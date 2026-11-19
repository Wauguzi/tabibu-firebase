import assert from 'node:assert/strict';

import { AiError, withTimeout } from './ai';

describe('withTimeout', () => {
  it('aborts a passed controller when the timer fires', async () => {
    const abort = new AbortController();
    const work = new Promise<string>(() => undefined);
    await assert.rejects(withTimeout(work, 20, abort), (error: unknown) => {
      assert.ok(error instanceof AiError);
      assert.equal(error.reason, 'Timeout');
      return true;
    });
    assert.equal(abort.signal.aborted, true);
  });

  it('does not need a controller for a call that finishes', async () => {
    const value = await withTimeout(Promise.resolve('ok'), 200);
    assert.equal(value, 'ok');
  });
});
