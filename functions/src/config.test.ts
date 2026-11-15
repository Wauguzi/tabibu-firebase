import assert from 'node:assert/strict';

import { configString, isEnabled, remoteConfigReader, type ServerTemplateLike } from './config';

function template(
  values: { on: boolean; text?: string },
  state: { failing: boolean },
): ServerTemplateLike {
  return {
    load() {
      return state.failing ? Promise.reject(new Error('unreachable')) : Promise.resolve();
    },
    evaluate: () => ({ getBoolean: () => values.on, getString: () => values.text ?? '' }),
  };
}

describe('remoteConfigReader', () => {
  it('reads off before the first load', () => {
    const reader = remoteConfigReader(template({ on: true }, { failing: false }));
    assert.equal(reader.enabled('preread_enabled'), false);
  });

  it('reads the switch after a load', async () => {
    const reader = remoteConfigReader(template({ on: true }, { failing: false }));
    await reader.refresh();
    assert.equal(reader.enabled('preread_enabled'), true);
  });

  it('keeps the cache through a short outage and drops it after several periods', async () => {
    let now = 1_000_000;
    const state = { failing: false };
    const reader = remoteConfigReader(template({ on: true }, state), 60_000, () => now);
    await reader.refresh();
    state.failing = true;

    now += 3 * 60_000;
    await reader.refresh();
    assert.equal(reader.enabled('preread_enabled'), true);

    now += 3 * 60_000;
    await reader.refresh();
    assert.equal(reader.enabled('preread_enabled'), false);

    state.failing = false;
    await reader.refresh();
    assert.equal(reader.enabled('preread_enabled'), true);
  });

  it('reads a string param after a load, and the fallback before it', async () => {
    const reader = remoteConfigReader(
      template({ on: true, text: 'gemini-3.8-flash' }, { failing: false }),
    );
    assert.equal(configString(reader, 'ai_text_model', 'fallback'), 'fallback');
    await reader.refresh();
    assert.equal(configString(reader, 'ai_text_model', 'fallback'), 'gemini-3.8-flash');
  });

  it('configString falls back for no reader, an empty value and a throwing one', async () => {
    assert.equal(configString(undefined, 'ai_location', 'global'), 'global');
    const empty = remoteConfigReader(template({ on: true }, { failing: false }));
    await empty.refresh();
    assert.equal(configString(empty, 'ai_location', 'global'), 'global');
    assert.equal(
      configString(
        {
          stringValue: () => {
            throw new Error('boom');
          },
        },
        'ai_location',
        'global',
      ),
      'global',
    );
  });

  it('isEnabled fails closed for no reader and for a throwing one', () => {
    assert.equal(isEnabled(undefined, 'x'), false);
    assert.equal(
      isEnabled(
        {
          enabled: () => {
            throw new Error('boom');
          },
        },
        'x',
      ),
      false,
    );
  });
});
