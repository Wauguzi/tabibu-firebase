#!/usr/bin/env npx ts-node
/**
 * Record each case's one open consult on the case (`openMdtUid`).
 * Dry by default: it prints the plan and writes nothing. `--apply` writes.
 * A case with more than one open consult is printed and left unchanged.
 *
 *   npx ts-node scripts/backfill-open-mdt.ts
 *   npx ts-node scripts/backfill-open-mdt.ts --apply
 *
 * Against the live project, `--apply` also needs SEED_CONFIRM set to the
 * project id. The emulators need no confirm.
 */
import { getApp, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

import { PROJECT } from '../src/seed';

const APPLY = process.argv.includes('--apply');

interface OpenConsult {
  conversationUid: string;
}

async function main(): Promise<void> {
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
  const plan = await buildPlan(db);
  console.log(
    JSON.stringify(
      {
        apply: APPLY,
        project: onEmulator ? 'emulators' : PROJECT,
        set: plan.set.length,
        clear: plan.clear.length,
        unchanged: plan.unchanged,
        conflicts: plan.conflicts,
      },
      null,
      2,
    ),
  );
  if (!APPLY) {
    console.log('Dry run only. Pass --apply to write.');
    return;
  }

  let written = 0;
  for (const row of [...plan.set, ...plan.clear]) {
    await db.collection('cases').doc(row.caseUid).update({
      openMdtUid: row.openMdtUid,
      lastUpdatedAt: new Date().toISOString(),
    });
    written += 1;
  }
  console.log(JSON.stringify({ written }));
}

export interface RecordedOpenMdt {
  id: string;
  openMdtUid: string;
}

export interface OpenConsultLink {
  caseUid: string;
  conversationUid: string;
}

export interface OpenMdtPlan {
  set: { caseUid: string; openMdtUid: string }[];
  clear: { caseUid: string; openMdtUid: string }[];
  unchanged: number;
  conflicts: { caseUid: string; conversationUids: string[] }[];
}

/**
 * Set and clear never name the same case. A single different open consult is
 * repaired. A recorded link is cleared only when that case has no open consult.
 */
export function planOpenMdt(
  recorded: readonly RecordedOpenMdt[],
  consults: readonly OpenConsultLink[],
): OpenMdtPlan {
  const open = new Map<string, OpenConsult[]>();
  for (const consult of consults) {
    const list = open.get(consult.caseUid) ?? [];
    list.push({ conversationUid: consult.conversationUid });
    open.set(consult.caseUid, list);
  }
  const recordedById = new Map(recorded.map((row) => [row.id, row.openMdtUid]));

  const set: OpenMdtPlan['set'] = [];
  const conflicts: OpenMdtPlan['conflicts'] = [];
  let unchanged = 0;

  for (const [caseUid, rows] of open) {
    if (!recordedById.has(caseUid)) {
      conflicts.push({
        caseUid,
        conversationUids: rows.map((row) => row.conversationUid),
      });
      continue;
    }
    const current = recordedById.get(caseUid) ?? '';
    if (rows.length !== 1) {
      conflicts.push({
        caseUid,
        conversationUids: rows.map((row) => row.conversationUid),
      });
      continue;
    }
    const only = rows[0].conversationUid;
    if (current === only) {
      unchanged += 1;
      continue;
    }
    set.push({ caseUid, openMdtUid: only });
  }

  const setting = new Set(set.map((row) => row.caseUid));
  const clear: OpenMdtPlan['clear'] = [];
  for (const row of recorded) {
    if (row.openMdtUid === '') continue;
    if (setting.has(row.id)) continue;
    const rows = open.get(row.id) ?? [];
    if (rows.length !== 0) continue;
    clear.push({ caseUid: row.id, openMdtUid: '' });
  }

  return { set, clear, unchanged, conflicts };
}

async function buildPlan(db: Firestore): Promise<OpenMdtPlan> {
  const snap = await db.collection('conversations').where('type', '==', 'GroupConsult').get();
  const consults: OpenConsultLink[] = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.status !== 'Open' || data.linkedResourceType !== 'Order') continue;
    const caseUid = typeof data.linkedResourceUid === 'string' ? data.linkedResourceUid : '';
    if (caseUid === '') continue;
    consults.push({ caseUid, conversationUid: doc.id });
  }

  const recordedDocs = await db.collection('cases').select('openMdtUid').get();
  const recorded = recordedDocs.docs.map((doc) => {
    const current = doc.get('openMdtUid');
    return {
      id: doc.id,
      openMdtUid: typeof current === 'string' ? current : '',
    };
  });
  return planOpenMdt(recorded, consults);
}

if (require.main === module) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : 'Backfill failed.');
    process.exitCode = 1;
  });
}
