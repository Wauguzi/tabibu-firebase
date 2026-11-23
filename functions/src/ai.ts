// cspell:ignore Dalili historia zinaweza kuendana homa virusi kuvuja damu Fuata itifaki Wizara kabla sampuli haijasafirishwa
/**
 * The seam to the AI service. Handlers take `deps.ai`; model calls go only through the
 * injected `GeminiGenerate`, never a direct call. Inputs are de-identified before they get
 * here (S-5).
 */

export type NotesLanguage = 'en' | 'sw' | 'mixed' | '';
export type AiFailureReason = 'Timeout' | 'ServiceError' | 'OffSchema' | 'Stale';

export class AiError extends Error {
  constructor(
    readonly reason: AiFailureReason,
    message = reason,
  ) {
    super(message);
    this.name = 'AiError';
  }
}

/** The longest a handler waits on the service; a late answer is dropped, not retried. */
export const AI_TIMEOUT_MS = 60_000;

/**
 * Rejects with a `Timeout` `AiError` when `work` has not settled in `ms`.
 * `abort` is only for a caller that passed a signal into the request: the timer
 * cancels that request so a retry is not a second live call. Other callers pass
 * nothing and are left running, as before.
 */
export function withTimeout<T>(
  work: Promise<T>,
  ms: number = AI_TIMEOUT_MS,
  abort?: AbortController,
): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  if (abort) {
    // Aborting rejects `work` after this promise has already settled as Timeout.
    void work.catch(() => undefined);
  }
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      reject(new AiError('Timeout'));
      abort?.abort();
    }, ms);
  });
  return Promise.race([work, timeout]).finally(() => clearTimeout(timer));
}

/** Everything the risk check and the notes translation may see. No name, id or order number. */
export interface CaseAiRequest {
  labTestIds: string[];
  sex: string;
  ageBand: string;
  county: string;
  notes: string;
}

export interface CaseAiResult {
  inputLanguage: NotesLanguage;
  suggestedLabTestIds: string[];
  advisoryKey: string;
  translation: { language: 'en' | 'sw'; text: string };
  models: Record<string, string>;
}

export interface MeasureRequest {
  runUid: string;
  labelOverrides: Record<string, string>;
}

export interface AiClient {
  /** One call for the risk check and the translation of the doctor's own notes. */
  assessCase(request: CaseAiRequest): Promise<CaseAiResult>;
  /** Recomputes measurements from relabelled tiles. Absent until the service has it. */
  measure?(request: MeasureRequest): Promise<{ measurements: Record<string, number> }>;
}

/** S-7: the model only selects a key. The words the doctor reads are these. */
export const ADVISORIES: Readonly<Record<string, { en: string; sw: string }>> = {
  VhfProtocol: {
    en: 'The symptoms and history may fit a viral haemorrhagic fever. Follow Ministry of Health protocol before the sample travels.',
    sw: 'Dalili na historia zinaweza kuendana na homa ya virusi vya kuvuja damu. Fuata itifaki ya Wizara ya Afya kabla sampuli haijasafirishwa.',
  },
};

/** The language a translation of notes written in `language` is made into. */
export function otherLanguage(language: NotesLanguage): 'en' | 'sw' {
  return language === 'sw' ? 'en' : language === 'en' ? 'sw' : 'en';
}

/** Fixtures only: it never leaves the process. Tests inject their own fakes for failures. */
export const stubAiClient: AiClient = {
  assessCase(request) {
    return Promise.resolve({
      inputLanguage: request.notes === '' ? '' : 'en',
      suggestedLabTestIds: [],
      advisoryKey: '',
      translation: { language: 'sw', text: request.notes === '' ? '' : 'Tafsiri ya majaribio.' },
      models: { stub: 'fixture' },
    });
  },
  measure() {
    return Promise.resolve({ measurements: {} });
  },
};
