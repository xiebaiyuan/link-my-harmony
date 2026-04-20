// Pure-JS model for the offline/local bookmark store.
//
// Shape mirrors services/LocalDatabase.ets (SQLite) but lives in memory so
// that CRUD / search / pagination / tag dedup / id allocation logic can be
// tested under `node --test` without a HarmonyOS device. The ArkTS RDB
// wrapper is a thin translation layer over the same semantics.
//
// Conventions:
//   * Local-only rows use NEGATIVE ids (-1, -2, ...). Synced rows (after a
//     successful push to Linkwarden) carry the server-assigned POSITIVE id.
//     The sign of `id` is therefore the single source of truth for
//     "is this a local-only row?".
//   * Collection name/color are NOT stored on the link row — they are
//     resolved against `store.collections` at read time. This avoids the
//     rename-ripple problem.
//   * Tags are globally unique by (case-sensitive) name, matching Linkwarden
//     server semantics.

function stringOrEmpty(value) {
  return typeof value === 'string' ? value : '';
}

function numberOrZero(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function toEpochMs(value, fallback) {
  if (typeof value === 'number' && Number.isFinite(value) && value >= 0) {
    return value;
  }
  return fallback;
}

export function createEmptyStore() {
  return {
    links: [],
    collections: [],
    tags: [],
  };
}

function nextNegativeId(ids) {
  let minId = 0;
  for (const id of ids) {
    if (typeof id === 'number' && Number.isFinite(id) && id < minId) {
      minId = id;
    }
  }
  return minId - 1;
}

export function nextLinkId(store) {
  const base = store ?? createEmptyStore();
  return nextNegativeId((base.links ?? []).map((l) => l.id));
}

export function nextCollectionId(store) {
  const base = store ?? createEmptyStore();
  return nextNegativeId((base.collections ?? []).map((c) => c.id));
}

export function nextTagId(store) {
  const base = store ?? createEmptyStore();
  return nextNegativeId((base.tags ?? []).map((t) => t.id));
}

// --- internal row shapes --------------------------------------------------

function sanitizeLinkRow(row, fallbackCreatedAt) {
  return {
    id: numberOrZero(row?.id),
    name: stringOrEmpty(row?.name),
    url: stringOrEmpty(row?.url).trim(),
    description: stringOrEmpty(row?.description),
    createdAt: stringOrEmpty(row?.createdAt).length > 0
      ? stringOrEmpty(row?.createdAt)
      : fallbackCreatedAt,
    collectionId: numberOrZero(row?.collectionId),
    pinned: Boolean(row?.pinned),
    tagIds: Array.isArray(row?.tagIds)
      ? row.tagIds.map((id) => numberOrZero(id)).filter((id) => id !== 0)
      : [],
  };
}

function sanitizeCollectionRow(row) {
  return {
    id: numberOrZero(row?.id),
    ownerId: numberOrZero(row?.ownerId),
    name: stringOrEmpty(row?.name).trim(),
    description: stringOrEmpty(row?.description),
    color: stringOrEmpty(row?.color),
    parentId: numberOrZero(row?.parentId),
  };
}

function sanitizeTagRow(row) {
  return {
    id: numberOrZero(row?.id),
    name: stringOrEmpty(row?.name).trim(),
  };
}

// --- helpers --------------------------------------------------------------

function findCollection(store, id) {
  if (!id) {
    return null;
  }
  for (const c of store.collections) {
    if (c.id === id) {
      return c;
    }
  }
  return null;
}

function findLinkIndex(store, id) {
  for (let i = 0; i < store.links.length; i++) {
    if (store.links[i].id === id) {
      return i;
    }
  }
  return -1;
}

function findCollectionIndex(store, id) {
  for (let i = 0; i < store.collections.length; i++) {
    if (store.collections[i].id === id) {
      return i;
    }
  }
  return -1;
}

function findTagByName(tags, name) {
  for (const t of tags) {
    if (t.name === name) {
      return t;
    }
  }
  return null;
}

function upsertTagsByName(tags, names) {
  let working = tags.slice();
  const resolved = [];
  for (const raw of names) {
    const name = stringOrEmpty(raw).trim();
    if (name.length === 0) {
      continue;
    }
    const existing = findTagByName(working, name);
    if (existing) {
      if (!resolved.some((t) => t.id === existing.id)) {
        resolved.push(existing);
      }
      continue;
    }
    const newTag = {
      id: nextNegativeId(working.map((t) => t.id)),
      name,
    };
    working = working.concat([newTag]);
    resolved.push(newTag);
  }
  return { tags: working, resolved };
}

function hydrateLink(row, store) {
  const tags = row.tagIds
    .map((id) => store.tags.find((t) => t.id === id))
    .filter((t) => t !== undefined)
    .map((t) => ({ id: t.id, name: t.name }));
  const collection = findCollection(store, row.collectionId);
  return {
    id: row.id,
    name: row.name,
    url: row.url,
    description: row.description,
    createdAt: row.createdAt,
    collectionId: collection ? collection.id : 0,
    collectionOwnerId: collection ? collection.ownerId : 0,
    collectionName: collection ? collection.name : '',
    collectionColor: collection ? collection.color : '',
    pinned: row.pinned,
    tags,
  };
}

function sortLinkRows(rows) {
  return rows.slice().sort((a, b) => {
    if (a.createdAt !== b.createdAt) {
      return a.createdAt < b.createdAt ? 1 : -1;
    }
    // newest id first on ties (so that a freshly added negative -1 beats -2)
    return b.id - a.id;
  });
}

// --- collections ----------------------------------------------------------

export function addCollection(store, draft) {
  const base = store ?? createEmptyStore();
  const sanitized = sanitizeCollectionRow(draft);
  if (sanitized.name.length === 0) {
    throw new Error('COLLECTION_NAME_REQUIRED');
  }
  const collection = {
    id: nextCollectionId(base),
    ownerId: sanitized.ownerId,
    name: sanitized.name,
    description: sanitized.description,
    color: sanitized.color,
    parentId: sanitized.parentId,
  };
  return {
    store: {
      links: base.links,
      collections: base.collections.concat([collection]),
      tags: base.tags,
    },
    collection,
  };
}

export function updateCollection(store, id, patch) {
  const base = store ?? createEmptyStore();
  const idx = findCollectionIndex(base, id);
  if (idx < 0) {
    throw new Error(`COLLECTION_NOT_FOUND:${id}`);
  }
  const existing = base.collections[idx];
  const nextName = patch?.name !== undefined ? stringOrEmpty(patch.name).trim() : existing.name;
  if (nextName.length === 0) {
    throw new Error('COLLECTION_NAME_REQUIRED');
  }
  const next = {
    id: existing.id,
    ownerId: patch?.ownerId !== undefined ? numberOrZero(patch.ownerId) : existing.ownerId,
    name: nextName,
    description: patch?.description !== undefined ? stringOrEmpty(patch.description) : existing.description,
    color: patch?.color !== undefined ? stringOrEmpty(patch.color) : existing.color,
    parentId: patch?.parentId !== undefined ? numberOrZero(patch.parentId) : existing.parentId,
  };
  const collections = base.collections.slice();
  collections[idx] = next;
  return {
    store: {
      links: base.links,
      collections,
      tags: base.tags,
    },
    collection: next,
  };
}

export function deleteCollection(store, id, options) {
  const base = store ?? createEmptyStore();
  const idx = findCollectionIndex(base, id);
  if (idx < 0) {
    throw new Error(`COLLECTION_NOT_FOUND:${id}`);
  }
  const cascade = Boolean(options?.cascade);
  const linksInCollection = base.links.filter((l) => l.collectionId === id);
  if (linksInCollection.length > 0 && !cascade) {
    throw new Error('COLLECTION_NOT_EMPTY');
  }
  const collections = base.collections.slice();
  collections.splice(idx, 1);
  const links = cascade
    ? base.links.filter((l) => l.collectionId !== id)
    : base.links;
  return {
    links,
    collections,
    tags: base.tags,
  };
}

export function getCollectionById(store, id) {
  const base = store ?? createEmptyStore();
  const c = findCollection(base, id);
  if (!c) {
    return null;
  }
  const linkCount = base.links.reduce((n, l) => (l.collectionId === id ? n + 1 : n), 0);
  return {
    id: c.id,
    ownerId: c.ownerId,
    name: c.name,
    description: c.description,
    color: c.color,
    parentId: c.parentId,
    parentName: findParentName(base, c.parentId),
    linkCount,
  };
}

function findParentName(store, parentId) {
  if (!parentId) {
    return '';
  }
  const parent = findCollection(store, parentId);
  return parent ? parent.name : '';
}

export function listCollections(store) {
  const base = store ?? createEmptyStore();
  return base.collections.map((c) => ({
    id: c.id,
    ownerId: c.ownerId,
    name: c.name,
    description: c.description,
    color: c.color,
    parentId: c.parentId,
    parentName: findParentName(base, c.parentId),
    linkCount: base.links.reduce((n, l) => (l.collectionId === c.id ? n + 1 : n), 0),
  }));
}

// --- links ----------------------------------------------------------------

export function addLink(store, draft, now) {
  const base = store ?? createEmptyStore();
  const clock = typeof now === 'number' && Number.isFinite(now) ? now : Date.now();
  const tagsFromDraft = Array.isArray(draft?.tags)
    ? draft.tags.map((t) => stringOrEmpty(t?.name ?? t))
    : [];
  const { tags: nextTags, resolved } = upsertTagsByName(base.tags, tagsFromDraft);

  const rawCollectionId = numberOrZero(draft?.collectionId);
  const collection = findCollection(base, rawCollectionId);
  const resolvedCollectionId = collection ? collection.id : 0;

  const url = stringOrEmpty(draft?.url).trim();
  if (url.length === 0) {
    throw new Error('LINK_URL_REQUIRED');
  }

  const row = {
    id: nextLinkId(base),
    name: stringOrEmpty(draft?.name),
    url,
    description: stringOrEmpty(draft?.description),
    createdAt: stringOrEmpty(draft?.createdAt).length > 0
      ? stringOrEmpty(draft?.createdAt)
      : new Date(clock).toISOString(),
    collectionId: resolvedCollectionId,
    pinned: Boolean(draft?.pinned),
    tagIds: resolved.map((t) => t.id),
  };

  const nextStore = {
    links: base.links.concat([row]),
    collections: base.collections,
    tags: nextTags,
  };

  return {
    store: nextStore,
    link: hydrateLink(row, nextStore),
  };
}

export function updateLink(store, id, patch) {
  const base = store ?? createEmptyStore();
  const idx = findLinkIndex(base, id);
  if (idx < 0) {
    throw new Error(`LINK_NOT_FOUND:${id}`);
  }
  const existing = base.links[idx];

  let nextTagIds = existing.tagIds;
  let nextTags = base.tags;
  if (patch && Object.prototype.hasOwnProperty.call(patch, 'tags')) {
    const names = Array.isArray(patch.tags)
      ? patch.tags.map((t) => stringOrEmpty(t?.name ?? t))
      : [];
    const { tags, resolved } = upsertTagsByName(base.tags, names);
    nextTags = tags;
    nextTagIds = resolved.map((t) => t.id);
  }

  let nextCollectionId = existing.collectionId;
  if (patch && Object.prototype.hasOwnProperty.call(patch, 'collectionId')) {
    const wanted = numberOrZero(patch.collectionId);
    if (wanted === 0) {
      nextCollectionId = 0;
    } else {
      const c = findCollection(base, wanted);
      nextCollectionId = c ? c.id : 0;
    }
  }

  const nextUrl = patch && Object.prototype.hasOwnProperty.call(patch, 'url')
    ? stringOrEmpty(patch.url).trim()
    : existing.url;
  if (nextUrl.length === 0) {
    throw new Error('LINK_URL_REQUIRED');
  }

  const next = {
    id: existing.id,
    name: patch && Object.prototype.hasOwnProperty.call(patch, 'name')
      ? stringOrEmpty(patch.name)
      : existing.name,
    url: nextUrl,
    description: patch && Object.prototype.hasOwnProperty.call(patch, 'description')
      ? stringOrEmpty(patch.description)
      : existing.description,
    createdAt: existing.createdAt,
    collectionId: nextCollectionId,
    pinned: patch && Object.prototype.hasOwnProperty.call(patch, 'pinned')
      ? Boolean(patch.pinned)
      : existing.pinned,
    tagIds: nextTagIds,
  };

  const nextLinks = base.links.slice();
  nextLinks[idx] = next;
  const nextStore = {
    links: nextLinks,
    collections: base.collections,
    tags: nextTags,
  };

  return {
    store: nextStore,
    link: hydrateLink(next, nextStore),
  };
}

export function deleteLink(store, id) {
  const base = store ?? createEmptyStore();
  const idx = findLinkIndex(base, id);
  if (idx < 0) {
    throw new Error(`LINK_NOT_FOUND:${id}`);
  }
  const links = base.links.slice();
  links.splice(idx, 1);
  return {
    links,
    collections: base.collections,
    tags: base.tags,
  };
}

export function setLinkPinned(store, id, pinned) {
  return updateLink(store, id, { pinned: Boolean(pinned) });
}

export function getLinkById(store, id) {
  const base = store ?? createEmptyStore();
  const row = base.links.find((l) => l.id === id);
  if (!row) {
    return null;
  }
  return hydrateLink(row, base);
}

export function listLinks(store, filter) {
  const base = store ?? createEmptyStore();
  const {
    cursor = 0,
    searchQueryString = '',
    collectionId = 0,
    pinnedOnly = false,
    tagId = 0,
    limit = 50,
  } = filter ?? {};

  let working = base.links.slice();
  if (collectionId > 0 || collectionId < 0) {
    working = working.filter((l) => l.collectionId === collectionId);
  }
  if (pinnedOnly) {
    working = working.filter((l) => l.pinned);
  }
  if (tagId !== 0) {
    working = working.filter((l) => l.tagIds.includes(tagId));
  }
  const q = stringOrEmpty(searchQueryString).trim().toLowerCase();
  if (q.length > 0) {
    working = working.filter((l) => {
      if (l.name.toLowerCase().includes(q)) return true;
      if (l.url.toLowerCase().includes(q)) return true;
      if (l.description.toLowerCase().includes(q)) return true;
      for (const tagId of l.tagIds) {
        const tag = base.tags.find((t) => t.id === tagId);
        if (tag && tag.name.toLowerCase().includes(q)) return true;
      }
      return false;
    });
  }

  const sorted = sortLinkRows(working);
  let start = 0;
  if (cursor !== 0) {
    const cursorIdx = sorted.findIndex((l) => l.id === cursor);
    start = cursorIdx >= 0 ? cursorIdx + 1 : sorted.length; // unknown cursor ⇒ empty page
  }

  const effectiveLimit = Math.max(1, Math.floor(numberOrZero(limit) || 50));
  const end = start + effectiveLimit;
  const page = sorted.slice(start, end);
  const hasMore = sorted.length > end;

  return {
    links: page.map((row) => hydrateLink(row, base)),
    nextCursor: hasMore && page.length > 0 ? page[page.length - 1].id : -1,
  };
}

// --- tags -----------------------------------------------------------------

export function ensureTag(store, name) {
  const base = store ?? createEmptyStore();
  const { tags, resolved } = upsertTagsByName(base.tags, [name]);
  if (resolved.length === 0) {
    throw new Error('TAG_NAME_REQUIRED');
  }
  return {
    store: {
      links: base.links,
      collections: base.collections,
      tags,
    },
    tag: resolved[0],
  };
}

export function deleteTag(store, id) {
  const base = store ?? createEmptyStore();
  const tags = base.tags.filter((t) => t.id !== id);
  if (tags.length === base.tags.length) {
    throw new Error(`TAG_NOT_FOUND:${id}`);
  }
  const links = base.links.map((l) => {
    if (!l.tagIds.includes(id)) {
      return l;
    }
    return {
      id: l.id,
      name: l.name,
      url: l.url,
      description: l.description,
      createdAt: l.createdAt,
      collectionId: l.collectionId,
      pinned: l.pinned,
      tagIds: l.tagIds.filter((tid) => tid !== id),
    };
  });
  return {
    links,
    collections: base.collections,
    tags,
  };
}

export function listTags(store) {
  const base = store ?? createEmptyStore();
  return base.tags.map((t) => ({
    id: t.id,
    name: t.name,
    linkCount: base.links.reduce(
      (n, l) => (l.tagIds.includes(t.id) ? n + 1 : n),
      0,
    ),
  }));
}

// --- serialization (re-usable for snapshot + backup) ----------------------

export function serializeStore(store) {
  const base = store ?? createEmptyStore();
  return JSON.stringify({
    links: base.links.map((l) => ({
      id: l.id,
      name: l.name,
      url: l.url,
      description: l.description,
      createdAt: l.createdAt,
      collectionId: l.collectionId,
      pinned: l.pinned,
      tagIds: l.tagIds.slice(),
    })),
    collections: base.collections.map((c) => ({
      id: c.id,
      ownerId: c.ownerId,
      name: c.name,
      description: c.description,
      color: c.color,
      parentId: c.parentId,
    })),
    tags: base.tags.map((t) => ({ id: t.id, name: t.name })),
  });
}

export function parseStore(raw) {
  if (typeof raw !== 'string' || raw.length === 0) {
    return createEmptyStore();
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    return createEmptyStore();
  }
  const collections = Array.isArray(parsed?.collections)
    ? parsed.collections.map((c) => sanitizeCollectionRow(c)).filter((c) => c.id !== 0)
    : [];
  const tags = Array.isArray(parsed?.tags)
    ? parsed.tags.map((t) => sanitizeTagRow(t)).filter((t) => t.id !== 0 && t.name.length > 0)
    : [];
  const links = Array.isArray(parsed?.links)
    ? parsed.links
      .map((l) => sanitizeLinkRow(l, ''))
      .filter((l) => l.id !== 0 && l.url.length > 0)
    : [];
  return { links, collections, tags };
}

// --- public helpers for tests / consumers ---------------------------------

export const __internals = {
  hydrateLink,
  sortLinkRows,
  upsertTagsByName,
  sanitizeLinkRow,
  toEpochMs,
};
