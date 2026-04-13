import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeInstanceUrl, buildQueryString } from './query-utils.mjs';

test('normalizeInstanceUrl adds https scheme and trims trailing slash', () => {
  assert.equal(normalizeInstanceUrl('cloud.linkwarden.app/'), 'https://cloud.linkwarden.app');
  assert.equal(normalizeInstanceUrl('http://localhost:3000///'), 'http://localhost:3000');
});

test('buildQueryString skips undefined values and encodes spaces', () => {
  const query = buildQueryString({
    cursor: 0,
    searchQueryString: 'hello world',
    pinnedOnly: true,
    collectionId: undefined,
  });

  assert.equal(query, 'cursor=0&searchQueryString=hello%20world&pinnedOnly=true');
});
