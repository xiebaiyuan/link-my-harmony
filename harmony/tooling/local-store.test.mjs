import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createEmptyStore,
  nextLinkId,
  nextCollectionId,
  nextTagId,
  addLink,
  updateLink,
  deleteLink,
  setLinkPinned,
  getLinkById,
  listLinks,
  addCollection,
  updateCollection,
  deleteCollection,
  getCollectionById,
  listCollections,
  ensureTag,
  deleteTag,
  listTags,
  serializeStore,
  parseStore,
} from './local-store.mjs';

const FIXED_NOW = Date.parse('2026-04-19T10:00:00.000Z');

function seedStore() {
  let store = createEmptyStore();
  ({ store } = addCollection(store, { name: 'Tech', color: '#1F6FEB' }));
  ({ store } = addCollection(store, { name: 'Life', color: '#10B981' }));
  ({ store } = addLink(store, {
    name: 'HarmonyOS docs',
    url: 'https://developer.huawei.com/harmony',
    collectionId: -1, // Tech
    tags: [{ name: 'harmony' }, { name: 'docs' }],
  }, FIXED_NOW));
  ({ store } = addLink(store, {
    name: 'Linkwarden',
    url: 'https://linkwarden.app',
    collectionId: -1,
    tags: [{ name: 'tool' }],
    pinned: true,
  }, FIXED_NOW + 1000));
  ({ store } = addLink(store, {
    name: 'Recipe',
    url: 'https://cooking.example.com/pasta',
    collectionId: -2,
    tags: [{ name: 'food' }],
  }, FIXED_NOW + 2000));
  return store;
}

// --- factory & id allocation ---------------------------------------------

test('createEmptyStore returns empty arrays', () => {
  assert.deepEqual(createEmptyStore(), { links: [], collections: [], tags: [] });
});

test('next*Id returns -1 for empty store and decrements as rows are added', () => {
  let store = createEmptyStore();
  assert.equal(nextLinkId(store), -1);
  assert.equal(nextCollectionId(store), -1);
  assert.equal(nextTagId(store), -1);
  ({ store } = addLink(store, { url: 'https://a.example' }, FIXED_NOW));
  assert.equal(nextLinkId(store), -2);
  ({ store } = addLink(store, { url: 'https://b.example' }, FIXED_NOW));
  assert.equal(nextLinkId(store), -3);
});

test('next*Id ignores synced (positive) ids when allocating', () => {
  const store = {
    links: [
      { id: 42, url: 'https://synced.example', name: '', description: '',
        createdAt: '', collectionId: 0, pinned: false, tagIds: [] },
    ],
    collections: [],
    tags: [],
  };
  assert.equal(nextLinkId(store), -1);
});

test('next*Id keeps decrementing even if synced ids claimed positive range', () => {
  let store = createEmptyStore();
  ({ store } = addLink(store, { url: 'https://a.example' }, FIXED_NOW));
  store = {
    ...store,
    links: store.links.concat([{
      id: 100, url: 'https://server.example', name: '', description: '',
      createdAt: '', collectionId: 0, pinned: false, tagIds: [],
    }]),
  };
  assert.equal(nextLinkId(store), -2);
});

// --- links CRUD ----------------------------------------------------------

test('addLink assigns next local id and a createdAt when absent', () => {
  const { store, link } = addLink(createEmptyStore(), {
    url: 'https://example.com',
  }, FIXED_NOW);
  assert.equal(link.id, -1);
  assert.equal(link.url, 'https://example.com');
  assert.equal(link.createdAt, '2026-04-19T10:00:00.000Z');
  assert.equal(store.links.length, 1);
});

test('addLink preserves supplied createdAt', () => {
  const { link } = addLink(createEmptyStore(), {
    url: 'https://example.com',
    createdAt: '2020-01-01T00:00:00.000Z',
  }, FIXED_NOW);
  assert.equal(link.createdAt, '2020-01-01T00:00:00.000Z');
});

