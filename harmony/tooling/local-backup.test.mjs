import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createEmptyStore,
  addCollection,
  addLink,
  ensureTag,
  listLinks,
  listCollections,
  listTags,
} from './local-store.mjs';
import {
  BACKUP_FORMAT,
  BACKUP_VERSION,
  exportStore,
  importBackup,
  parseBackup,
} from './local-backup.mjs';

const FIXED_NOW = Date.parse('2026-04-19T10:00:00.000Z');
const FIXED_EXPORTED_AT = '2026-04-19T10:30:00.000Z';

function makePopulatedStore() {
  let store = createEmptyStore();
  let tech, life;
  ({ store, collection: tech } = addCollection(store, { name: 'Tech', color: '#1F6FEB', ownerId: 1 }));
  ({ store, collection: life } = addCollection(store, { name: 'Life', color: '#10B981' }));
  ({ store } = addLink(store, {
    name: 'HarmonyOS docs',
    url: 'https://developer.huawei.com/harmony',
    description: '',
    collectionId: tech.id,
    tags: [{ name: 'harmony' }, { name: 'docs' }],
    pinned: false,
  }, FIXED_NOW));
  ({ store } = addLink(store, {
    name: 'Linkwarden',
    url: 'https://linkwarden.app',
    collectionId: tech.id,
    tags: [{ name: 'tool' }],
    pinned: true,
  }, FIXED_NOW + 1000));
  ({ store } = addLink(store, {
    name: 'Pasta recipe',
    url: 'https://cooking.example.com/pasta',
    collectionId: life.id,
    tags: [{ name: 'food' }],
  }, FIXED_NOW + 2000));
  return store;
}

// --- export ---------------------------------------------------------------

test('exportStore emits a folio-backup envelope with sorted rows', () => {
  const raw = exportStore(makePopulatedStore(), { exportedAt: FIXED_EXPORTED_AT });
  const parsed = JSON.parse(raw);
  assert.equal(parsed.format, BACKUP_FORMAT);
  assert.equal(parsed.version, BACKUP_VERSION);
  assert.equal(parsed.exportedAt, FIXED_EXPORTED_AT);
  // rows sorted by id ascending (most negative first)
  assert.ok(parsed.links.length > 0);
  for (let i = 1; i < parsed.links.length; i++) {
    assert.ok(parsed.links[i - 1].id <= parsed.links[i].id);
  }
  for (let i = 1; i < parsed.collections.length; i++) {
    assert.ok(parsed.collections[i - 1].id <= parsed.collections[i].id);
  }
});

test('exportStore is deterministic for the same input and exportedAt', () => {
  const a = exportStore(makePopulatedStore(), { exportedAt: FIXED_EXPORTED_AT });
  const b = exportStore(makePopulatedStore(), { exportedAt: FIXED_EXPORTED_AT });
  assert.equal(a, b);
});

test('exportStore handles an empty store', () => {
  const raw = exportStore(createEmptyStore(), { exportedAt: FIXED_EXPORTED_AT });
  const parsed = JSON.parse(raw);
  assert.deepEqual(parsed.links, []);
  assert.deepEqual(parsed.collections, []);
  assert.deepEqual(parsed.tags, []);
});

// --- parse guardrails -----------------------------------------------------

test('parseBackup rejects empty input', () => {
  assert.throws(() => parseBackup(''), /BACKUP_EMPTY/);
  assert.throws(() => parseBackup(null), /BACKUP_EMPTY/);
});

test('parseBackup rejects malformed JSON', () => {
  assert.throws(() => parseBackup('not-json'), /BACKUP_MALFORMED_JSON/);
});

test('parseBackup rejects unrecognized format', () => {
  assert.throws(
    () => parseBackup(JSON.stringify({ format: 'netscape', version: 1, links: [] })),
    /BACKUP_UNRECOGNIZED_FORMAT/,
  );
});

test('parseBackup rejects unsupported versions with the version number in the error', () => {
  assert.throws(
    () => parseBackup(JSON.stringify({ format: BACKUP_FORMAT, version: 2 })),
    /BACKUP_UNSUPPORTED_VERSION:2/,
  );
});

test('parseBackup silently drops invalid rows while keeping valid ones', () => {
  const raw = JSON.stringify({
    format: BACKUP_FORMAT,
    version: BACKUP_VERSION,
    exportedAt: FIXED_EXPORTED_AT,
    collections: [
      { id: -1, name: 'Good' },
      { id: 0, name: 'MissingId' },
    ],
    tags: [
      { id: -1, name: 'ok' },
      { id: -2, name: '' },
    ],
    links: [
      { id: -1, url: 'https://ok.example', collectionId: -1, tagIds: [-1] },
      { id: -2, url: '' },
    ],
  });
  const { store } = parseBackup(raw);
  assert.equal(store.collections.length, 1);
  assert.equal(store.tags.length, 1);
  assert.equal(store.links.length, 1);
});

// --- replace strategy -----------------------------------------------------

