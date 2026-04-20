// Pure-JS planner for pushing a local/offline store up to a Linkwarden server.
//
// Two-step shape:
//   1. `planMerge(localStore, serverSnapshot)` produces a static action plan
//      (no network calls, no mutation). Each action is either:
//        * `reuse`   — server already has an entity matching by name/url.
//        * `create`  — nothing matches; caller should POST to the server.
//        * `skip`    — local link URL already exists in the resolved server
//                      collection; user's local row has no counterpart to
//                      push. Caller decides whether to drop it locally.
//   2. `applyMergeResult(store, plan, results)` rewrites the local store in
//      place of the plan: successful `reuse` + `create` actions swap their
//      negative local ids for the positive server ids; failed actions stay
//      negative so the caller can retry later. Link rows in the store also
//      have their `collectionId` remapped so references survive.
//
// The planner is pure and cursor-free: callers are expected to have already
// paged the server snapshot into memory.

function stringOrEmpty(value) {
  return typeof value === 'string' ? value : '';
}

function emptyPlanSummary() {
  return {
    collectionsToCreate: 0,
    collectionsReused: 0,
    collectionsAlreadySynced: 0,
    linksToCreate: 0,
    linksToSkip: 0,
    linksAlreadySynced: 0,
  };
}

export function planMerge(localStore, serverSnapshot) {
  const local = localStore ?? { links: [], collections: [], tags: [] };
  const server = serverSnapshot ?? { collections: [], links: [] };

  const plan = {
    collectionActions: [],
    linkActions: [],
    summary: emptyPlanSummary(),
  };

  // Name-indexed server collections (first match wins if server has dupes).
  const serverCollectionByName = new Map();
  for (const c of server.collections ?? []) {
    if (!serverCollectionByName.has(c.name)) {
      serverCollectionByName.set(c.name, c);
    }
  }

  // tempId (local, could be any sign) -> resolved server id when known.
  const collectionIdResolver = new Map();

  for (const c of local.collections ?? []) {
    if (typeof c.id === 'number' && c.id > 0) {
      plan.summary.collectionsAlreadySynced += 1;
      collectionIdResolver.set(c.id, c.id);
      continue;
    }
    const match = serverCollectionByName.get(c.name);
    if (match) {
      plan.collectionActions.push({
        kind: 'reuse',
        tempId: c.id,
        resolvedServerId: match.id,
        name: c.name,
        ownerId: match.ownerId,
      });
      collectionIdResolver.set(c.id, match.id);
      plan.summary.collectionsReused += 1;
      continue;
    }
    plan.collectionActions.push({
      kind: 'create',
      tempId: c.id,
      name: c.name,
      ownerId: c.ownerId,
      description: c.description,
      color: c.color,
      parentTempId: c.parentId, // remapped at apply time
    });
    plan.summary.collectionsToCreate += 1;
  }

  // Server (collectionId, url) -> exists?
  const serverLinkKey = (cid, url) => `${cid}::${url}`;
  const serverLinkIndex = new Set();
  for (const l of server.links ?? []) {
    serverLinkIndex.add(serverLinkKey(l.collectionId, l.url));
  }

  const tagNameById = new Map();
  for (const t of local.tags ?? []) {
    tagNameById.set(t.id, t.name);
  }

  for (const l of local.links ?? []) {
    if (typeof l.id === 'number' && l.id > 0) {
      plan.summary.linksAlreadySynced += 1;
      continue;
    }
    const resolvedCollectionServerId = collectionIdResolver.get(l.collectionId);
    // We can only decide "skip as duplicate" when the target collection
    // already exists on the server. For newly-created collections, the
    // target is brand new and cannot contain duplicates.
    if (typeof resolvedCollectionServerId === 'number' && resolvedCollectionServerId > 0) {
      if (serverLinkIndex.has(serverLinkKey(resolvedCollectionServerId, l.url))) {
        plan.linkActions.push({
          kind: 'skip',
          localId: l.id,
          url: l.url,
          reason: 'DUPLICATE_URL_IN_SERVER_COLLECTION',
          collectionTempId: l.collectionId,
          resolvedCollectionServerId,
        });
        plan.summary.linksToSkip += 1;
        continue;
      }
    }

    const tagNames = (l.tagIds ?? [])
      .map((tid) => tagNameById.get(tid))
      .filter((n) => typeof n === 'string' && n.length > 0);

    plan.linkActions.push({
      kind: 'create',
      localId: l.id,
      name: stringOrEmpty(l.name),
      url: stringOrEmpty(l.url),
      description: stringOrEmpty(l.description),
      pinned: Boolean(l.pinned),
      collectionTempId: l.collectionId,
      tagNames,
    });
    plan.summary.linksToCreate += 1;
  }

  return plan;
}

function emptyApplySummary() {
  return {
    collectionsRemapped: 0,
    collectionsFailed: 0,
    linksRemapped: 0,
    linksSkippedDropped: 0,
    linksFailed: 0,
  };
}

