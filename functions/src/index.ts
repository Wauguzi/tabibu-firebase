/**
 * Cloud Functions entry point: callables and triggers for identity, cases, appointments,
 * conversations, reports, shares, push and outbreak alerts. AI clients are built per
 * invocation from the kill switches and the server Remote Config; only the share-code
 * callables bind a secret, and no function binds a model key.
 */
import { setGlobalOptions } from 'firebase-functions/v2';
import { onCall } from 'firebase-functions/v2/https';
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { defineSecret } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { getRemoteConfig } from 'firebase-admin/remote-config';
import { getStorage } from 'firebase-admin/storage';

import {
  acceptCaseHandler,
  cancelOrderHandler,
  completeCaseHandler,
  createOrderHandler,
  onCaseWrittenHandler,
  reassignPathologistHandler,
  recordSampleReceivedHandler,
  registerSlidesHandler,
  rejectCaseHandler,
  removeCaseViewerHandler,
  requestPathologistHandler,
  reserveSlideUploadsHandler,
  sweepCasesHandler,
} from './cases';
import {
  cancelAppointmentHandler,
  completeAppointmentHandler,
  expireAppointmentsHandler,
  onAppointmentWrittenHandler,
  recordSymptomTranscriptHandler,
  requestAppointmentHandler,
  respondToAppointmentHandler,
} from './appointments';
import { Deps as DomainDeps } from './case-support';
import { callerOf, type Caller } from './common';
import {
  AI_LOCATION_PARAM,
  AI_TEXT_MODEL_PARAM,
  GEMINI_LOCATION_DEFAULT,
  GEMINI_TEXT_MODEL,
  createGeminiGenerate,
  resolveAlertAiClient,
  resolveGeminiAiClient,
  type GeminiGenerate,
} from './ai-gemini';
import { configString, isEnabled, KILL_SWITCHES, remoteConfigReader } from './config';
import {
  closeConversationHandler,
  inviteToMdtHandler,
  leaveMdtHandler,
  onMessageCreatedHandler,
  openDirectConversationHandler,
  openMdtHandler,
  removeFromMdtHandler,
  respondToMdtInviteHandler,
  shareTranscriptHandler,
  sweepConversationsHandler,
  withdrawMessageHandler,
} from './conversations';
import {
  Deps,
  addPatientHandler,
  completePatientSignUpHandler,
  completePractitionerSignUpHandler,
  linkPatientAccountHandler,
  syncPractitionerHandler,
  verifyPractitionerHandler,
} from './identity';
import {
  backfillAvailabilityHandler,
  registerStaffTokenHandler,
  resumeLinkJobsHandler,
  setAlertApproverHandler,
  updatePatientAreaHandler,
} from './identity-extras';
import { sendPushHandler } from './push';
import type { MessagingLike, RuntimeDeps } from './runtime-deps';
import {
  approveReportTextHandler,
  discardDraftHandler,
  markDiscussedHandler,
  onPrereadWrittenHandler,
  onReportCreatedHandler,
  onReportDraftWrittenHandler,
  onReportTextWrittenHandler,
  requestReportTextHandler,
  scorePrereadHandler,
  signReportHandler,
  startReportHandler,
} from './reports';
import {
  createShareCodeHandler,
  reissueShareCodeHandler,
  redeemShareCodeHandler,
  revokeShareCodeHandler,
} from './shares-callables';
import type { AlertDeps } from './alert-deps';
import { onNotifiableEventWrittenHandler } from './alert-detector';
import { runAlertSweep } from './alert-sweep';
import {
  approveAlertHandler,
  onAlertWrittenHandler,
  requestAlertDraftHandler,
} from './alert-drafts';
import { aggregateModelSignals as aggregateModelSignalsHandler } from './model-signals';

initializeApp();

// europe-west1 sits inside the database's eur3 location. The instance cap bounds the cost of
// a scripted burst until App Check is enforced.
setGlobalOptions({ region: 'europe-west1', maxInstances: 10 });

function deps(): Deps {
  return { db: getFirestore(), auth: getAuth(), bucket: getStorage().bucket().name };
}

export const completePatientSignUp = onCall((request) =>
  completePatientSignUpHandler(deps(), callerOf(request), request.data),
);

export const completePractitionerSignUp = onCall((request) =>
  completePractitionerSignUpHandler(deps(), callerOf(request), request.data),
);

