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

async function buildPlan(db: Firestore): Promise<{
  set: { caseUid: string; openMdtUid: string }[];
  clear: { caseUid: string; openMdtUid: string }[];
  unchanged: number;
  conflicts: { caseUid: string; conversationUids: string[] }[];
}> {
  const snap = await db.collection('conversations').where('type', '==', 'GroupConsult').get();
  const open = new Map<string, OpenConsult[]>();
  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.status !== 'Open' || data.linkedResourceType !== 'Order') continue;
    const caseUid = typeof data.linkedResourceUid === 'string' ? data.linkedResourceUid : '';
    if (caseUid === '') continue;
    const list = open.get(caseUid) ?? [];
    list.push({ conversationUid: doc.id });
    open.set(caseUid, list);
  }

  const set: { caseUid: string; openMdtUid: string }[] = [];
  const clear: { caseUid: string; openMdtUid: string }[] = [];
  const conflicts: { caseUid: string; conversationUids: string[] }[] = [];
  let unchanged = 0;

  for (const [caseUid, consults] of open) {
    const caseSnap = await db.collection('cases').doc(caseUid).get();
    if (!caseSnap.exists) {
      conflicts.push({
        caseUid,
        conversationUids: consults.map((c) => c.conversationUid),
      });
      continue;
    }
    const current = caseSnap.get('openMdtUid');
    const recorded = typeof current === 'string' ? current : '';
    if (consults.length !== 1) {
      conflicts.push({
        caseUid,
        conversationUids: consults.map((c) => c.conversationUid),
      });
      continue;
    }
    const only = consults[0].conversationUid;
    if (recorded === only) {
      unchanged += 1;
      continue;
    }
    set.push({ caseUid, openMdtUid: only });
  }

  const recorded = await db.collection('cases').select('openMdtUid').get();
  for (const doc of recorded.docs) {
    const current = doc.get('openMdtUid');
    if (typeof current !== 'string' || current === '') continue;
    const consults = open.get(doc.id) ?? [];
    if (consults.some((c) => c.conversationUid === current)) continue;
    if (consults.length > 1) continue;
    clear.push({ caseUid: doc.id, openMdtUid: '' });
  }

  return { set, clear, unchanged, conflicts };
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : 'Backfill failed.');
  process.exitCode = 1;
});
