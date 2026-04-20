// Versioned backup format for the local/offline store.
//
// Goals:
//   * Full fidelity round-trip for a local-only user (export → import =
//     identical store with `replace` strategy).
//   * Safe cross-device merges: two different devices whose users have
//     colliding negative ids must be merge-able without clobbering each
//     other. The `merge` strategy achieves this by remapping every
//     imported row onto fresh local ids via addLink / addCollection /
//     ensureTag, deduping by (collection name, url) for links and by name
//     for collections / tags.
//   * Explicit version gate: anything that isn't `format: "folio-backup"`
//     at the current version throws rather than silently discarding data.

import {
  createEmptyStore,
  parseStore,
  addCollection,
  addLink,
  ensureTag,
} from './local-store.mjs';

export const BACKUP_FORMAT = 'folio-backup';
export const BACKUP_VERSION = 1;

function stringOrEmpty(value) {
  return typeof value === 'string' ? value : '';
}

function sortRowsById(rows) {
  return rows.slice().sort((a, b) => a.id - b.id);
}

function snapshotForExport(store) {
  const base = store ?? createEmptyStore();
  return {
    links: sortRowsById(base.links).map((l) => ({
      id: l.id,
      name: l.name,
      url: l.url,
      description: l.description,
      createdAt: l.createdAt,
      collectionId: l.collectionId,
      pinned: l.pinned,
      tagIds: l.tagIds.slice(),
    })),
    collections: sortRowsById(base.collections).map((c) => ({
      id: c.id,
      ownerId: c.ownerId,
      name: c.name,
      description: c.description,
      color: c.color,
      parentId: c.parentId,
    })),
    tags: sortRowsById(base.tags).map((t) => ({ id: t.id, name: t.name })),
  };
}

export function exportStore(store, options) {
  const exportedAt = stringOrEmpty(options?.exportedAt).length > 0
    ? stringOrEmpty(options.exportedAt)
    : new Date().toISOString();
  const snapshot = snapshotForExport(store);
  return JSON.stringify({
    format: BACKUP_FORMAT,
    version: BACKUP_VERSION,
    exportedAt,
    collections: snapshot.collections,
    tags: snapshot.tags,
    links: snapshot.links,
  }, null, 2);
}

export function parseBackup(raw) {
  if (typeof raw !== 'string' || raw.length === 0) {
    throw new Error('BACKUP_EMPTY');
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    throw new Error('BACKUP_MALFORMED_JSON');
  }
  if (parsed?.format !== BACKUP_FORMAT) {
    throw new Error('BACKUP_UNRECOGNIZED_FORMAT');
  }
  if (parsed?.version !== BACKUP_VERSION) {
    throw new Error(`BACKUP_UNSUPPORTED_VERSION:${parsed?.version}`);
  }
  // Reuse local-store's sanitizer by wrapping the relevant sections.
  const sanitized = parseStore(JSON.stringify({
    links: Array.isArray(parsed.links) ? parsed.links : [],
    collections: Array.isArray(parsed.collections) ? parsed.collections : [],
    tags: Array.isArray(parsed.tags) ? parsed.tags : [],
  }));
  return {
    exportedAt: stringOrEmpty(parsed.exportedAt),
    store: sanitized,
  };
}

function emptySummary() {
  return {
    linksImported: 0,
    linksSkipped: 0,
    collectionsImported: 0,
    collectionsReused: 0,
    tagsImported: 0,
    tagsReused: 0,
  };
}

function mergeBackupStore(currentStore, backupStore) {
  const summary = emptySummary();
  let working = {
    links: currentStore.links.slice(),
    collections: currentStore.collections.slice(),
    tags: currentStore.tags.slice(),
  };

  // 1. Collections — dedup by name, remember mapping for link remap later.
  const collectionMap = new Map();
  const createdCollectionIds = new Set();
  for (const c of backupStore.collections) {
    const match = working.collections.find((x) => x.name === c.name);
    if (match) {
      collectionMap.set(c.id, match.id);
      summary.collectionsReused += 1;
      continue;
    }
    const res = addCollection(working, {
      name: c.name,
      ownerId: c.ownerId,
      description: c.description,
      color: c.color,
      parentId: 0, // resolved in a second pass so forward refs work
    });
    working = res.store;
    collectionMap.set(c.id, res.collection.id);
    createdCollectionIds.add(res.collection.id);
    summary.collectionsImported += 1;
  }

  // 2. Second pass — fix parentId on freshly-created collections.
  if (createdCollectionIds.size > 0) {
    const collections = working.collections.slice();
    for (const c of backupStore.collections) {
      if (!c.parentId) continue;
      const mappedId = collectionMap.get(c.id);
      if (mappedId === undefined || !createdCollectionIds.has(mappedId)) continue;
      const mappedParentId = collectionMap.get(c.parentId);
      if (mappedParentId === undefined) continue;
      const idx = collections.findIndex((col) => col.id === mappedId);
      if (idx < 0) continue;
      if (collections[idx].parentId === mappedParentId) continue;
      collections[idx] = {
        id: collections[idx].id,
        ownerId: collections[idx].ownerId,
        name: collections[idx].name,
        description: collections[idx].description,
        color: collections[idx].color,
        parentId: mappedParentId,
      };
    }
    working = { ...working, collections };
  }

  // 3. Tags — ensure each backup tag (even orphans) exists by name.
  for (const t of backupStore.tags) {
    const match = working.tags.find((x) => x.name === t.name);
    if (match) {
      summary.tagsReused += 1;
      continue;
    }
    const res = ensureTag(working, t.name);
    working = res.store;
    summary.tagsImported += 1;
  }

  // 4. Links — remap collectionId via collectionMap, resolve tag names
  //    via backup's own tag table, skip if an identical (collection, url)
  //    link already exists.
  const backupTagNameById = new Map(backupStore.tags.map((t) => [t.id, t.name]));
  for (const l of backupStore.links) {
    const mappedCollectionId = collectionMap.get(l.collectionId) ?? 0;
    const tagNames = l.tagIds
      .map((tid) => backupTagNameById.get(tid))
      .filter((name) => typeof name === 'string' && name.length > 0);

    const duplicate = working.links.find(
      (x) => x.collectionId === mappedCollectionId && x.url === l.url,
    );
    if (duplicate) {
      summary.linksSkipped += 1;
      continue;
    }

    const res = addLink(working, {
      name: l.name,
      url: l.url,
      description: l.description,
      createdAt: l.createdAt,
      collectionId: mappedCollectionId,
      pinned: l.pinned,
      tags: tagNames.map((name) => ({ name })),
    });
    working = res.store;
    summary.linksImported += 1;
  }

  return { store: working, summary };
}

export function importBackup(store, raw, options) {
  const parsed = parseBackup(raw);
  const strategy = options?.strategy ?? 'merge';

  if (strategy === 'replace') {
    return {
      store: {
        links: parsed.store.links.slice(),
        collections: parsed.store.collections.slice(),
        tags: parsed.store.tags.slice(),
      },
      summary: {
        linksImported: parsed.store.links.length,
        linksSkipped: 0,
        collectionsImported: parsed.store.collections.length,
        collectionsReused: 0,
        tagsImported: parsed.store.tags.length,
        tagsReused: 0,
      },
      exportedAt: parsed.exportedAt,
    };
  }

  if (strategy === 'merge') {
    const result = mergeBackupStore(store ?? createEmptyStore(), parsed.store);
    return {
      store: result.store,
      summary: result.summary,
      exportedAt: parsed.exportedAt,
    };
  }

  throw new Error(`BACKUP_UNKNOWN_STRATEGY:${strategy}`);
}