export const verifyPractitioner = onCall((request) =>
  verifyPractitionerHandler(deps(), callerOf(request), request.data),
);

export const addPatient = onCall((request) =>
  addPatientHandler(deps(), callerOf(request), request.data),
);

export const linkPatientAccount = onCall((request) =>
  linkPatientAccountHandler(deps(), callerOf(request), request.data),
);

// Retried on failure: the handler reads the stored profile, so running it twice is safe.
export const syncPractitioner = onDocumentWritten({ document: 'doctors/{uid}', retry: true }, async (event) => {
  await syncPractitionerHandler(getFirestore(), event.params.uid);
});

// --- Cases, share codes and reports ----------------------------------------------------------

// A Firebase secret parameter: its value is bound at deploy time and never appears in the source.
const shareCodeKey = defineSecret('SHARE_CODE_KEY');

// Every switch is `false` until Remote Config says otherwise, and reads `false` when the template
// cannot be loaded. The model location and id fall back to their in-app defaults.
const switches = remoteConfigReader(
  getRemoteConfig().initServerTemplate({
    defaultConfig: {
      ...Object.fromEntries(KILL_SWITCHES.map((key) => [key, false])),
      [AI_LOCATION_PARAM]: GEMINI_LOCATION_DEFAULT,
      [AI_TEXT_MODEL_PARAM]: GEMINI_TEXT_MODEL,
    },
  }),
);

/** Gemini on the Agent Platform through the Functions service account; no key anywhere. */
function geminiTransport(): GeminiGenerate {
  return createGeminiGenerate({
    location: configString(switches, AI_LOCATION_PARAM, GEMINI_LOCATION_DEFAULT),
  });
}

function liveAiClient() {
  return resolveGeminiAiClient({
    generate: geminiTransport(),
    model: configString(switches, AI_TEXT_MODEL_PARAM, GEMINI_TEXT_MODEL),
    riskCheckEnabled: isEnabled(switches, 'risk_check_enabled'),
    symptomIntakeEnabled: isEnabled(switches, 'symptom_intake_enabled'),
    voiceInputEnabled: isEnabled(switches, 'voice_input_enabled'),
  });
}

// The live client is attached only when a switch is on; otherwise each AI job records Failed.
async function domainDeps(withShareKey = false): Promise<DomainDeps> {
  await switches.refresh();
  return {
    db: getFirestore(),
    auth: getAuth(),
    bucket: getStorage().bucket().name,
    config: switches,
    ai: liveAiClient(),
    shareCodeKey: withShareKey ? shareCodeKey.value() : undefined,
    synthetic: process.env.ALERTS_SYNTHETIC === 'true',
  };
}

type DomainHandler = (deps: DomainDeps, caller: Caller | null, data: unknown) => Promise<unknown>;

const domainCall = (handler: DomainHandler) =>
  onCall(async (request) => handler(await domainDeps(), callerOf(request), request.data));

const keyedCall = (handler: DomainHandler) =>
  onCall({ secrets: [shareCodeKey] }, async (request) =>
    handler(await domainDeps(true), callerOf(request), request.data),
  );

export const createOrder = domainCall(createOrderHandler);
export const requestPathologist = domainCall(requestPathologistHandler);
export const acceptCase = domainCall(acceptCaseHandler);
export const rejectCase = domainCall(rejectCaseHandler);
export const reassignPathologist = domainCall(reassignPathologistHandler);
export const recordSampleReceived = domainCall(recordSampleReceivedHandler);
export const reserveSlideUploads = domainCall(reserveSlideUploadsHandler);
export const registerSlides = domainCall(registerSlidesHandler);
export const cancelOrder = domainCall(cancelOrderHandler);
export const completeCase = domainCall(completeCaseHandler);
export const removeCaseViewer = domainCall(removeCaseViewerHandler);

export const createShareCode = keyedCall(createShareCodeHandler);
export const redeemShareCode = keyedCall(redeemShareCodeHandler);
export const revokeShareCode = domainCall(revokeShareCodeHandler);
export const reissueShareCode = keyedCall(reissueShareCodeHandler);

export const startReport = domainCall(startReportHandler);
export const discardDraft = domainCall(discardDraftHandler);
export const scorePreread = domainCall(scorePrereadHandler);
export const signReport = keyedCall(signReportHandler);
export const markDiscussed = domainCall(markDiscussedHandler);
export const approveReportText = domainCall(approveReportTextHandler);
export const requestReportText = domainCall(requestReportTextHandler);

