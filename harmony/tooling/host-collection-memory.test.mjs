import test from 'node:test';
import assert from 'node:assert/strict';
import {
  HOST_COLLECTION_SCORE_HALF_LIFE_MS,
  createDefaultHostCollectionMemory,
  extractHostname,
  findHostCollectionEntry,
  hostCollectionScore,
  parseHostCollectionMemory,
  pickBestCollectionForHost,
  recordHostChoice,
  serializeHostCollectionMemory,
} from './host-collection-memory.mjs';

test('createDefaultHostCollectionMemory returns empty entries', () => {
  assert.deepEqual(createDefaultHostCollectionMemory(), { entries: [] });
});

test('extractHostname lowercases and strips www', () => {
  assert.equal(extractHostname('https://WWW.Github.com/foo/bar'), 'github.com');
  assert.equal(extractHostname('http://news.ycombinator.com/item?id=1'), 'news.ycombinator.com');
  assert.equal(extractHostname('https://example.com'), 'example.com');
});

test('extractHostname returns empty on invalid input', () => {
  assert.equal(extractHostname(''), '');
  assert.equal(extractHostname('not a url'), '');
  assert.equal(extractHostname('ftp://example.com'), '');
  assert.equal(extractHostname(null), '');
  assert.equal(extractHostname(undefined), '');
});

test('extractHostname tolerates whitespace and trailing punctuation', () => {
  assert.equal(extractHostname('  https://example.com/page,  '), 'example.com');
  assert.equal(extractHostname('https://example.com:8443/x'), 'example.com');
});

test('recordHostChoice adds a new entry with count=1', () => {
  const now = 1_700_000_000_000;
  const state = recordHostChoice(createDefaultHostCollectionMemory(), 'github.com', 42, now);
  assert.deepEqual(state.entries, [{ host: 'github.com', collectionId: 42, count: 1, lastUsedAt: now }]);
});

test('recordHostChoice increments existing entry and moves to front', () => {
  const t0 = 1_000;
  const t1 = 2_000;
  const t2 = 3_000;
  let state = createDefaultHostCollectionMemory();
  state = recordHostChoice(state, 'github.com', 1, t0);
  state = recordHostChoice(state, 'news.ycombinator.com', 2, t1);
  state = recordHostChoice(state, 'github.com', 1, t2);
  assert.equal(state.entries.length, 2);
  assert.deepEqual(state.entries[0], { host: 'github.com', collectionId: 1, count: 2, lastUsedAt: t2 });
  assert.deepEqual(state.entries[1], { host: 'news.ycombinator.com', collectionId: 2, count: 1, lastUsedAt: t1 });
});

test('recordHostChoice keeps separate entries when same host used for different collections', () => {
  const t0 = 1_000;
  const t1 = 2_000;
  let state = createDefaultHostCollectionMemory();
  state = recordHostChoice(state, 'github.com', 1, t0);
  state = recordHostChoice(state, 'github.com', 2, t1);
  assert.equal(state.entries.length, 2);
  assert.ok(findHostCollectionEntry(state, 'github.com', 1));
  assert.ok(findHostCollectionEntry(state, 'github.com', 2));
});

test('recordHostChoice normalizes host via extractHostname', () => {
  const state = recordHostChoice(createDefaultHostCollectionMemory(), 'https://WWW.Example.com/x', 9, 1);
  assert.equal(state.entries.length, 1);
  assert.equal(state.entries[0].host, 'example.com');
});

test('recordHostChoice rejects empty host and non-positive collectionId', () => {
  const base = createDefaultHostCollectionMemory();
  assert.deepEqual(recordHostChoice(base, '', 1, 1), base);
  assert.deepEqual(recordHostChoice(base, 'github.com', 0, 1), base);
  assert.deepEqual(recordHostChoice(base, 'github.com', -3, 1), base);
});

test('findHostCollectionEntry returns null when missing', () => {
  const state = recordHostChoice(createDefaultHostCollectionMemory(), 'github.com', 7, 100);
  assert.equal(findHostCollectionEntry(state, 'github.com', 999), null);
  assert.equal(findHostCollectionEntry(state, 'other.com', 7), null);
  assert.deepEqual(
    findHostCollectionEntry(state, 'github.com', 7),
    { host: 'github.com', collectionId: 7, count: 1, lastUsedAt: 100 },
  );
});

