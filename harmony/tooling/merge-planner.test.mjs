import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createEmptyStore,
  addCollection,
  addLink,
  ensureTag,
} from './local-store.mjs';
import { planMerge, applyMergeResult } from './merge-planner.mjs';

const FIXED_NOW = Date.parse('2026-04-19T10:00:00.000Z');

// --- helpers --------------------------------------------------------------

function storeWith(fns) {
  let store = createEmptyStore();
  for (const fn of fns) {
    store = fn(store);
  }
  return store;
}

function mkAddCollection(draft) {
  return (store) => {
    const res = addCollection(store, draft);
    return res.store;
  };
}

function mkAddLink(draft, now) {
  return (store) => {
    const res = addLink(store, draft, now ?? FIXED_NOW);
    return res.store;
  };
}

// --- plan -----------------------------------------------------------------

test('planMerge on empty local store returns an empty plan', () => {
  const plan = planMerge(createEmptyStore(), { collections: [], links: [] });
  assert.deepEqual(plan.collectionActions, []);
  assert.deepEqual(plan.linkActions, []);
  assert.deepEqual(plan.summary, {
    collectionsToCreate: 0,
    collectionsReused: 0,
    collectionsAlreadySynced: 0,
    linksToCreate: 0,
    linksToSkip: 0,
    linksAlreadySynced: 0,
  });
});

test('planMerge emits create actions for every pure-local item', () => {
  const store = storeWith([
    mkAddCollection({ name: 'Tech' }),
    mkAddLink({ url: 'https://a.example', collectionId: -1, name: 'A' }),
    mkAddLink({ url: 'https://b.example', collectionId: -1, name: 'B', tags: [{ name: 'work' }] }),
  ]);
  const plan = planMerge(store, { collections: [], links: [] });
  assert.equal(plan.collectionActions.length, 1);
  assert.equal(plan.collectionActions[0].kind, 'create');
  assert.equal(plan.collectionActions[0].name, 'Tech');

  assert.equal(plan.linkActions.length, 2);
  for (const la of plan.linkActions) {
    assert.equal(la.kind, 'create');
    assert.equal(la.collectionTempId, -1);
  }
  assert.equal(plan.summary.collectionsToCreate, 1);
  assert.equal(plan.summary.linksToCreate, 2);
});

test('planMerge reuses a server collection by name and skips duplicate-url links', () => {
  const store = storeWith([
    mkAddCollection({ name: 'Tech' }),
    mkAddLink({ url: 'https://existing.example', collectionId: -1 }),
    mkAddLink({ url: 'https://new.example', collectionId: -1 }),
  ]);
  const server = {
    collections: [{ id: 10, name: 'Tech', ownerId: 1 }],
    links: [{ collectionId: 10, url: 'https://existing.example' }],
  };
  const plan = planMerge(store, server);

  assert.equal(plan.collectionActions.length, 1);
  const colAct = plan.collectionActions[0];
  assert.equal(colAct.kind, 'reuse');
  assert.equal(colAct.tempId, -1);
  assert.equal(colAct.resolvedServerId, 10);

  const skipAct = plan.linkActions.find((a) => a.kind === 'skip');
  const createAct = plan.linkActions.find((a) => a.kind === 'create');
  assert.ok(skipAct);
  assert.ok(createAct);
  assert.equal(skipAct.url, 'https://existing.example');
  assert.equal(skipAct.resolvedCollectionServerId, 10);
  assert.equal(createAct.url, 'https://new.example');
  assert.equal(plan.summary.collectionsReused, 1);
  assert.equal(plan.summary.linksToSkip, 1);
  assert.equal(plan.summary.linksToCreate, 1);
});

test('planMerge does not skip when the target collection is going to be newly created', () => {
  // Even if the server has the same URL under a DIFFERENT collection,
  // a local item under a soon-to-be-created collection is its own row.
  const store = storeWith([
    mkAddCollection({ name: 'NewCol' }),
    mkAddLink({ url: 'https://shared.example', collectionId: -1 }),
  ]);
  const server = {
    collections: [{ id: 99, name: 'OtherCol', ownerId: 1 }],
    links: [{ collectionId: 99, url: 'https://shared.example' }],
  };
  const plan = planMerge(store, server);
  assert.equal(plan.linkActions.length, 1);
  assert.equal(plan.linkActions[0].kind, 'create');
  assert.equal(plan.summary.linksToSkip, 0);
});