// Triggers retry on failure and re-read the current documents, so a redelivery is safe. The AI
// calls in onCaseWritten need the longer timeout.
export const onCaseWritten = onDocumentWritten(
  {
    document: 'cases/{caseUid}',
    retry: true,
    timeoutSeconds: 120,
  },
  async (event) => {
    await onCaseWrittenHandler(
      await domainDeps(),
      event.params.caseUid,
      event.data?.before.data(),
      event.data?.after.data(),
    );
  },
);

export const onPrereadWritten = onDocumentWritten(
  {
    document: 'cases/{caseUid}/preread/{runUid}',
    retry: true,
    timeoutSeconds: 300,
    // A 4,096 px slide decodes to tens of megabytes, and the resize copies it.
    memory: '1GiB',
  },
  async (event) => {
    await onPrereadWrittenHandler(await domainDeps(), event.params.caseUid, event.params.runUid);
  },
);

export const onReportCreated = onDocumentCreated(
  { document: 'cases/{caseUid}/reports/{reportUid}', retry: true },
  async (event) => {
    await onReportCreatedHandler(await domainDeps(), event.params.caseUid, event.params.reportUid);
  },
);

// Writes the measurement preview a relabelled draft needs before it can be signed (S-2). With no
// `ai` client wired it records a `Failed` preview, and `signReport` refuses the overrides.
export const onReportDraftWritten = onDocumentWritten(
  { document: 'cases/{caseUid}/reportDrafts/{pathologistUid}', retry: true, timeoutSeconds: 120 },
  async (event) => {
    await onReportDraftWrittenHandler(
      await domainDeps(),
      event.params.caseUid,
      event.params.pathologistUid,
      event.data?.after.data(),
    );
  },
);

export const onReportTextWritten = onDocumentWritten(
  {
    document: 'cases/{caseUid}/reportTexts/{textId}',
    retry: true,
    timeoutSeconds: 180,
  },
  async (event) => {
    await onReportTextWrittenHandler(await domainDeps(), event.params.caseUid, event.params.textId);
  },
);

// The alert kinds ride the same schedule; each half runs even when the other throws.
export const sweepCases = onSchedule('every 5 minutes', async () => {
  // Resolve deps first so a deps failure does not leave one half already in flight.
  const [domain, alerts] = await Promise.all([domainDeps(), alertDeps()]);
  const [casesResult, alertsResult] = await Promise.allSettled([
    sweepCasesHandler(domain),
    runAlertSweep(alerts, new Date()),
  ]);
  const failed = [casesResult, alertsResult].filter((r) => r.status === 'rejected');
  if (failed.length === 0) return;
  for (const r of failed) {
    logger.error('sweepCases half failed', {
      reason: String((r as PromiseRejectedResult).reason),
    });
  }
  throw (failed[0] as PromiseRejectedResult).reason;
});

// --- Appointments, conversations, push and staff ---------------------------------------------

async function runtimeDeps(): Promise<RuntimeDeps> {
  await switches.refresh();
  return {
    db: getFirestore(),
    auth: getAuth(),
    bucket: getStorage().bucket().name,
    config: switches,
    ai: liveAiClient(),
    messaging: getMessaging() as unknown as MessagingLike,
    storage: getStorage(),
  };
}

type RuntimeHandler = (deps: RuntimeDeps, caller: Caller | null, data: unknown) => Promise<unknown>;

const runtimeCall = (handler: RuntimeHandler) =>
  onCall(async (request) => handler(await runtimeDeps(), callerOf(request), request.data));

export const requestAppointment = runtimeCall(requestAppointmentHandler);
export const respondToAppointment = runtimeCall(respondToAppointmentHandler);
export const cancelAppointment = runtimeCall(cancelAppointmentHandler);
export const completeAppointment = runtimeCall(completeAppointmentHandler);
// The app transcribes on the device; this call only records the transcript it sends.
export const recordSymptomTranscript = runtimeCall(recordSymptomTranscriptHandler);