test('hostCollectionScore handles null and future timestamps', () => {
  const now = 5_000;
  assert.equal(hostCollectionScore(null, now), 0);
  assert.equal(
    hostCollectionScore({ host: 'x.com', collectionId: 1, count: 3, lastUsedAt: now + 10 }, now),
    3,
  );
});

test('hostCollectionScore halves after one half-life', () => {
  const now = 10 * HOST_COLLECTION_SCORE_HALF_LIFE_MS;
  const entry = { host: 'x.com', collectionId: 1, count: 4, lastUsedAt: now - HOST_COLLECTION_SCORE_HALF_LIFE_MS };
  const score = hostCollectionScore(entry, now);
  assert.ok(Math.abs(score - 2) < 1e-9, `expected ~2, got ${score}`);
});

test('pickBestCollectionForHost returns 0 when host is unknown', () => {
  const state = recordHostChoice(createDefaultHostCollectionMemory(), 'github.com', 1, 100);
  assert.equal(pickBestCollectionForHost(state, 'other.com', 200), 0);
  assert.equal(pickBestCollectionForHost(state, '', 200), 0);
});

test('pickBestCollectionForHost picks the entry with the highest weighted score', () => {
  const now = 10 * HOST_COLLECTION_SCORE_HALF_LIFE_MS;
  let state = createDefaultHostCollectionMemory();
  // Collection 1: count=5 but 3 half-lives old → score ≈ 5 * 0.125 = 0.625
  state = recordHostChoice(state, 'github.com', 1, now - 3 * HOST_COLLECTION_SCORE_HALF_LIFE_MS);
  state = recordHostChoice(state, 'github.com', 1, now - 3 * HOST_COLLECTION_SCORE_HALF_LIFE_MS);
  state = recordHostChoice(state, 'github.com', 1, now - 3 * HOST_COLLECTION_SCORE_HALF_LIFE_MS);
  state = recordHostChoice(state, 'github.com', 1, now - 3 * HOST_COLLECTION_SCORE_HALF_LIFE_MS);
  state = recordHostChoice(state, 'github.com', 1, now - 3 * HOST_COLLECTION_SCORE_HALF_LIFE_MS);
  // Collection 2: count=2 but fresh → score = 2
  state = recordHostChoice(state, 'github.com', 2, now);
  state = recordHostChoice(state, 'github.com', 2, now);
  assert.equal(pickBestCollectionForHost(state, 'github.com', now), 2);
});

test('pickBestCollectionForHost uses the normalized host', () => {
  const state = recordHostChoice(createDefaultHostCollectionMemory(), 'github.com', 7, 100);
  assert.equal(pickBestCollectionForHost(state, 'https://WWW.github.com/x', 200), 7);
});

test('serialize and parse round-trip', () => {
  let state = createDefaultHostCollectionMemory();
  state = recordHostChoice(state, 'github.com', 1, 100);
  state = recordHostChoice(state, 'github.com', 2, 200);
  state = recordHostChoice(state, 'news.ycombinator.com', 3, 300);
  const roundTrip = parseHostCollectionMemory(serializeHostCollectionMemory(state));
  assert.deepEqual(roundTrip, state);
});

test('parseHostCollectionMemory tolerates garbage input', () => {
  assert.deepEqual(parseHostCollectionMemory(''), createDefaultHostCollectionMemory());
  assert.deepEqual(parseHostCollectionMemory('not-json'), createDefaultHostCollectionMemory());
  assert.deepEqual(parseHostCollectionMemory('{"entries":"oops"}'), createDefaultHostCollectionMemory());
});

test('parseHostCollectionMemory drops malformed entries and clamps negatives', () => {
  const raw = JSON.stringify({
    entries: [
      { host: 'github.com', collectionId: 1, count: 3, lastUsedAt: 100 },
      { host: '', collectionId: 2, count: 1, lastUsedAt: 1 },
      { host: 'news.ycombinator.com', collectionId: 'x', count: 1, lastUsedAt: 1 },
      { host: 'example.com', collectionId: 5, count: -4, lastUsedAt: -10 },
    ],
  });
  const parsed = parseHostCollectionMemory(raw);
  assert.deepEqual(parsed.entries, [
    { host: 'github.com', collectionId: 1, count: 3, lastUsedAt: 100 },
    { host: 'example.com', collectionId: 5, count: 0, lastUsedAt: 0 },
  ]);
});
