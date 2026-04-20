// SQLite-backed implementation of the local/offline bookmark store.
//
// This mirrors the pure-JS logic under `harmony/tooling/local-store.mjs`,
// `local-backup.mjs`, and `merge-planner.mjs` — those modules are covered by
// node --test so the algorithmic correctness (id allocation, dedup, merge
// id remap, backup envelope validation) is already exercised off-device.
//
// This file is the thin persistence layer. It uses
// `@ohos.data.relationalStore` (SQLite) so that we do not have to load the
// whole bookmark set into memory, and so the user's data sits on disk with
// ACID guarantees between writes.
//
// Schema is explicit (no autoincrement) because local-only rows use
// negative ids allocated by `nextLocalId(existingIds)`; once the user
// signs in and the merge flow completes, each row's id is rewritten to
// the positive server id.

import relationalStore from '@ohos.data.relationalStore';
import type { LinkItem, LinkTag, CollectionItem, PagedLinks } from '../common/Models';
import {
  LOCAL_DB_NAME,
  LOCAL_DB_VERSION,
  BACKUP_FORMAT,
  BACKUP_VERSION,
  nextLocalId,
  normalizeTagNames,
  toIntegerOrZero,
  toStringOrEmpty,
  type LocalLinkDraft,
  type LocalLinkDraftTag,
  type LocalLinkPatch,
  type LocalCollectionDraft,
  type LocalCollectionPatch,
  type LocalLinkFilter,
  type BackupEnvelope,
  type BackupLinkRow,
  type BackupCollectionRow,
  type BackupTagRow,
  type ImportStrategy,
  type ImportSummary,
} from '../common/LocalStore';

const TABLE_COLLECTIONS: string = 'collections';
const TABLE_TAGS: string = 'tags';
const TABLE_LINKS: string = 'links';
const TABLE_LINK_TAGS: string = 'link_tags';

const CREATE_COLLECTIONS_SQL: string =
  `CREATE TABLE IF NOT EXISTS ${TABLE_COLLECTIONS} (` +
  `  id INTEGER PRIMARY KEY,` +
  `  owner_id INTEGER NOT NULL DEFAULT 0,` +
  `  name TEXT NOT NULL,` +
  `  description TEXT NOT NULL DEFAULT '',` +
  `  color TEXT NOT NULL DEFAULT '',` +
  `  parent_id INTEGER NOT NULL DEFAULT 0` +
  `)`;

const CREATE_TAGS_SQL: string =
  `CREATE TABLE IF NOT EXISTS ${TABLE_TAGS} (` +
  `  id INTEGER PRIMARY KEY,` +
  `  name TEXT NOT NULL UNIQUE` +
  `)`;

const CREATE_LINKS_SQL: string =
  `CREATE TABLE IF NOT EXISTS ${TABLE_LINKS} (` +
  `  id INTEGER PRIMARY KEY,` +
  `  name TEXT NOT NULL DEFAULT '',` +
  `  url TEXT NOT NULL,` +
  `  description TEXT NOT NULL DEFAULT '',` +
  `  created_at TEXT NOT NULL DEFAULT '',` +
  `  collection_id INTEGER NOT NULL DEFAULT 0,` +
  `  pinned INTEGER NOT NULL DEFAULT 0` +
  `)`;

const CREATE_LINK_TAGS_SQL: string =
  `CREATE TABLE IF NOT EXISTS ${TABLE_LINK_TAGS} (` +
  `  link_id INTEGER NOT NULL,` +
  `  tag_id INTEGER NOT NULL,` +
  `  PRIMARY KEY (link_id, tag_id)` +
  `)`;

const CREATE_IDX_LINKS_COLLECTION: string =
  `CREATE INDEX IF NOT EXISTS idx_links_collection ON ${TABLE_LINKS}(collection_id)`;
const CREATE_IDX_LINKS_PINNED: string =
  `CREATE INDEX IF NOT EXISTS idx_links_pinned ON ${TABLE_LINKS}(pinned)`;
const CREATE_IDX_LINKS_CREATED: string =
  `CREATE INDEX IF NOT EXISTS idx_links_created ON ${TABLE_LINKS}(created_at DESC)`;

interface LinkRow {
  id: number;
  name: string;
  url: string;
  description: string;
  createdAt: string;
  collectionId: number;
  pinned: boolean;
}

interface CollectionRow {
  id: number;
  ownerId: number;
  name: string;
  description: string;
  color: string;
  parentId: number;
}

export class LocalDatabase {
  private context: Context;
  private store: relationalStore.RdbStore | null = null;

  constructor(context: Context) {
    this.context = context;
  }

  async init(): Promise<void> {
    if (this.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: LOCAL_DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S2,
    };
    this.store = await relationalStore.getRdbStore(this.context, config);
    await this.store.executeSql(CREATE_COLLECTIONS_SQL);
    await this.store.executeSql(CREATE_TAGS_SQL);
    await this.store.executeSql(CREATE_LINKS_SQL);
    await this.store.executeSql(CREATE_LINK_TAGS_SQL);
    await this.store.executeSql(CREATE_IDX_LINKS_COLLECTION);
    await this.store.executeSql(CREATE_IDX_LINKS_PINNED);
    await this.store.executeSql(CREATE_IDX_LINKS_CREATED);
  }

