#!/usr/bin/env npx ts-node
/**
 * Asks for a fresh draft of one alert, as an approver's "request a new draft" would:
 * the alert goes back to Drafting and the deployed trigger drafts it again. Used when a
 * draft was written by an older template.
 * Dry by default: it prints the alert and writes nothing. `--apply` writes.
 *
 *   npx ts-node scripts/redraft-alert.ts <alertUid> <approverUid>
 *   npx ts-node scripts/redraft-alert.ts <alertUid> <approverUid> --apply
 *
 * Against the live project, `--apply` also needs SEED_CONFIRM set to the project id.
 */
import { getApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

import { requestAlertDraftHandler } from '../src/alert-drafts';
import { PROJECT } from '../src/seed';

const APPLY = process.argv.includes('--apply');
const [alertUid = '', approverUid = ''] = process.argv.slice(2).filter((a) => !a.startsWith('--'));

async function main(): Promise<void> {
  if (alertUid === '' || approverUid === '') {
    throw new Error('Usage: redraft-alert.ts <alertUid> <approverUid> [--apply]');
  }
  const onEmulator = process.env.FIRESTORE_EMULATOR_HOST !== undefined;
  if (APPLY && !onEmulator && process.env.SEED_CONFIRM !== PROJECT) {
    throw new Error(`Writing the live project needs SEED_CONFIRM=${PROJECT}.`);
  }
  try {
    getApp();
  } catch {
    initializeApp({ projectId: onEmulator ? 'demo-tabibu' : PROJECT });
  }
  const db = getFirestore();
  const alert = (await db.collection('alerts').doc(alertUid).get()).data();
  if (!alert) throw new Error(`No alert ${alertUid}.`);
  const headline = (alert.machineText?.patient_en?.headline as string | undefined) ?? '';
  console.log(JSON.stringify({ alertUid, status: alert.status, requestCount: alert.requestCount ?? 0, headline }));
  if (!APPLY) {
    console.log('Dry run only. Pass --apply to write.');
    return;
  }
  // The handler re-checks everything an approver's request would: the approver row, the
  // alert's state and the redraft limit.
  const account = await getAuth().getUser(approverUid);
  const result = await requestAlertDraftHandler(
    { db },
    {
      uid: approverUid,
      email: account.email ?? '',
      emailVerified: account.emailVerified,
      role: 'Doctor',
      isAdmin: true,
    },
    { alertUid },
  );
  console.log(JSON.stringify(result));
}

if (require.main === module) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : 'Redraft failed.');
    process.exitCode = 1;
  });
}