test('planMerge counts already-synced (positive-id) items separately', () => {
  const baseStore = createEmptyStore();
  const withCollection = {
    ...baseStore,
    collections: [
      { id: 42, ownerId: 1, name: 'Synced', description: '', color: '', parentId: 0 },
    ],
  };
  const withLink = {
    ...withCollection,
    links: [
      { id: 777, name: 'synced', url: 'https://s.example', description: '', createdAt: '',
        collectionId: 42, pinned: false, tagIds: [] },
    ],
  };
  const plan = planMerge(withLink, { collections: [], links: [] });
  assert.equal(plan.collectionActions.length, 0);
  assert.equal(plan.linkActions.length, 0);
  assert.equal(plan.summary.collectionsAlreadySynced, 1);
  assert.equal(plan.summary.linksAlreadySynced, 1);
});

test('planMerge resolves tagNames from the local tag table', () => {
  const store = storeWith([
    mkAddCollection({ name: 'Tech' }),
    mkAddLink({ url: 'https://a.example', collectionId: -1, tags: [{ name: 'alpha' }, { name: 'beta' }] }),
  ]);
  const plan = planMerge(store, { collections: [], links: [] });
  const create = plan.linkActions[0];
  assert.deepEqual(create.tagNames.sort(), ['alpha', 'beta']);
});

// --- applyMergeResult -----------------------------------------------------

test('applyMergeResult remaps collection and link ids on full success', () => {
  const store = storeWith([
    mkAddCollection({ name: 'Tech' }),
    mkAddLink({ url: 'https://a.example', collectionId: -1, name: 'A' }),
    mkAddLink({ url: 'https://b.example', collectionId: -1, name: 'B' }),
  ]);
  const plan = planMerge(store, { collections: [], links: [] });

  const results = {
    collectionsCreated: new Map([[-1, 500]]),
    linksCreated: new Map([[-1, 1001], [-2, 1002]]),
  };
  const { store: next, summary } = applyMergeResult(store, plan, results);

  assert.equal(next.collections[0].id, 500);
  const mappedLinks = next.links.sort((a, b) => a.id - b.id);
  assert.deepEqual(mappedLinks.map((l) => l.id), [1001, 1002]);
  for (const l of mappedLinks) {
    assert.equal(l.collectionId, 500);
  }
  assert.equal(summary.collectionsRemapped, 1);
  assert.equal(summary.linksRemapped, 2);
  assert.equal(summary.collectionsFailed, 0);
  assert.equal(summary.linksFailed, 0);
});

test('applyMergeResult remaps to the server id when a collection was reused', () => {
  const store = storeWith([
    mkAddCollection({ name: 'Tech' }),
    mkAddLink({ url: 'https://a.example', collectionId: -1 }),
  ]);
  const server = {
    collections: [{ id: 77, name: 'Tech', ownerId: 2 }],
    links: [],
  };
  const plan = planMerge(store, server);

  const results = {
    collectionsCreated: new Map(),
    linksCreated: new Map([[-1, 999]]),
  };
  const { store: next } = applyMergeResult(store, plan, results);

  assert.equal(next.collections.length, 1);
  assert.equal(next.collections[0].id, 77);
  assert.equal(next.links[0].id, 999);
  assert.equal(next.links[0].collectionId, 77);
});

test('applyMergeResult keeps a failed collection negative and its links remain pointing at it', () => {
  const store = storeWith([
    mkAddCollection({ name: 'Tech' }),
    mkAddLink({ url: 'https://a.example', collectionId: -1 }),
  ]);
  const plan = planMerge(store, { collections: [], links: [] });

  const results = {
    collectionsCreated: new Map(), // nothing succeeded
    linksCreated: new Map(),
    failedCollections: [-1],
    failedLinks: [-1],
  };
  const { store: next, summary } = applyMergeResult(store, plan, results);

  assert.equal(next.collections[0].id, -1);
  assert.equal(next.links[0].id, -1);
  assert.equal(next.links[0].collectionId, -1);
  assert.equal(summary.collectionsFailed, 1);
  assert.equal(summary.linksFailed, 1);
  assert.equal(summary.collectionsRemapped, 0);
  assert.equal(summary.linksRemapped, 0);
});