  private requireStore(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('LOCAL_DB_NOT_INITIALIZED');
    }
    return this.store;
  }

  // --- id allocation ------------------------------------------------------

  private async allocateNextId(table: string): Promise<number> {
    const rs = await this.requireStore().querySql(`SELECT MIN(id) AS min_id FROM ${table}`);
    try {
      if (!rs.goToFirstRow()) {
        return -1;
      }
      const idx: number = rs.getColumnIndex('min_id');
      if (idx < 0) {
        return -1;
      }
      if (rs.isColumnNull(idx)) {
        return -1;
      }
      const minId: number = rs.getLong(idx);
      return minId < 0 ? minId - 1 : -1;
    } finally {
      rs.close();
    }
  }

  // --- collections --------------------------------------------------------

  async addCollection(draft: LocalCollectionDraft): Promise<CollectionItem> {
    const name: string = toStringOrEmpty(draft.name).trim();
    if (name.length === 0) {
      throw new Error('COLLECTION_NAME_REQUIRED');
    }
    const id: number = await this.allocateNextId(TABLE_COLLECTIONS);
    const values: relationalStore.ValuesBucket = {
      id,
      owner_id: toIntegerOrZero(draft.ownerId),
      name,
      description: toStringOrEmpty(draft.description),
      color: toStringOrEmpty(draft.color),
      parent_id: toIntegerOrZero(draft.parentId),
    };
    await this.requireStore().insert(TABLE_COLLECTIONS, values);
    const result: CollectionItem | null = await this.getCollectionById(id);
    if (result === null) {
      throw new Error('COLLECTION_INSERT_FAILED');
    }
    return result;
  }

  async updateCollection(id: number, patch: LocalCollectionPatch): Promise<CollectionItem> {
    const existing: CollectionRow | null = await this.fetchCollectionRow(id);
    if (existing === null) {
      throw new Error(`COLLECTION_NOT_FOUND:${id}`);
    }
    const nextName: string = patch.name !== undefined
      ? toStringOrEmpty(patch.name).trim()
      : existing.name;
    if (nextName.length === 0) {
      throw new Error('COLLECTION_NAME_REQUIRED');
    }
    const values: relationalStore.ValuesBucket = {
      owner_id: patch.ownerId !== undefined ? toIntegerOrZero(patch.ownerId) : existing.ownerId,
      name: nextName,
      description: patch.description !== undefined ? toStringOrEmpty(patch.description) : existing.description,
      color: patch.color !== undefined ? toStringOrEmpty(patch.color) : existing.color,
      parent_id: patch.parentId !== undefined ? toIntegerOrZero(patch.parentId) : existing.parentId,
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_COLLECTIONS);
    predicates.equalTo('id', id);
    await this.requireStore().update(values, predicates);
    const result: CollectionItem | null = await this.getCollectionById(id);
    if (result === null) {
      throw new Error('COLLECTION_UPDATE_FAILED');
    }
    return result;
  }

  async deleteCollection(id: number, cascade: boolean = false): Promise<void> {
    const existing: CollectionRow | null = await this.fetchCollectionRow(id);
    if (existing === null) {
      throw new Error(`COLLECTION_NOT_FOUND:${id}`);
    }
    const linkCount: number = await this.countLinksInCollection(id);
    if (linkCount > 0 && !cascade) {
      throw new Error('COLLECTION_NOT_EMPTY');
    }
    const store = this.requireStore();
    if (cascade && linkCount > 0) {
      const links: Array<LinkRow> = await this.fetchLinkRowsByCollection(id);
      for (let i: number = 0; i < links.length; i++) {
        await this.deleteLink(links[i].id);
      }
    }
    const predicates = new relationalStore.RdbPredicates(TABLE_COLLECTIONS);
    predicates.equalTo('id', id);
    await store.delete(predicates);
  }

  async getCollectionById(id: number): Promise<CollectionItem | null> {
    const row: CollectionRow | null = await this.fetchCollectionRow(id);
    if (row === null) {
      return null;
    }
    const linkCount: number = await this.countLinksInCollection(row.id);
    const parentName: string = row.parentId !== 0
      ? await this.fetchCollectionName(row.parentId)
      : '';
    return {
      id: row.id,
      ownerId: row.ownerId,
      name: row.name,
      description: row.description,
      color: row.color,
      parentId: row.parentId,
      parentName,
      linkCount,
    };
  }

  async listCollections(): Promise<Array<CollectionItem>> {
    const store = this.requireStore();
    const rs = await store.querySql(
      `SELECT c.id, c.owner_id, c.name, c.description, c.color, c.parent_id,` +
      ` (SELECT COUNT(*) FROM ${TABLE_LINKS} l WHERE l.collection_id = c.id) AS link_count,` +
      ` (SELECT p.name FROM ${TABLE_COLLECTIONS} p WHERE p.id = c.parent_id) AS parent_name` +
      ` FROM ${TABLE_COLLECTIONS} c` +
      ` ORDER BY c.name ASC`,
    );
    try {
      const out: Array<CollectionItem> = [];
      while (rs.goToNextRow()) {
        out.push({
          id: rs.getLong(rs.getColumnIndex('id')),
          ownerId: rs.getLong(rs.getColumnIndex('owner_id')),
          name: rs.getString(rs.getColumnIndex('name')),
          description: rs.getString(rs.getColumnIndex('description')),
          color: rs.getString(rs.getColumnIndex('color')),
          parentId: rs.getLong(rs.getColumnIndex('parent_id')),
          parentName: rs.isColumnNull(rs.getColumnIndex('parent_name'))
            ? ''
            : rs.getString(rs.getColumnIndex('parent_name')),
          linkCount: rs.getLong(rs.getColumnIndex('link_count')),
        });
      }
      return out;
    } finally {
      rs.close();
    }
  }

  private async fetchCollectionRow(id: number): Promise<CollectionRow | null> {
    const predicates = new relationalStore.RdbPredicates(TABLE_COLLECTIONS);
    predicates.equalTo('id', id);
    const rs = await this.requireStore().query(predicates,
      ['id', 'owner_id', 'name', 'description', 'color', 'parent_id']);
    try {
      if (!rs.goToFirstRow()) {
        return null;
      }
      return {
        id: rs.getLong(rs.getColumnIndex('id')),
        ownerId: rs.getLong(rs.getColumnIndex('owner_id')),
        name: rs.getString(rs.getColumnIndex('name')),
        description: rs.getString(rs.getColumnIndex('description')),
        color: rs.getString(rs.getColumnIndex('color')),
        parentId: rs.getLong(rs.getColumnIndex('parent_id')),
      };
    } finally {
      rs.close();
    }
  }

  private async fetchCollectionName(id: number): Promise<string> {
    if (id === 0) {
      return '';
    }
    const rs = await this.requireStore().querySql(
      `SELECT name FROM ${TABLE_COLLECTIONS} WHERE id = ?`, [id]);
    try {
      if (!rs.goToFirstRow()) {
        return '';
      }
      return rs.getString(rs.getColumnIndex('name'));
    } finally {
      rs.close();
    }
  }

  private async countLinksInCollection(id: number): Promise<number> {
    const rs = await this.requireStore().querySql(
      `SELECT COUNT(*) AS c FROM ${TABLE_LINKS} WHERE collection_id = ?`, [id]);
    try {
      if (!rs.goToFirstRow()) {
        return 0;
      }
      return rs.getLong(rs.getColumnIndex('c'));
    } finally {
      rs.close();
    }
  }

  // --- tags ---------------------------------------------------------------

  async ensureTag(rawName: string): Promise<LinkTag> {
    const name: string = toStringOrEmpty(rawName).trim();
    if (name.length === 0) {
      throw new Error('TAG_NAME_REQUIRED');
    }
    const existing: LinkTag | null = await this.fetchTagByName(name);
    if (existing !== null) {
      return existing;
    }
    const id: number = await this.allocateNextId(TABLE_TAGS);
    const values: relationalStore.ValuesBucket = { id, name };
    await this.requireStore().insert(TABLE_TAGS, values);
    return { id, name };
  }

  async deleteTag(id: number): Promise<void> {
    const existing: LinkTag | null = await this.fetchTagById(id);
    if (existing === null) {
      throw new Error(`TAG_NOT_FOUND:${id}`);
    }
    const store = this.requireStore();
    const jp = new relationalStore.RdbPredicates(TABLE_LINK_TAGS);
    jp.equalTo('tag_id', id);
    await store.delete(jp);
    const tp = new relationalStore.RdbPredicates(TABLE_TAGS);
    tp.equalTo('id', id);
    await store.delete(tp);
  }

  async listTags(): Promise<Array<LinkTag>> {
    const rs = await this.requireStore().querySql(
      `SELECT id, name FROM ${TABLE_TAGS} ORDER BY name ASC`);
    try {
      const out: Array<LinkTag> = [];
      while (rs.goToNextRow()) {
        out.push({
          id: rs.getLong(rs.getColumnIndex('id')),
          name: rs.getString(rs.getColumnIndex('name')),
        });
      }
      return out;
    } finally {
      rs.close();
    }
  }

  private async fetchTagByName(name: string): Promise<LinkTag | null> {
    const rs = await this.requireStore().querySql(
      `SELECT id, name FROM ${TABLE_TAGS} WHERE name = ? LIMIT 1`, [name]);
    try {
      if (!rs.goToFirstRow()) {
        return null;
      }
      return {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
      };
    } finally {
      rs.close();
    }
  }

  private async fetchTagById(id: number): Promise<LinkTag | null> {
    const rs = await this.requireStore().querySql(
      `SELECT id, name FROM ${TABLE_TAGS} WHERE id = ? LIMIT 1`, [id]);
    try {
      if (!rs.goToFirstRow()) {
        return null;
      }
      return {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
      };
    } finally {
      rs.close();
    }
  }

  private async fetchLinkTagIds(linkId: number): Promise<Array<number>> {
    const rs = await this.requireStore().querySql(
      `SELECT tag_id FROM ${TABLE_LINK_TAGS} WHERE link_id = ?`, [linkId]);
    try {
      const out: Array<number> = [];
      while (rs.goToNextRow()) {
        out.push(rs.getLong(rs.getColumnIndex('tag_id')));
      }
      return out;
    } finally {
      rs.close();
    }
  }

  private async fetchLinkTags(linkId: number): Promise<Array<LinkTag>> {
    const rs = await this.requireStore().querySql(
      `SELECT t.id, t.name FROM ${TABLE_TAGS} t` +
      ` INNER JOIN ${TABLE_LINK_TAGS} lt ON lt.tag_id = t.id` +
      ` WHERE lt.link_id = ?`, [linkId]);
    try {
      const out: Array<LinkTag> = [];
      while (rs.goToNextRow()) {
        out.push({
          id: rs.getLong(rs.getColumnIndex('id')),
          name: rs.getString(rs.getColumnIndex('name')),
        });
      }
      return out;
    } finally {
      rs.close();
    }
  }

  // --- links --------------------------------------------------------------

  async addLink(draft: LocalLinkDraft, nowMs?: number): Promise<LinkItem> {
    const url: string = toStringOrEmpty(draft.url).trim();
    if (url.length === 0) {
      throw new Error('LINK_URL_REQUIRED');
    }
    const store = this.requireStore();
    const linkId: number = await this.allocateNextId(TABLE_LINKS);
    const createdAtInput: string = toStringOrEmpty(draft.createdAt);
    const clock: number = typeof nowMs === 'number' && Number.isFinite(nowMs)
      ? nowMs
      : Date.now();
    const createdAt: string = createdAtInput.length > 0
      ? createdAtInput
      : new Date(clock).toISOString();

    const collectionIdRaw: number = toIntegerOrZero(draft.collectionId);
    const resolvedCollectionId: number = collectionIdRaw !== 0
      && (await this.fetchCollectionRow(collectionIdRaw)) !== null
        ? collectionIdRaw
        : 0;

    const linkValues: relationalStore.ValuesBucket = {
      id: linkId,
      name: toStringOrEmpty(draft.name),
      url,
      description: toStringOrEmpty(draft.description),
      created_at: createdAt,
      collection_id: resolvedCollectionId,
      pinned: draft.pinned === true ? 1 : 0,
    };
    await store.insert(TABLE_LINKS, linkValues);

    const tagNames: Array<string> = normalizeTagNames(draft.tags);
    for (let i: number = 0; i < tagNames.length; i++) {
      const tag: LinkTag = await this.ensureTag(tagNames[i]);
      const bridgeValues: relationalStore.ValuesBucket = {
        link_id: linkId,
        tag_id: tag.id,
      };
      await store.insert(TABLE_LINK_TAGS, bridgeValues);
    }

    const result: LinkItem | null = await this.getLinkById(linkId);
    if (result === null) {
      throw new Error('LINK_INSERT_FAILED');
    }
    return result;
  }

  async updateLink(id: number, patch: LocalLinkPatch): Promise<LinkItem> {
    const existing: LinkRow | null = await this.fetchLinkRow(id);
    if (existing === null) {
      throw new Error(`LINK_NOT_FOUND:${id}`);
    }
    const store = this.requireStore();

    const nextUrl: string = patch.url !== undefined
      ? toStringOrEmpty(patch.url).trim()
      : existing.url;
    if (nextUrl.length === 0) {
      throw new Error('LINK_URL_REQUIRED');
    }
    let nextCollectionId: number = existing.collectionId;
    if (patch.collectionId !== undefined) {
      const wanted: number = toIntegerOrZero(patch.collectionId);
      if (wanted === 0) {
        nextCollectionId = 0;
      } else {
        const col = await this.fetchCollectionRow(wanted);
        nextCollectionId = col !== null ? wanted : 0;
      }
    }
    const values: relationalStore.ValuesBucket = {
      name: patch.name !== undefined ? toStringOrEmpty(patch.name) : existing.name,
      url: nextUrl,
      description: patch.description !== undefined
        ? toStringOrEmpty(patch.description)
        : existing.description,
      collection_id: nextCollectionId,
      pinned: patch.pinned !== undefined
        ? (patch.pinned === true ? 1 : 0)
        : (existing.pinned ? 1 : 0),
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_LINKS);
    predicates.equalTo('id', id);
    await store.update(values, predicates);

    if (patch.tags !== undefined) {
      const bridge = new relationalStore.RdbPredicates(TABLE_LINK_TAGS);
      bridge.equalTo('link_id', id);
      await store.delete(bridge);
      const tagNames: Array<string> = normalizeTagNames(patch.tags);
      for (let i: number = 0; i < tagNames.length; i++) {
        const tag: LinkTag = await this.ensureTag(tagNames[i]);
        const bridgeValues: relationalStore.ValuesBucket = {
          link_id: id,
          tag_id: tag.id,
        };
        await store.insert(TABLE_LINK_TAGS, bridgeValues);
      }
    }

    const result: LinkItem | null = await this.getLinkById(id);
    if (result === null) {
      throw new Error('LINK_UPDATE_FAILED');
    }
    return result;
  }

  async deleteLink(id: number): Promise<void> {
    const existing: LinkRow | null = await this.fetchLinkRow(id);
    if (existing === null) {
      throw new Error(`LINK_NOT_FOUND:${id}`);
    }
    const store = this.requireStore();
    const bp = new relationalStore.RdbPredicates(TABLE_LINK_TAGS);
    bp.equalTo('link_id', id);
    await store.delete(bp);
    const lp = new relationalStore.RdbPredicates(TABLE_LINKS);
    lp.equalTo('id', id);
    await store.delete(lp);
  }

  async setLinkPinned(id: number, pinned: boolean): Promise<LinkItem> {
    return await this.updateLink(id, { pinned });
  }

  async getLinkById(id: number): Promise<LinkItem | null> {
    const row: LinkRow | null = await this.fetchLinkRow(id);
    if (row === null) {
      return null;
    }
    return await this.hydrateLinkRow(row);
  }

  async listLinks(filter: LocalLinkFilter): Promise<PagedLinks> {
    const limit: number = Math.max(1, toIntegerOrZero(filter.limit) || 50);
    const searchTerm: string = toStringOrEmpty(filter.searchQueryString).trim().toLowerCase();
    const collectionId: number = toIntegerOrZero(filter.collectionId);
    const pinnedOnly: boolean = filter.pinnedOnly === true;
    const tagId: number = toIntegerOrZero(filter.tagId);
    const cursor: number = toIntegerOrZero(filter.cursor);

    const where: Array<string> = [];
    const args: Array<relationalStore.ValueType> = [];

    if (collectionId !== 0) {
      where.push('l.collection_id = ?');
      args.push(collectionId);
    }
    if (pinnedOnly) {
      where.push('l.pinned = 1');
    }
    if (tagId !== 0) {
      where.push(`l.id IN (SELECT link_id FROM ${TABLE_LINK_TAGS} WHERE tag_id = ?)`);
      args.push(tagId);
    }
    if (searchTerm.length > 0) {
      where.push(
        `(LOWER(l.name) LIKE ? OR LOWER(l.url) LIKE ? OR LOWER(l.description) LIKE ?` +
        ` OR l.id IN (SELECT lt.link_id FROM ${TABLE_LINK_TAGS} lt` +
        `  INNER JOIN ${TABLE_TAGS} t ON t.id = lt.tag_id` +
        `  WHERE LOWER(t.name) LIKE ?))`,
      );
      const like: string = `%${searchTerm}%`;
      args.push(like, like, like, like);
    }

    // Cursor pagination over (created_at DESC, id DESC).
    // We need the cursor link's (created_at, id) to filter strictly after it.
    let cursorCreatedAt: string = '';
    let cursorId: number = 0;
    if (cursor !== 0) {
      const cursorRow: LinkRow | null = await this.fetchLinkRow(cursor);
      if (cursorRow !== null) {
        cursorCreatedAt = cursorRow.createdAt;
        cursorId = cursorRow.id;
      } else {
        return { links: [], nextCursor: -1 };
      }
    }
    if (cursor !== 0) {
      where.push('(l.created_at < ? OR (l.created_at = ? AND l.id < ?))');
      args.push(cursorCreatedAt, cursorCreatedAt, cursorId);
    }

    const whereClause: string = where.length > 0 ? ` WHERE ${where.join(' AND ')}` : '';
    // fetch limit+1 to know if there's a next page
    const sql: string =
      `SELECT l.id, l.name, l.url, l.description, l.created_at, l.collection_id, l.pinned` +
      ` FROM ${TABLE_LINKS} l${whereClause}` +
      ` ORDER BY l.created_at DESC, l.id DESC` +
      ` LIMIT ?`;
    args.push(limit + 1);
    const rs = await this.requireStore().querySql(sql, args);
    const rows: Array<LinkRow> = [];
    try {
      while (rs.goToNextRow()) {
        rows.push({
          id: rs.getLong(rs.getColumnIndex('id')),
          name: rs.getString(rs.getColumnIndex('name')),
          url: rs.getString(rs.getColumnIndex('url')),
          description: rs.getString(rs.getColumnIndex('description')),
          createdAt: rs.getString(rs.getColumnIndex('created_at')),
          collectionId: rs.getLong(rs.getColumnIndex('collection_id')),
          pinned: rs.getLong(rs.getColumnIndex('pinned')) !== 0,
        });
      }
    } finally {
      rs.close();
    }

    const hasMore: boolean = rows.length > limit;
    const page: Array<LinkRow> = hasMore ? rows.slice(0, limit) : rows;
    const links: Array<LinkItem> = [];
    for (let i: number = 0; i < page.length; i++) {
      links.push(await this.hydrateLinkRow(page[i]));
    }
    const nextCursor: number = hasMore && page.length > 0 ? page[page.length - 1].id : -1;
    return { links, nextCursor };
  }

  private async fetchLinkRow(id: number): Promise<LinkRow | null> {
    const predicates = new relationalStore.RdbPredicates(TABLE_LINKS);
    predicates.equalTo('id', id);
    const rs = await this.requireStore().query(predicates,
      ['id', 'name', 'url', 'description', 'created_at', 'collection_id', 'pinned']);
    try {
      if (!rs.goToFirstRow()) {
        return null;
      }
      return {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        url: rs.getString(rs.getColumnIndex('url')),
        description: rs.getString(rs.getColumnIndex('description')),
        createdAt: rs.getString(rs.getColumnIndex('created_at')),
        collectionId: rs.getLong(rs.getColumnIndex('collection_id')),
        pinned: rs.getLong(rs.getColumnIndex('pinned')) !== 0,
      };
    } finally {
      rs.close();
    }
  }

  private async fetchLinkRowsByCollection(collectionId: number): Promise<Array<LinkRow>> {
    const rs = await this.requireStore().querySql(
      `SELECT id, name, url, description, created_at, collection_id, pinned` +
      ` FROM ${TABLE_LINKS} WHERE collection_id = ?`, [collectionId]);
    try {
      const out: Array<LinkRow> = [];
      while (rs.goToNextRow()) {
        out.push({
          id: rs.getLong(rs.getColumnIndex('id')),
          name: rs.getString(rs.getColumnIndex('name')),
          url: rs.getString(rs.getColumnIndex('url')),
          description: rs.getString(rs.getColumnIndex('description')),
          createdAt: rs.getString(rs.getColumnIndex('created_at')),
          collectionId: rs.getLong(rs.getColumnIndex('collection_id')),
          pinned: rs.getLong(rs.getColumnIndex('pinned')) !== 0,
        });
      }
      return out;
    } finally {
      rs.close();
    }
  }

  private async hydrateLinkRow(row: LinkRow): Promise<LinkItem> {
    const tags: Array<LinkTag> = await this.fetchLinkTags(row.id);
    let collectionOwnerId: number = 0;
    let collectionName: string = '';
    let collectionColor: string = '';
    if (row.collectionId !== 0) {
      const col: CollectionRow | null = await this.fetchCollectionRow(row.collectionId);
      if (col !== null) {
        collectionOwnerId = col.ownerId;
        collectionName = col.name;
        collectionColor = col.color;
      }
    }
    return {
      id: row.id,
      name: row.name,
      url: row.url,
      description: row.description,
      createdAt: row.createdAt,
      collectionId: row.collectionId,
      collectionOwnerId,
      collectionName,
      collectionColor,
      pinned: row.pinned,
      tags,
    };
  }

  // --- export / import ----------------------------------------------------

  async exportAll(exportedAt?: string): Promise<string> {
    const store = this.requireStore();

    const collectionRows: Array<BackupCollectionRow> = [];
    {
      const rs = await store.querySql(
        `SELECT id, owner_id, name, description, color, parent_id` +
        ` FROM ${TABLE_COLLECTIONS} ORDER BY id ASC`);
      try {
        while (rs.goToNextRow()) {
          collectionRows.push({
            id: rs.getLong(rs.getColumnIndex('id')),
            ownerId: rs.getLong(rs.getColumnIndex('owner_id')),
            name: rs.getString(rs.getColumnIndex('name')),
            description: rs.getString(rs.getColumnIndex('description')),
            color: rs.getString(rs.getColumnIndex('color')),
            parentId: rs.getLong(rs.getColumnIndex('parent_id')),
          });
        }
      } finally {
        rs.close();
      }
    }

    const tagRows: Array<BackupTagRow> = [];
    {
      const rs = await store.querySql(
        `SELECT id, name FROM ${TABLE_TAGS} ORDER BY id ASC`);
      try {
        while (rs.goToNextRow()) {
          tagRows.push({
            id: rs.getLong(rs.getColumnIndex('id')),
            name: rs.getString(rs.getColumnIndex('name')),
          });
        }
      } finally {
        rs.close();
      }
    }

    const linkRows: Array<BackupLinkRow> = [];
    {
      const rs = await store.querySql(
        `SELECT id, name, url, description, created_at, collection_id, pinned` +
        ` FROM ${TABLE_LINKS} ORDER BY id ASC`);
      try {
        while (rs.goToNextRow()) {
          const lid: number = rs.getLong(rs.getColumnIndex('id'));
          linkRows.push({
            id: lid,
            name: rs.getString(rs.getColumnIndex('name')),
            url: rs.getString(rs.getColumnIndex('url')),
            description: rs.getString(rs.getColumnIndex('description')),
            createdAt: rs.getString(rs.getColumnIndex('created_at')),
            collectionId: rs.getLong(rs.getColumnIndex('collection_id')),
            pinned: rs.getLong(rs.getColumnIndex('pinned')) !== 0,
            tagIds: [], // filled below
          });
        }
      } finally {
        rs.close();
      }
    }
    for (let i: number = 0; i < linkRows.length; i++) {
      linkRows[i].tagIds = await this.fetchLinkTagIds(linkRows[i].id);
    }

    const envelope: BackupEnvelope = {
      format: BACKUP_FORMAT,
      version: BACKUP_VERSION,
      exportedAt: toStringOrEmpty(exportedAt).length > 0
        ? toStringOrEmpty(exportedAt)
        : new Date().toISOString(),
      collections: collectionRows,
      tags: tagRows,
      links: linkRows,
    };
    return JSON.stringify(envelope, null, 2);
  }

  async importBackup(raw: string, strategy: ImportStrategy): Promise<ImportSummary> {
    const envelope: BackupEnvelope = parseBackupEnvelope(raw);
    if (strategy === 'replace') {
      return await this.applyReplaceImport(envelope);
    }
    if (strategy === 'merge') {
      return await this.applyMergeImport(envelope);
    }
    throw new Error(`BACKUP_UNKNOWN_STRATEGY:${strategy}`);
  }

  async clear(): Promise<void> {
    const store = this.requireStore();
    await store.executeSql(`DELETE FROM ${TABLE_LINK_TAGS}`);
    await store.executeSql(`DELETE FROM ${TABLE_LINKS}`);
    await store.executeSql(`DELETE FROM ${TABLE_TAGS}`);
    await store.executeSql(`DELETE FROM ${TABLE_COLLECTIONS}`);
  }

  private async applyReplaceImport(envelope: BackupEnvelope): Promise<ImportSummary> {
    const store = this.requireStore();
    await store.executeSql(`DELETE FROM ${TABLE_LINK_TAGS}`);
    await store.executeSql(`DELETE FROM ${TABLE_LINKS}`);
    await store.executeSql(`DELETE FROM ${TABLE_TAGS}`);
    await store.executeSql(`DELETE FROM ${TABLE_COLLECTIONS}`);

    for (let i: number = 0; i < envelope.collections.length; i++) {
      const c: BackupCollectionRow = envelope.collections[i];
      const values: relationalStore.ValuesBucket = {
        id: c.id,
        owner_id: c.ownerId,
        name: c.name,
        description: c.description,
        color: c.color,
        parent_id: c.parentId,
      };
      await store.insert(TABLE_COLLECTIONS, values);
    }
    for (let i: number = 0; i < envelope.tags.length; i++) {
      const t: BackupTagRow = envelope.tags[i];
      const values: relationalStore.ValuesBucket = { id: t.id, name: t.name };
      await store.insert(TABLE_TAGS, values);
    }
    for (let i: number = 0; i < envelope.links.length; i++) {
      const l: BackupLinkRow = envelope.links[i];
      const values: relationalStore.ValuesBucket = {
        id: l.id,
        name: l.name,
        url: l.url,
        description: l.description,
        created_at: l.createdAt,
        collection_id: l.collectionId,
        pinned: l.pinned ? 1 : 0,
      };
      await store.insert(TABLE_LINKS, values);
      for (let j: number = 0; j < l.tagIds.length; j++) {
        const bridge: relationalStore.ValuesBucket = { link_id: l.id, tag_id: l.tagIds[j] };
        await store.insert(TABLE_LINK_TAGS, bridge);
      }
    }

    return {
      linksImported: envelope.links.length,
      linksSkipped: 0,
      collectionsImported: envelope.collections.length,
      collectionsReused: 0,
      tagsImported: envelope.tags.length,
      tagsReused: 0,
    };
  }

  private async applyMergeImport(envelope: BackupEnvelope): Promise<ImportSummary> {
    // See tooling/local-backup.mjs for the reference algorithm.
    const summary: ImportSummary = {
      linksImported: 0,
      linksSkipped: 0,
      collectionsImported: 0,
      collectionsReused: 0,
      tagsImported: 0,
      tagsReused: 0,
    };

    // 1. Collections — dedup by name.
    const collectionIdMap: Map<number, number> = new Map();
    const createdCollectionIds: Set<number> = new Set();
    for (let i: number = 0; i < envelope.collections.length; i++) {
      const c: BackupCollectionRow = envelope.collections[i];
      const match: CollectionItem | null = await this.findCollectionByName(c.name);
      if (match !== null) {
        collectionIdMap.set(c.id, match.id);
        summary.collectionsReused += 1;
        continue;
      }
      const created: CollectionItem = await this.addCollection({
        name: c.name,
        ownerId: c.ownerId,
        description: c.description,
        color: c.color,
        parentId: 0,
      });
      collectionIdMap.set(c.id, created.id);
      createdCollectionIds.add(created.id);
      summary.collectionsImported += 1;
    }
    // 2. Fix parentId for freshly-created collections.
    for (let i: number = 0; i < envelope.collections.length; i++) {
      const c: BackupCollectionRow = envelope.collections[i];
      if (c.parentId === 0) {
        continue;
      }
      const mappedId: number | undefined = collectionIdMap.get(c.id);
      if (mappedId === undefined || !createdCollectionIds.has(mappedId)) {
        continue;
      }
      const mappedParentId: number | undefined = collectionIdMap.get(c.parentId);
      if (mappedParentId === undefined) {
        continue;
      }
      await this.updateCollection(mappedId, { parentId: mappedParentId });
    }

    // 3. Tags — ensure each exists by name.
    for (let i: number = 0; i < envelope.tags.length; i++) {
      const t: BackupTagRow = envelope.tags[i];
      const existing: LinkTag | null = await this.fetchTagByName(t.name);
      if (existing !== null) {
        summary.tagsReused += 1;
        continue;
      }
      await this.ensureTag(t.name);
      summary.tagsImported += 1;
    }

    // 4. Links — remap and dedup by (collection, url).
    const backupTagNameById: Map<number, string> = new Map();
    for (let i: number = 0; i < envelope.tags.length; i++) {
      backupTagNameById.set(envelope.tags[i].id, envelope.tags[i].name);
    }
    for (let i: number = 0; i < envelope.links.length; i++) {
      const l: BackupLinkRow = envelope.links[i];
      const mappedCollectionId: number = collectionIdMap.get(l.collectionId) ?? 0;
      if (await this.linkExistsInCollectionByUrl(mappedCollectionId, l.url)) {
        summary.linksSkipped += 1;
        continue;
      }
      const tagNames: Array<string> = [];
      for (let j: number = 0; j < l.tagIds.length; j++) {
        const nm: string | undefined = backupTagNameById.get(l.tagIds[j]);
        if (typeof nm === 'string' && nm.length > 0) {
          tagNames.push(nm);
        }
      }
      await this.addLink({
        name: l.name,
        url: l.url,
        description: l.description,
        createdAt: l.createdAt,
        collectionId: mappedCollectionId,
        pinned: l.pinned,
        tags: tagNames.map((n: string) => {
          const entry: LocalLinkDraftTag = { name: n };
          return entry;
        }),
      });
      summary.linksImported += 1;
    }

    return summary;
  }

  private async findCollectionByName(name: string): Promise<CollectionItem | null> {
    const rs = await this.requireStore().querySql(
      `SELECT id FROM ${TABLE_COLLECTIONS} WHERE name = ? LIMIT 1`, [name]);
    try {
      if (!rs.goToFirstRow()) {
        return null;
      }
      const id: number = rs.getLong(rs.getColumnIndex('id'));
      return await this.getCollectionById(id);
    } finally {
      rs.close();
    }
  }

  private async linkExistsInCollectionByUrl(collectionId: number, url: string): Promise<boolean> {
    const rs = await this.requireStore().querySql(
      `SELECT 1 FROM ${TABLE_LINKS} WHERE collection_id = ? AND url = ? LIMIT 1`,
      [collectionId, url]);
    try {
      return rs.goToFirstRow();
    } finally {
      rs.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Envelope parser (shared with tooling/local-backup.mjs semantics).
// Kept as a plain function so we can use it without a DB instance — callers
// can pre-validate a user-picked file before prompting for a strategy.
// ---------------------------------------------------------------------------

export function parseBackupEnvelope(raw: string): BackupEnvelope {
  if (typeof raw !== 'string' || raw.length === 0) {
    throw new Error('BACKUP_EMPTY');
  }
  let parsed: object;
  try {
    parsed = JSON.parse(raw) as object;
  } catch (error) {
    throw new Error('BACKUP_MALFORMED_JSON');
  }
  const envelope = parsed as BackupEnvelope;
  if (envelope.format !== BACKUP_FORMAT) {
    throw new Error('BACKUP_UNRECOGNIZED_FORMAT');
  }
  if (envelope.version !== BACKUP_VERSION) {
    throw new Error(`BACKUP_UNSUPPORTED_VERSION:${envelope.version}`);
  }
  const collections: Array<BackupCollectionRow> = Array.isArray(envelope.collections)
    ? envelope.collections
      .map((c: BackupCollectionRow) => sanitizeBackupCollectionRow(c))
      .filter((c: BackupCollectionRow) => c.id !== 0 && c.name.length > 0)
    : [];
  const tags: Array<BackupTagRow> = Array.isArray(envelope.tags)
    ? envelope.tags
      .map((t: BackupTagRow) => sanitizeBackupTagRow(t))
      .filter((t: BackupTagRow) => t.id !== 0 && t.name.length > 0)
    : [];
  const links: Array<BackupLinkRow> = Array.isArray(envelope.links)
    ? envelope.links
      .map((l: BackupLinkRow) => sanitizeBackupLinkRow(l))
      .filter((l: BackupLinkRow) => l.id !== 0 && l.url.length > 0)
    : [];
  return {
    format: BACKUP_FORMAT,
    version: BACKUP_VERSION,
    exportedAt: toStringOrEmpty(envelope.exportedAt),
    collections,
    tags,
    links,
  };
}

function sanitizeBackupCollectionRow(row: BackupCollectionRow): BackupCollectionRow {
  return {
    id: toIntegerOrZero(row.id),
    ownerId: toIntegerOrZero(row.ownerId),
    name: toStringOrEmpty(row.name).trim(),
    description: toStringOrEmpty(row.description),
    color: toStringOrEmpty(row.color),
    parentId: toIntegerOrZero(row.parentId),
  };
}

function sanitizeBackupTagRow(row: BackupTagRow): BackupTagRow {
  return {
    id: toIntegerOrZero(row.id),
    name: toStringOrEmpty(row.name).trim(),
  };
}

function sanitizeBackupLinkRow(row: BackupLinkRow): BackupLinkRow {
  return {
    id: toIntegerOrZero(row.id),
    name: toStringOrEmpty(row.name),
    url: toStringOrEmpty(row.url).trim(),
    description: toStringOrEmpty(row.description),
    createdAt: toStringOrEmpty(row.createdAt),
    collectionId: toIntegerOrZero(row.collectionId),
    pinned: row.pinned === true,
    tagIds: Array.isArray(row.tagIds)
      ? row.tagIds.map((id: number) => toIntegerOrZero(id)).filter((id: number) => id !== 0)
      : [],
  };
}
