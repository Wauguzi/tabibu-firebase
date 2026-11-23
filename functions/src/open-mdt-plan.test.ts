import assert from 'node:assert/strict';

import { planOpenMdt } from '../scripts/backfill-open-mdt';

describe('planOpenMdt', () => {
  it('repairs one different open consult and does not clear it', () => {
    const plan = planOpenMdt(
      [{ id: 'case-1', openMdtUid: 'old' }],
      [{ caseUid: 'case-1', conversationUid: 'new' }],
    );

    assert.deepEqual(plan.set, [{ caseUid: 'case-1', openMdtUid: 'new' }]);
    assert.deepEqual(plan.clear, []);
  });

  it('clears a recorded link only when nothing is open', () => {
    const plan = planOpenMdt([{ id: 'case-1', openMdtUid: 'old' }], []);

    assert.deepEqual(plan.set, []);
    assert.deepEqual(plan.clear, [{ caseUid: 'case-1', openMdtUid: '' }]);
  });

  it('leaves a matching link and a conflict untouched', () => {
    const plan = planOpenMdt(
      [
        { id: 'ok', openMdtUid: 'same' },
        { id: 'two', openMdtUid: 'old' },
      ],
      [
        { caseUid: 'ok', conversationUid: 'same' },
        { caseUid: 'two', conversationUid: 'a' },
        { caseUid: 'two', conversationUid: 'b' },
      ],
    );

    assert.deepEqual(plan.set, []);
    assert.deepEqual(plan.clear, []);
    assert.deepEqual(plan.conflicts.map((row) => row.caseUid), ['two']);
    assert.equal(plan.unchanged, 1);
  });
});