test('applyMergeResult keeps skipped links by default and drops them when dropSkipped=true', () => {
  const store = storeWith([
    mkAddCollection({ name: 'Tech' }),
    mkAddLink({ url: 'https://dup.example', collectionId: -1 }),
  ]);
  const server = {
    collections: [{ id: 50, name: 'Tech', ownerId: 1 }],
    links: [{ collectionId: 50, url: 'https://dup.example' }],
  };
  const plan = planMerge(store, server);
  assert.equal(plan.summary.linksToSkip, 1);

  // Default: keep the local duplicate (user may want to reconcile manually).
  const keep = applyMergeResult(store, plan, {
    collectionsCreated: new Map(),
    linksCreated: new Map(),
  });
  assert.equal(keep.store.links.length, 1);
  assert.equal(keep.store.links[0].url, 'https://dup.example');
  assert.equal(keep.summary.linksSkippedDropped, 0);

  // Opt-in: drop the skipped local duplicate.
  const drop = applyMergeResult(
    store,
    plan,
    { collectionsCreated: new Map(), linksCreated: new Map() },
    { dropSkipped: true },
  );
  assert.equal(drop.store.links.length, 0);
  assert.equal(drop.summary.linksSkippedDropped, 1);
});

test('applyMergeResult dedupes collections when two local rows map to the same server id', () => {
  // Start with two local collections (-1 and -2) coincidentally named "Tech"
  // — both will map to the same server collection (id 50).
  let store = createEmptyStore();
  ({ store } = addCollection(store, { name: 'Tech', color: '#A' }));
  ({ store } = addCollection(store, { name: 'Tech', color: '#B' })); // duplicate name allowed

  ({ store } = addLink(store, { url: 'https://a.example', collectionId: -1 }, FIXED_NOW));
  ({ store } = addLink(store, { url: 'https://b.example', collectionId: -2 }, FIXED_NOW + 1));

  const server = {
    collections: [{ id: 50, name: 'Tech', ownerId: 1 }],
    links: [],
  };
  const plan = planMerge(store, server);
  const { store: next } = applyMergeResult(store, plan, {
    collectionsCreated: new Map(),
    linksCreated: new Map([[-1, 10], [-2, 20]]),
  });

  // both collections dedupe to the single server row
  assert.equal(next.collections.length, 1);
  assert.equal(next.collections[0].id, 50);
  // but both links survive, now pointing at the shared server id
  assert.equal(next.links.length, 2);
  for (const l of next.links) {
    assert.equal(l.collectionId, 50);
  }
});

test('applyMergeResult accepts plain object maps as well as Map instances', () => {
  const store = storeWith([
    mkAddCollection({ name: 'Tech' }),
    mkAddLink({ url: 'https://a.example', collectionId: -1 }),
  ]);
  const plan = planMerge(store, { collections: [], links: [] });
  const { store: next } = applyMergeResult(store, plan, {
    collectionsCreated: { '-1': 300 },
    linksCreated: { '-1': 400 },
  });
  assert.equal(next.collections[0].id, 300);
  assert.equal(next.links[0].id, 400);
  assert.equal(next.links[0].collectionId, 300);
});

test('applyMergeResult preserves parent hierarchy when both parent and child are created', () => {
  let store = createEmptyStore();
  ({ store } = addCollection(store, { name: 'Parent' }));
  ({ store } = addCollection(store, { name: 'Child', parentId: -1 }));
  const plan = planMerge(store, { collections: [], links: [] });
  const { store: next } = applyMergeResult(store, plan, {
    collectionsCreated: new Map([[-1, 100], [-2, 200]]),
    linksCreated: new Map(),
  });
  const parent = next.collections.find((c) => c.name === 'Parent');
  const child = next.collections.find((c) => c.name === 'Child');
  assert.equal(parent.id, 100);
  assert.equal(child.id, 200);
  assert.equal(child.parentId, 100);
});

test('applyMergeResult does not touch synced rows that were not part of the plan', () => {
  // pre-existing synced row — should survive applyMergeResult untouched.
  const synced = {
    id: 42, ownerId: 1, name: 'Synced', description: '', color: '', parentId: 0,
  };
  const store = {
    links: [],
    collections: [synced, { id: -1, ownerId: 0, name: 'Local', description: '', color: '', parentId: 0 }],
    tags: [],
  };
  const plan = planMerge(store, { collections: [], links: [] });
  const { store: next } = applyMergeResult(store, plan, {
    collectionsCreated: new Map([[-1, 500]]),
    linksCreated: new Map(),
  });
  assert.ok(next.collections.some((c) => c.id === 42 && c.name === 'Synced'));
  assert.ok(next.collections.some((c) => c.id === 500 && c.name === 'Local'));
});