test('addLink requires a non-empty url', () => {
  assert.throws(() => addLink(createEmptyStore(), { url: '' }, FIXED_NOW), /LINK_URL_REQUIRED/);
  assert.throws(() => addLink(createEmptyStore(), { url: '   ' }, FIXED_NOW), /LINK_URL_REQUIRED/);
  assert.throws(() => addLink(createEmptyStore(), {}, FIXED_NOW), /LINK_URL_REQUIRED/);
});

test('addLink trims url before persisting', () => {
  const { link } = addLink(createEmptyStore(), {
    url: '  https://trim.example  ',
  }, FIXED_NOW);
  assert.equal(link.url, 'https://trim.example');
});

test('addLink dedupes tags by name and reuses existing tag ids', () => {
  let store = createEmptyStore();
  let first;
  ({ store, link: first } = addLink(store, {
    url: 'https://a.example',
    tags: [{ name: 'foo' }, { name: 'bar' }, { name: 'foo' }],
  }, FIXED_NOW));
  assert.equal(first.tags.length, 2);
  const [foo1, bar1] = first.tags;

  let second;
  ({ store, link: second } = addLink(store, {
    url: 'https://b.example',
    tags: [{ name: 'foo' }, { name: 'baz' }],
  }, FIXED_NOW));
  assert.equal(second.tags.find((t) => t.name === 'foo').id, foo1.id);
  assert.notEqual(second.tags.find((t) => t.name === 'baz').id, bar1.id);
  assert.equal(store.tags.length, 3); // foo, bar, baz
});

test('addLink accepts plain string tag entries alongside objects', () => {
  const { link } = addLink(createEmptyStore(), {
    url: 'https://a.example',
    tags: ['harmony', { name: 'docs' }, '   ', ''],
  }, FIXED_NOW);
  assert.deepEqual(link.tags.map((t) => t.name), ['harmony', 'docs']);
});

test('addLink resolves collection fields from the collections table', () => {
  let store = createEmptyStore();
  let col;
  ({ store, collection: col } = addCollection(store, {
    name: 'Tech',
    color: '#1F6FEB',
    ownerId: 7,
  }));
  const { link } = addLink(store, {
    url: 'https://a.example',
    collectionId: col.id,
  }, FIXED_NOW);
  assert.equal(link.collectionId, col.id);
  assert.equal(link.collectionName, 'Tech');
  assert.equal(link.collectionColor, '#1F6FEB');
  assert.equal(link.collectionOwnerId, 7);
});

test('addLink with unknown collectionId zeroes the embed', () => {
  const { link } = addLink(createEmptyStore(), {
    url: 'https://a.example',
    collectionId: 99,
  }, FIXED_NOW);
  assert.equal(link.collectionId, 0);
  assert.equal(link.collectionName, '');
});

test('updateLink preserves untouched fields and updates only patched ones', () => {
  let store = seedStore();
  const target = store.links.find((l) => l.name === 'Linkwarden');
  const before = getLinkById(store, target.id);
  ({ store } = updateLink(store, target.id, { description: 'bookmark manager' }));
  const after = getLinkById(store, target.id);
  assert.equal(after.description, 'bookmark manager');
  assert.equal(after.name, before.name);
  assert.equal(after.url, before.url);
  assert.equal(after.pinned, before.pinned);
  assert.deepEqual(after.tags.map((t) => t.name), before.tags.map((t) => t.name));
});

test('updateLink replaces tags when tags are in the patch', () => {
  let store = seedStore();
  const target = store.links.find((l) => l.name === 'Linkwarden');
  ({ store } = updateLink(store, target.id, { tags: [{ name: 'tool' }, { name: 'self-hosted' }] }));
  const after = getLinkById(store, target.id);
  assert.deepEqual(after.tags.map((t) => t.name).sort(), ['self-hosted', 'tool']);
});

