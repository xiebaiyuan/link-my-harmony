import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createDefaultSessionState,
  parseSessionState,
  serializeSessionState,
} from './session-state.mjs';
import { DEFAULT_INSTANCE_URL } from './query-utils.mjs';

test('createDefaultSessionState returns unauthenticated defaults', () => {
  assert.deepEqual(createDefaultSessionState(), {
    instance: DEFAULT_INSTANCE_URL,
    token: '',
    theme: 'system',
  });
});

test('serializeSessionState keeps only persisted fields', () => {
  const result = serializeSessionState({
    instance: 'https://self-hosted.example',
    token: 'abc123',
    theme: 'dark',
    username: 'ignored',
  });

  assert.equal(result, '{"instance":"https://self-hosted.example","token":"abc123","theme":"dark"}');
});

test('parseSessionState falls back on invalid JSON', () => {
  assert.deepEqual(parseSessionState('not-json'), createDefaultSessionState());
});

test('parseSessionState ignores invalid theme values', () => {
  assert.deepEqual(parseSessionState('{"instance":"https://a.example","token":"t","theme":"blue"}'), {
    instance: 'https://a.example',
    token: 't',
    theme: 'system',
  });
});
