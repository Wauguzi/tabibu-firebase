/** Plans each case's open-consult link for `scripts/backfill-open-mdt.ts`. */

interface OpenConsult {
  conversationUid: string;
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
