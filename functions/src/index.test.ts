import assert from 'node:assert/strict';

import * as fns from './index';

interface ManifestEndpoint {
  timeoutSeconds?: number;
  secretEnvironmentVariables?: { key: string }[];
}

function endpointOf(fn: unknown): ManifestEndpoint {
  return (fn as { __endpoint?: ManifestEndpoint }).__endpoint ?? {};
}

function secretsOf(fn: unknown): string[] {
  return (endpointOf(fn).secretEnvironmentVariables ?? []).map((s) => s.key).sort();
}

describe('index secret bindings', () => {
  it('binds a secret only on the share-code functions', () => {
    const bound: string[] = [];
    for (const [name, fn] of Object.entries(fns)) {
      if (secretsOf(fn).length > 0) bound.push(name);
    }
    assert.deepEqual(bound.sort(), [
      'createShareCode',
      'redeemShareCode',
      'reissueShareCode',
      'signReport',
    ]);
    for (const name of bound) {
      assert.deepEqual(secretsOf((fns as Record<string, unknown>)[name]), ['SHARE_CODE_KEY']);
    }
  });

  it('exposes recordSymptomTranscript with no secret', () => {
    assert.equal(typeof fns.recordSymptomTranscript, 'function');
    assert.deepEqual(secretsOf(fns.recordSymptomTranscript), []);
  });

  it('keeps the longer timeout on the model-calling triggers', () => {
    for (const name of [
      'onCaseWritten',
      'onPrereadWritten',
      'onReportTextWritten',
      'onAppointmentWritten',
      'onMessageCreated',
      'onAlertWritten',
    ] as const) {
      assert.ok(
        (endpointOf(fns[name]).timeoutSeconds ?? 0) >= 120,
        `${name} lost its model-call timeout`,
      );
    }
  });
});