test('updateLink moves a link between collections', () => {
  let store = seedStore();
  const target = store.links.find((l) => l.name === 'Linkwarden');
  const life = store.collections.find((c) => c.name === 'Life');
  ({ store } = updateLink(store, target.id, { collectionId: life.id }));
  const after = getLinkById(store, target.id);
  assert.equal(after.collectionId, life.id);
  assert.equal(after.collectionName, 'Life');
});

test('updateLink with unknown collectionId zeroes the link out of any collection', () => {
  let store = seedStore();
  const target = store.links[0];
  ({ store } = updateLink(store, target.id, { collectionId: 9999 }));
  const after = getLinkById(store, target.id);
  assert.equal(after.collectionId, 0);
  assert.equal(after.collectionName, '');
});

test('updateLink throws when the url patch is empty', () => {
  const store = seedStore();
  const target = store.links[0];
  assert.throws(() => updateLink(store, target.id, { url: '   ' }), /LINK_URL_REQUIRED/);
});

test('updateLink throws when the id does not exist', () => {
  assert.throws(() => updateLink(createEmptyStore(), -999, { name: 'x' }), /LINK_NOT_FOUND/);
});

test('deleteLink removes the row and nothing else', () => {
  let store = seedStore();
  const target = store.links.find((l) => l.name === 'Recipe');
  const before = store.links.length;
  store = deleteLink(store, target.id);
  assert.equal(store.links.length, before - 1);
  assert.equal(getLinkById(store, target.id), null);
});

test('deleteLink throws when id not found', () => {
  assert.throws(() => deleteLink(createEmptyStore(), -1), /LINK_NOT_FOUND/);
});

test('setLinkPinned toggles the pinned flag', () => {
  let store = seedStore();
  const target = store.links.find((l) => l.name === 'HarmonyOS docs');
  ({ store } = setLinkPinned(store, target.id, true));
  assert.equal(getLinkById(store, target.id).pinned, true);
  ({ store } = setLinkPinned(store, target.id, false));
  assert.equal(getLinkById(store, target.id).pinned, false);
});

// --- list & filter --------------------------------------------------------

test('listLinks sorts by createdAt DESC', () => {
  const store = seedStore();
  const { links } = listLinks(store, {});
  assert.deepEqual(links.map((l) => l.name), ['Recipe', 'Linkwarden', 'HarmonyOS docs']);
});

test('listLinks filters by collectionId', () => {
  const store = seedStore();
  const tech = store.collections.find((c) => c.name === 'Tech');
  const { links } = listLinks(store, { collectionId: tech.id });
  assert.deepEqual(links.map((l) => l.name).sort(), ['HarmonyOS docs', 'Linkwarden']);
});

test('listLinks filters by pinnedOnly', () => {
  const store = seedStore();
  const { links } = listLinks(store, { pinnedOnly: true });
  assert.deepEqual(links.map((l) => l.name), ['Linkwarden']);
});

test('listLinks search matches name / url / description / tag name (case-insensitive)', () => {
  let store = seedStore();
  ({ store } = updateLink(store, store.links.find((l) => l.name === 'HarmonyOS docs').id, {
    description: 'official API REFERENCE',
  }));

  const byName = listLinks(store, { searchQueryString: 'recipe' }).links;
  assert.deepEqual(byName.map((l) => l.name), ['Recipe']);

  const byUrl = listLinks(store, { searchQueryString: 'linkwarden.app' }).links;
  assert.deepEqual(byUrl.map((l) => l.name), ['Linkwarden']);

  const byDescription = listLinks(store, { searchQueryString: 'api reference' }).links;
  assert.deepEqual(byDescription.map((l) => l.name), ['HarmonyOS docs']);

  const byTag = listLinks(store, { searchQueryString: 'food' }).links;
  assert.deepEqual(byTag.map((l) => l.name), ['Recipe']);
});