test('importBackup with replace strategy fully overwrites the current store', () => {
  const current = makePopulatedStore();
  const fresh = createEmptyStore();
  const raw = exportStore(current, { exportedAt: FIXED_EXPORTED_AT });

  const { store, summary } = importBackup(fresh, raw, { strategy: 'replace' });

  // Functional equivalence — deterministic export may reorder rows by id,
  // so compare sorted rather than expecting insertion-order identity.
  const byId = (arr) => arr.slice().sort((a, b) => a.id - b.id);
  assert.deepEqual(byId(store.links), byId(current.links));
  assert.deepEqual(byId(store.collections), byId(current.collections));
  assert.deepEqual(byId(store.tags), byId(current.tags));

  assert.equal(summary.linksImported, current.links.length);
  assert.equal(summary.collectionsImported, current.collections.length);
  assert.equal(summary.tagsImported, current.tags.length);
  assert.equal(summary.linksSkipped, 0);
});

test('importBackup replace also replaces when a different store is current', () => {
  const backupSource = makePopulatedStore();
  const raw = exportStore(backupSource, { exportedAt: FIXED_EXPORTED_AT });

  let other = createEmptyStore();
  ({ store: other } = addCollection(other, { name: 'Unrelated' }));
  ({ store: other } = addLink(other, { url: 'https://other.example' }, FIXED_NOW));

  const { store } = importBackup(other, raw, { strategy: 'replace' });
  assert.equal(store.collections.some((c) => c.name === 'Unrelated'), false);
  assert.equal(store.links.some((l) => l.url === 'https://other.example'), false);
});

// --- merge strategy -------------------------------------------------------

test('importBackup merge into empty is equivalent to loading the snapshot', () => {
  const source = makePopulatedStore();
  const raw = exportStore(source, { exportedAt: FIXED_EXPORTED_AT });
  const { store, summary } = importBackup(createEmptyStore(), raw, { strategy: 'merge' });

  assert.equal(listCollections(store).length, listCollections(source).length);
  assert.equal(listLinks(store, {}).links.length, listLinks(source, {}).links.length);
  assert.equal(listTags(store).length, listTags(source).length);
  assert.equal(summary.linksSkipped, 0);
  assert.equal(summary.collectionsReused, 0);
});

test('importBackup merge reuses existing collections/tags by name', () => {
  // Device A exports; device B already has a collection named "Tech" and a tag named "harmony".
  const source = makePopulatedStore();
  const raw = exportStore(source, { exportedAt: FIXED_EXPORTED_AT });

  let b = createEmptyStore();
  ({ store: b } = addCollection(b, { name: 'Tech', color: '#fff', ownerId: 99 }));
  ({ store: b } = ensureTag(b, 'harmony'));

  const before = listCollections(b).find((c) => c.name === 'Tech');

  const { store, summary } = importBackup(b, raw, { strategy: 'merge' });

  // collection "Tech" should still be the same row (same id), not duplicated
  const after = listCollections(store).filter((c) => c.name === 'Tech');
  assert.equal(after.length, 1);
  assert.equal(after[0].id, before.id);
  assert.ok(summary.collectionsReused >= 1);
  assert.ok(summary.tagsReused >= 1);
});

test('importBackup merge dedupes links by (collection, url)', () => {
  const source = makePopulatedStore();
  const raw = exportStore(source, { exportedAt: FIXED_EXPORTED_AT });

  // Target already has Tech with Linkwarden link at the same url.
  let target = createEmptyStore();
  let tech;
  ({ store: target, collection: tech } = addCollection(target, { name: 'Tech' }));
  ({ store: target } = addLink(target, {
    url: 'https://linkwarden.app',
    collectionId: tech.id,
    name: 'Linkwarden already',
  }, FIXED_NOW));

  const { store, summary } = importBackup(target, raw, { strategy: 'merge' });

  const techLinks = listLinks(store, { collectionId: tech.id }).links;
  // one pre-existing + HarmonyOS docs imported (= 2 total); Linkwarden url is deduped.
  assert.equal(techLinks.filter((l) => l.url === 'https://linkwarden.app').length, 1);
  assert.equal(summary.linksSkipped, 1);
});

test('importBackup merge does NOT dedupe across different collections', () => {
  const source = makePopulatedStore();
  const raw = exportStore(source, { exportedAt: FIXED_EXPORTED_AT });

  // Target already has the linkwarden url under a DIFFERENT collection ("Misc").
  let target = createEmptyStore();
  let misc;
  ({ store: target, collection: misc } = addCollection(target, { name: 'Misc' }));
  ({ store: target } = addLink(target, {
    url: 'https://linkwarden.app',
    collectionId: misc.id,
  }, FIXED_NOW));

  const { store, summary } = importBackup(target, raw, { strategy: 'merge' });

  const all = listLinks(store, {}).links.filter((l) => l.url === 'https://linkwarden.app');
  assert.equal(all.length, 2);
  assert.equal(summary.linksSkipped, 0);
});

