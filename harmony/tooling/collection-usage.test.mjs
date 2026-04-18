import test from 'node:test';
import assert from 'node:assert/strict';
import {
  COLLECTION_USAGE_SCORE_HALF_LIFE_MS,
  collectionUsageScore,
  createDefaultCollectionUsage,
  findCollectionUsageEntry,
  parseCollectionUsage,
  recordCollectionView,
  serializeCollectionUsage,
} from './collection-usage.mjs';

test('createDefaultCollectionUsage returns empty entries', () => {
  assert.deepEqual(createDefaultCollectionUsage(), { entries: [] });
});

test('recordCollectionView adds a new entry with count=1', () => {
  const now = 1_700_000_000_000;
  const state = recordCollectionView(createDefaultCollectionUsage(), 42, now);
  assert.deepEqual(state.entries, [{ collectionId: 42, viewCount: 1, lastViewedAt: now }]);
});

test('recordCollectionView increments existing entry and moves it to the front', () => {
  const t0 = 1_000;
  const t1 = 2_000;
  const t2 = 3_000;
  let state = createDefaultCollectionUsage();
  state = recordCollectionView(state, 1, t0);
  state = recordCollectionView(state, 2, t1);
  state = recordCollectionView(state, 1, t2);
  assert.equal(state.entries.length, 2);
  assert.deepEqual(state.entries[0], { collectionId: 1, viewCount: 2, lastViewedAt: t2 });
  assert.deepEqual(state.entries[1], { collectionId: 2, viewCount: 1, lastViewedAt: t1 });
});

test('findCollectionUsageEntry returns null when missing', () => {
  const state = recordCollectionView(createDefaultCollectionUsage(), 7, 100);
  assert.equal(findCollectionUsageEntry(state, 999), null);
  assert.deepEqual(findCollectionUsageEntry(state, 7), { collectionId: 7, viewCount: 1, lastViewedAt: 100 });
});

test('collectionUsageScore handles null and future timestamps', () => {
  const now = 5_000;
  assert.equal(collectionUsageScore(null, now), 0);
  assert.equal(collectionUsageScore({ collectionId: 1, viewCount: 3, lastViewedAt: now + 10 }, now), 3);
});

test('collectionUsageScore halves after one half-life', () => {
  const now = 10 * COLLECTION_USAGE_SCORE_HALF_LIFE_MS;
  const entry = { collectionId: 1, viewCount: 4, lastViewedAt: now - COLLECTION_USAGE_SCORE_HALF_LIFE_MS };
  const score = collectionUsageScore(entry, now);
  assert.ok(Math.abs(score - 2) < 1e-9, `expected ~2, got ${score}`);
});

test('collectionUsageScore weights frequency and recency together', () => {
  const now = 10 * COLLECTION_USAGE_SCORE_HALF_LIFE_MS;
  const frequentButOld = { collectionId: 1, viewCount: 5, lastViewedAt: now - 4 * COLLECTION_USAGE_SCORE_HALF_LIFE_MS };
  const rareButFresh = { collectionId: 2, viewCount: 1, lastViewedAt: now };
  assert.ok(collectionUsageScore(rareButFresh, now) > collectionUsageScore(frequentButOld, now));

  const veryFrequentOld = { collectionId: 3, viewCount: 50, lastViewedAt: now - COLLECTION_USAGE_SCORE_HALF_LIFE_MS };
  assert.ok(collectionUsageScore(veryFrequentOld, now) > collectionUsageScore(rareButFresh, now));
});

test('serializeCollectionUsage and parseCollectionUsage round-trip', () => {
  const state = recordCollectionView(
    recordCollectionView(createDefaultCollectionUsage(), 1, 100),
    2,
    200,
  );
  const roundTrip = parseCollectionUsage(serializeCollectionUsage(state));
  assert.deepEqual(roundTrip, state);
});

test('parseCollectionUsage tolerates garbage input', () => {
  assert.deepEqual(parseCollectionUsage(''), createDefaultCollectionUsage());
  assert.deepEqual(parseCollectionUsage('not-json'), createDefaultCollectionUsage());
  assert.deepEqual(parseCollectionUsage('{"entries":"oops"}'), createDefaultCollectionUsage());
});

test('parseCollectionUsage drops malformed entries and clamps negatives', () => {
  const raw = JSON.stringify({
    entries: [
      { collectionId: 1, viewCount: 3, lastViewedAt: 100 },
      { collectionId: 'x', viewCount: 1, lastViewedAt: 1 },
      { collectionId: 2, viewCount: -4, lastViewedAt: -10 },
    ],
  });
  const parsed = parseCollectionUsage(raw);
  assert.deepEqual(parsed.entries, [
    { collectionId: 1, viewCount: 3, lastViewedAt: 100 },
    { collectionId: 2, viewCount: 0, lastViewedAt: 0 },
  ]);
});