test('listLinks paginates via cursor and reports nextCursor', () => {
  let store = createEmptyStore();
  for (let i = 0; i < 5; i++) {
    ({ store } = addLink(store, {
      name: `Link ${i}`,
      url: `https://example.com/${i}`,
    }, FIXED_NOW + i * 1000));
  }
  const page1 = listLinks(store, { limit: 2 });
  assert.equal(page1.links.length, 2);
  assert.notEqual(page1.nextCursor, -1);

  const page2 = listLinks(store, { limit: 2, cursor: page1.nextCursor });
  assert.equal(page2.links.length, 2);
  assert.notEqual(page2.nextCursor, -1);

  const page3 = listLinks(store, { limit: 2, cursor: page2.nextCursor });
  assert.equal(page3.links.length, 1);
  assert.equal(page3.nextCursor, -1);

  const seen = [...page1.links, ...page2.links, ...page3.links].map((l) => l.name);
  assert.deepEqual(seen, ['Link 4', 'Link 3', 'Link 2', 'Link 1', 'Link 0']);
});

test('listLinks returns empty page for an unknown cursor', () => {
  const store = seedStore();
  const { links, nextCursor } = listLinks(store, { cursor: -9999 });
  assert.deepEqual(links, []);
  assert.equal(nextCursor, -1);
});

test('listLinks filters by tagId', () => {
  const store = seedStore();
  const toolTag = store.tags.find((t) => t.name === 'tool');
  const { links } = listLinks(store, { tagId: toolTag.id });
  assert.deepEqual(links.map((l) => l.name), ['Linkwarden']);
});

// --- collections ----------------------------------------------------------

test('addCollection requires a non-empty name', () => {
  assert.throws(() => addCollection(createEmptyStore(), { name: '   ' }), /COLLECTION_NAME_REQUIRED/);
});

test('addCollection allows duplicate names (matching Linkwarden semantics)', () => {
  let store = createEmptyStore();
  let a, b;
  ({ store, collection: a } = addCollection(store, { name: 'Duplicate' }));
  ({ store, collection: b } = addCollection(store, { name: 'Duplicate' }));
  assert.notEqual(a.id, b.id);
});

test('updateCollection renames and retains id, rename reflects in listCollections', () => {
  let store = seedStore();
  const tech = store.collections.find((c) => c.name === 'Tech');
  ({ store } = updateCollection(store, tech.id, { name: 'Developer', color: '#000' }));
  const cols = listCollections(store);
  const renamed = cols.find((c) => c.id === tech.id);
  assert.equal(renamed.name, 'Developer');
  assert.equal(renamed.color, '#000');
});

test('updateCollection rejects cleared name', () => {
  const store = seedStore();
  const tech = store.collections.find((c) => c.name === 'Tech');
  assert.throws(() => updateCollection(store, tech.id, { name: '' }), /COLLECTION_NAME_REQUIRED/);
});

test('updateCollection throws when id unknown', () => {
  assert.throws(() => updateCollection(createEmptyStore(), -1, { name: 'x' }), /COLLECTION_NOT_FOUND/);
});

test('deleteCollection blocks when links exist', () => {
  const store = seedStore();
  const tech = store.collections.find((c) => c.name === 'Tech');
  assert.throws(() => deleteCollection(store, tech.id), /COLLECTION_NOT_EMPTY/);
});

test('deleteCollection with cascade=true removes contained links', () => {
  let store = seedStore();
  const tech = store.collections.find((c) => c.name === 'Tech');
  store = deleteCollection(store, tech.id, { cascade: true });
  assert.equal(store.collections.some((c) => c.id === tech.id), false);
  assert.equal(store.links.some((l) => l.collectionId === tech.id), false);
  assert.equal(store.links.length, 1); // only the Recipe link remains
});

test('deleteCollection succeeds for an empty collection', () => {
  let store = createEmptyStore();
  let col;
  ({ store, collection: col } = addCollection(store, { name: 'Empty' }));
  store = deleteCollection(store, col.id);
  assert.equal(store.collections.length, 0);
});