test('importBackup merge remaps ids so negative ids from two devices never collide', () => {
  // Source store uses negative ids -1..-N.
  const source = makePopulatedStore();
  const raw = exportStore(source, { exportedAt: FIXED_EXPORTED_AT });

  // Target coincidentally uses the SAME negative id space for different data.
  let target = createEmptyStore();
  ({ store: target } = addCollection(target, { name: 'Target only 1' })); // id -1
  ({ store: target } = addCollection(target, { name: 'Target only 2' })); // id -2
  ({ store: target } = addLink(target, {
    url: 'https://target-unique.example',
    collectionId: -1,
  }, FIXED_NOW));
  ({ store: target } = addLink(target, {
    url: 'https://target-unique-2.example',
    collectionId: -2,
  }, FIXED_NOW + 500));

  const { store } = importBackup(target, raw, { strategy: 'merge' });

  // All pre-existing target links still reference their correct collections.
  const t1 = store.links.find((l) => l.url === 'https://target-unique.example');
  const t2 = store.links.find((l) => l.url === 'https://target-unique-2.example');
  const c1 = store.collections.find((c) => c.name === 'Target only 1');
  const c2 = store.collections.find((c) => c.name === 'Target only 2');
  assert.equal(t1.collectionId, c1.id);
  assert.equal(t2.collectionId, c2.id);

  // Imported Tech + Life still carry the Harmony/Linkwarden + Pasta links correctly.
  const tech = store.collections.find((c) => c.name === 'Tech');
  const life = store.collections.find((c) => c.name === 'Life');
  const techUrls = store.links
    .filter((l) => l.collectionId === tech.id)
    .map((l) => l.url)
    .sort();
  const lifeUrls = store.links
    .filter((l) => l.collectionId === life.id)
    .map((l) => l.url);
  assert.deepEqual(techUrls, [
    'https://developer.huawei.com/harmony',
    'https://linkwarden.app',
  ]);
  assert.deepEqual(lifeUrls, ['https://cooking.example.com/pasta']);
});

test('importBackup merge preserves parent/child collection hierarchy when both imported', () => {
  let source = createEmptyStore();
  let parent;
  ({ store: source, collection: parent } = addCollection(source, { name: 'Parent' }));
  ({ store: source } = addCollection(source, { name: 'Child', parentId: parent.id }));
  const raw = exportStore(source, { exportedAt: FIXED_EXPORTED_AT });

  const { store } = importBackup(createEmptyStore(), raw, { strategy: 'merge' });
  const imported = listCollections(store);
  const importedParent = imported.find((c) => c.name === 'Parent');
  const importedChild = imported.find((c) => c.name === 'Child');
  assert.equal(importedChild.parentId, importedParent.id);
  assert.equal(importedChild.parentName, 'Parent');
});

test('importBackup merge does not overwrite parentId of a reused collection', () => {
  // Target has "Tech" with parentId 0 already — incoming backup thinks "Tech" has a parent.
  // Reuse should leave the existing parent alone (user's own structure wins).
  const source = makePopulatedStore();
  const raw = exportStore(source, { exportedAt: FIXED_EXPORTED_AT });

  let target = createEmptyStore();
  let ownTech;
  ({ store: target, collection: ownTech } = addCollection(target, { name: 'Tech', parentId: 0 }));

  const { store } = importBackup(target, raw, { strategy: 'merge' });
  const techAfter = listCollections(store).find((c) => c.id === ownTech.id);
  assert.equal(techAfter.parentId, 0);
});

test('importBackup merge preserves original pinned flag and createdAt', () => {
  const source = makePopulatedStore();
  const raw = exportStore(source, { exportedAt: FIXED_EXPORTED_AT });
  const { store } = importBackup(createEmptyStore(), raw, { strategy: 'merge' });
  const imported = store.links.find((l) => l.url === 'https://linkwarden.app');
  assert.equal(imported.pinned, true);
  assert.equal(imported.createdAt, new Date(FIXED_NOW + 1000).toISOString());
});

test('importBackup merge imports orphan tags (tags present in backup but not referenced by any link)', () => {
  let source = createEmptyStore();
  ({ store: source } = ensureTag(source, 'orphan-tag'));
  const raw = exportStore(source, { exportedAt: FIXED_EXPORTED_AT });
  const { store, summary } = importBackup(createEmptyStore(), raw, { strategy: 'merge' });
  assert.equal(store.tags.some((t) => t.name === 'orphan-tag'), true);
  assert.equal(summary.tagsImported, 1);
});

test('importBackup rejects unknown strategies', () => {
  const raw = exportStore(createEmptyStore(), { exportedAt: FIXED_EXPORTED_AT });
  assert.throws(
    () => importBackup(createEmptyStore(), raw, { strategy: 'mirror' }),
    /BACKUP_UNKNOWN_STRATEGY/,
  );
});

test('importBackup merge is the default strategy when options are omitted', () => {
  const source = makePopulatedStore();
  const raw = exportStore(source, { exportedAt: FIXED_EXPORTED_AT });
  const { store } = importBackup(createEmptyStore(), raw);
  assert.equal(listCollections(store).length, listCollections(source).length);
});
