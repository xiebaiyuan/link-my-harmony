import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createDefaultSessionState,
  parseSessionState,
  serializeSessionState,
} from './session-state.mjs';
import { DEFAULT_INSTANCE_URL } from './query-utils.mjs';

test('createDefaultSessionState returns unauthenticated online defaults', () => {
  assert.deepEqual(createDefaultSessionState(), {
    instance: DEFAULT_INSTANCE_URL,
    token: '',
    theme: 'system',
    mode: 'online',
  });
});

test('serializeSessionState keeps only persisted fields', () => {
  const result = serializeSessionState({
    instance: 'https://self-hosted.example',
    token: 'abc123',
    theme: 'dark',
    mode: 'offline',
    username: 'ignored',
  });

  assert.equal(
    result,
    '{"instance":"https://self-hosted.example","token":"abc123","theme":"dark","mode":"offline"}',
  );
});

test('parseSessionState falls back on invalid JSON', () => {
  assert.deepEqual(parseSessionState('not-json'), createDefaultSessionState());
});

test('parseSessionState ignores invalid theme values', () => {
  assert.deepEqual(
    parseSessionState('{"instance":"https://a.example","token":"t","theme":"blue","mode":"online"}'),
    {
      instance: 'https://a.example',
      token: 't',
      theme: 'system',
      mode: 'online',
    },
  );
});

test('parseSessionState defaults mode to online for older payloads missing the field', () => {
  const legacyPayload = '{"instance":"https://a.example","token":"t","theme":"dark"}';
  assert.equal(parseSessionState(legacyPayload).mode, 'online');
});

test('parseSessionState normalizes an unknown mode to online', () => {
  const payload = '{"instance":"https://a.example","token":"","theme":"system","mode":"weird"}';
  assert.equal(parseSessionState(payload).mode, 'online');
});

test('parseSessionState preserves offline mode', () => {
  const payload = '{"instance":"https://a.example","token":"","theme":"system","mode":"offline"}';
  const state = parseSessionState(payload);
  assert.equal(state.mode, 'offline');
  assert.equal(state.token, '');
});