function cloneStore(store) {
  return {
    links: (store?.links ?? []).map((l) => ({
      id: l.id,
      name: l.name,
      url: l.url,
      description: l.description,
      createdAt: l.createdAt,
      collectionId: l.collectionId,
      pinned: l.pinned,
      tagIds: (l.tagIds ?? []).slice(),
    })),
    collections: (store?.collections ?? []).map((c) => ({
      id: c.id,
      ownerId: c.ownerId,
      name: c.name,
      description: c.description,
      color: c.color,
      parentId: c.parentId,
    })),
    tags: (store?.tags ?? []).map((t) => ({ id: t.id, name: t.name })),
  };
}

export function applyMergeResult(store, plan, results, options) {
  const working = cloneStore(store);
  const summary = emptyApplySummary();
  const dropSkipped = Boolean(options?.dropSkipped);

  const collectionsCreated = results?.collectionsCreated instanceof Map
    ? results.collectionsCreated
    : new Map(Object.entries(results?.collectionsCreated ?? {}).map(([k, v]) => [Number(k), v]));
  const linksCreated = results?.linksCreated instanceof Map
    ? results.linksCreated
    : new Map(Object.entries(results?.linksCreated ?? {}).map(([k, v]) => [Number(k), v]));
  const failedCollections = new Set(Array.isArray(results?.failedCollections)
    ? results.failedCollections
    : []);
  const failedLinks = new Set(Array.isArray(results?.failedLinks) ? results.failedLinks : []);

  // 1. Build a tempId -> final id map for collections using the plan + results.
  const finalCollectionIdByTempId = new Map();
  for (const action of plan?.collectionActions ?? []) {
    if (action.kind === 'reuse') {
      finalCollectionIdByTempId.set(action.tempId, action.resolvedServerId);
      continue;
    }
    if (action.kind === 'create') {
      if (failedCollections.has(action.tempId)) {
        summary.collectionsFailed += 1;
        continue; // leave tempId unchanged in the store
      }
      const serverId = collectionsCreated.get(action.tempId);
      if (typeof serverId === 'number' && serverId > 0) {
        finalCollectionIdByTempId.set(action.tempId, serverId);
      } else {
        // Neither failed nor created — treat as failed.
        summary.collectionsFailed += 1;
      }
    }
  }

  // 2. Rewrite collection ids in the store.
  const seenCollectionIds = new Set();
  const rewrittenCollections = [];
  for (const c of working.collections) {
    const mappedId = finalCollectionIdByTempId.get(c.id);
    if (typeof mappedId === 'number' && mappedId !== c.id) {
      if (seenCollectionIds.has(mappedId)) {
        // Another local collection was 'reuse'd to the same server id —
        // drop this now-duplicate row; its links will get remapped below.
        continue;
      }
      rewrittenCollections.push({
        id: mappedId,
        ownerId: c.ownerId,
        name: c.name,
        description: c.description,
        color: c.color,
        parentId: finalCollectionIdByTempId.get(c.parentId) ?? c.parentId,
      });
      seenCollectionIds.add(mappedId);
      summary.collectionsRemapped += 1;
    } else {
      if (seenCollectionIds.has(c.id)) continue;
      rewrittenCollections.push({
        id: c.id,
        ownerId: c.ownerId,
        name: c.name,
        description: c.description,
        color: c.color,
        parentId: finalCollectionIdByTempId.get(c.parentId) ?? c.parentId,
      });
      seenCollectionIds.add(c.id);
    }
  }
  working.collections = rewrittenCollections;

  // 3. Build a localId -> final id map for links and a set of skip-ids.
  const finalLinkIdByLocalId = new Map();
  const skipDropIds = new Set();
  for (const action of plan?.linkActions ?? []) {
    if (action.kind === 'skip') {
      if (dropSkipped) {
        skipDropIds.add(action.localId);
      }
      continue;
    }
    if (action.kind === 'create') {
      if (failedLinks.has(action.localId)) {
        summary.linksFailed += 1;
        continue;
      }
      const serverId = linksCreated.get(action.localId);
      if (typeof serverId === 'number' && serverId > 0) {
        finalLinkIdByLocalId.set(action.localId, serverId);
      } else {
        summary.linksFailed += 1;
      }
    }
  }

  // 4. Rewrite links: remap id, remap collectionId, drop skip-ids when requested.
  const rewrittenLinks = [];
  for (const l of working.links) {
    if (skipDropIds.has(l.id)) {
      summary.linksSkippedDropped += 1;
      continue;
    }
    const mappedId = finalLinkIdByLocalId.get(l.id);
    const mappedCollectionId = finalCollectionIdByTempId.get(l.collectionId);
    const nextId = typeof mappedId === 'number' && mappedId !== l.id ? mappedId : l.id;
    const nextCollectionId = typeof mappedCollectionId === 'number' && mappedCollectionId !== l.collectionId
      ? mappedCollectionId
      : l.collectionId;
    if (mappedId !== undefined && mappedId !== l.id) {
      summary.linksRemapped += 1;
    }
    rewrittenLinks.push({
      id: nextId,
      name: l.name,
      url: l.url,
      description: l.description,
      createdAt: l.createdAt,
      collectionId: nextCollectionId,
      pinned: l.pinned,
      tagIds: l.tagIds.slice(),
    });
  }
  working.links = rewrittenLinks;

  return { store: working, summary };
}