export const openDirectConversation = runtimeCall(openDirectConversationHandler);
export const openMdt = runtimeCall(openMdtHandler);
export const inviteToMdt = runtimeCall(inviteToMdtHandler);
export const respondToMdtInvite = runtimeCall(respondToMdtInviteHandler);
export const leaveMdt = runtimeCall(leaveMdtHandler);
export const removeFromMdt = runtimeCall(removeFromMdtHandler);
export const closeConversation = runtimeCall(closeConversationHandler);
export const withdrawMessage = runtimeCall(withdrawMessageHandler);
export const shareTranscript = runtimeCall(shareTranscriptHandler);

export const updatePatientArea = runtimeCall(updatePatientAreaHandler);
export const registerStaffToken = runtimeCall(registerStaffTokenHandler);
export const setAlertApprover = runtimeCall(setAlertApproverHandler);
export const backfillAvailability = runtimeCall(backfillAvailabilityHandler);

export const onAppointmentWritten = onDocumentWritten(
  {
    document: 'appointments/{appointmentUid}',
    retry: true,
    timeoutSeconds: 120,
  },
  async (event) => {
    await onAppointmentWrittenHandler(
      await runtimeDeps(),
      event.params.appointmentUid,
      event.data?.before.data(),
      event.data?.after.data(),
    );
  },
);

export const onMessageCreated = onDocumentCreated(
  {
    document: 'conversations/{conversationUid}/messages/{messageUid}',
    retry: true,
    timeoutSeconds: 120,
  },
  async (event) => {
    await onMessageCreatedHandler(await runtimeDeps(), event.params.conversationUid, event.params.messageUid);
  },
);

export const sendPush = onDocumentWritten({ document: 'notifications/{notificationUid}', retry: true }, async (event) => {
  await sendPushHandler(await runtimeDeps(), event.params.notificationUid, {
    before: event.data?.before.data(),
    after: event.data?.after.data(),
  });
});

export const expireAppointments = onSchedule('every 5 minutes', async () => {
  await expireAppointmentsHandler(await runtimeDeps());
});

export const sweepConversations = onSchedule('every 5 minutes', async () => {
  await sweepConversationsHandler(await runtimeDeps());
});

export const resumeLinkJobs = onSchedule('every 5 minutes', async () => {
  const { resumed, failed } = await resumeLinkJobsHandler(await runtimeDeps());
  // Counts only: a job's id is a patient's record id.
  logger.info('resumeLinkJobs', { resumed, failed });
});

// --- Outbreak alerts ------------------------------------------------------------------

// Live alert drafting: Gemini when the switch is on; otherwise the template.
async function alertDeps(): Promise<AlertDeps> {
  await switches.refresh();
  return {
    db: getFirestore(),
    topics: getMessaging(),
    config: switches,
    ai: resolveAlertAiClient({
      generate: geminiTransport(),
      model: configString(switches, AI_TEXT_MODEL_PARAM, GEMINI_TEXT_MODEL),
      alertDraftingEnabled: isEnabled(switches, 'alert_drafting_enabled'),
    }),
    synthetic: process.env.ALERTS_SYNTHETIC === 'true',
    patientDelayMin: Number(process.env.ALERT_PATIENT_DELAY_MIN ?? '0'),
  };
}

type AlertHandler = (deps: AlertDeps, caller: Caller | null, data: unknown) => Promise<unknown>;

const alertCall = (handler: AlertHandler) =>
  onCall(async (request) => handler(await alertDeps(), callerOf(request), request.data));

export const approveAlert = alertCall(approveAlertHandler);
export const requestAlertDraft = alertCall(requestAlertDraftHandler);

// Retried on failure: the handlers re-read the stored documents, so a redelivery is safe.
// Drafting calls the text model, so it gets the longer timeout.
export const onNotifiableEventWritten = onDocumentWritten(
  { document: 'notifiableEvents/{eventUid}', retry: true },
  async (event) => {
    await onNotifiableEventWrittenHandler(await alertDeps(), event.params.eventUid, {
      before: event.data?.before.data(),
      after: event.data?.after.data(),
    });
  },
);

export const onAlertWritten = onDocumentWritten(
  {
    document: 'alerts/{alertUid}',
    retry: true,
    timeoutSeconds: 120,
  },
  async (event) => {
    await onAlertWrittenHandler(await alertDeps(), event.params.alertUid, {
      before: event.data?.before.data(),
      after: event.data?.after.data(),
    });
  },
);

export const aggregateModelSignals = onSchedule(
  { schedule: '10 0 * * *', timeZone: 'Africa/Nairobi' },
  async () => {
    await aggregateModelSignalsHandler(await alertDeps());
  },
);