test('listCollections exposes computed linkCount and parentName', () => {
  let store = createEmptyStore();
  let parent;
  ({ store, collection: parent } = addCollection(store, { name: 'Parent' }));
  ({ store } = addCollection(store, { name: 'Child', parentId: parent.id }));
  ({ store } = addLink(store, { url: 'https://a.example', collectionId: parent.id }, FIXED_NOW));
  const cols = listCollections(store);
  const parentRow = cols.find((c) => c.id === parent.id);
  const childRow = cols.find((c) => c.name === 'Child');
  assert.equal(parentRow.linkCount, 1);
  assert.equal(childRow.parentName, 'Parent');
});

test('getCollectionById returns null for unknown id', () => {
  assert.equal(getCollectionById(createEmptyStore(), -1), null);
});

// --- tags -----------------------------------------------------------------

test('ensureTag dedupes by name and rejects empty names', () => {
  let store = createEmptyStore();
  let a, b;
  ({ store, tag: a } = ensureTag(store, 'work'));
  ({ store, tag: b } = ensureTag(store, 'work'));
  assert.equal(a.id, b.id);
  assert.throws(() => ensureTag(store, '   '), /TAG_NAME_REQUIRED/);
});

test('deleteTag removes tag and cleans all link references', () => {
  let store = seedStore();
  const foodTag = store.tags.find((t) => t.name === 'food');
  store = deleteTag(store, foodTag.id);
  assert.equal(store.tags.some((t) => t.id === foodTag.id), false);
  for (const l of store.links) {
    assert.equal(l.tagIds.includes(foodTag.id), false);
  }
});

test('deleteTag throws when id unknown', () => {
  assert.throws(() => deleteTag(createEmptyStore(), -1), /TAG_NOT_FOUND/);
});

test('listTags reports linkCount per tag', () => {
  const store = seedStore();
  const list = listTags(store);
  const harmony = list.find((t) => t.name === 'harmony');
  const docs = list.find((t) => t.name === 'docs');
  const tool = list.find((t) => t.name === 'tool');
  assert.equal(harmony.linkCount, 1);
  assert.equal(docs.linkCount, 1);
  assert.equal(tool.linkCount, 1);
});

// --- serialization --------------------------------------------------------

test('serializeStore + parseStore survive a round-trip', () => {
  const store = seedStore();
  const raw = serializeStore(store);
  const restored = parseStore(raw);
  assert.deepEqual(restored, store);
});

test('parseStore returns an empty store for malformed JSON', () => {
  assert.deepEqual(parseStore('not-json'), createEmptyStore());
  assert.deepEqual(parseStore(''), createEmptyStore());
  assert.deepEqual(parseStore(null), createEmptyStore());
});

test('parseStore drops rows that are missing required identifiers', () => {
  const payload = JSON.stringify({
    links: [
      { id: 0, url: 'https://bad.example' },
      { id: -1, url: '' },
      { id: -2, url: 'https://good.example' },
    ],
    collections: [
      { id: 0, name: 'Invalid' },
      { id: -1, name: 'Keep' },
    ],
    tags: [
      { id: 0, name: 'drop' },
      { id: -1, name: '' },
      { id: -2, name: 'keep' },
    ],
  });
  const restored = parseStore(payload);
  assert.equal(restored.links.length, 1);
  assert.equal(restored.links[0].id, -2);
  assert.equal(restored.collections.length, 1);
  assert.equal(restored.collections[0].id, -1);
  assert.equal(restored.tags.length, 1);
  assert.equal(restored.tags[0].id, -2);
});

test('hydrateLink (via getLinkById) reflects subsequent collection renames', () => {
  let store = seedStore();
  const target = store.links.find((l) => l.name === 'HarmonyOS docs');
  const tech = store.collections.find((c) => c.name === 'Tech');
  ({ store } = updateCollection(store, tech.id, { name: 'Developer' }));
  const after = getLinkById(store, target.id);
  assert.equal(after.collectionName, 'Developer');
});
