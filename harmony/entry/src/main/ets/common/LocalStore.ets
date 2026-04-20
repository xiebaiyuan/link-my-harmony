// Shared types and constants for the local/offline bookmark store.
//
// Logic (CRUD, search, pagination, backup, merge planner) has a pure-JS
// twin under `harmony/tooling/local-store.mjs` + `local-backup.mjs` +
// `merge-planner.mjs` that is covered by node --test. The ArkTS side
// (services/LocalDatabase.ets) implements the same semantics on top of
// `@ohos.data.relationalStore` (SQLite).

import type { LinkItem, LinkTag, CollectionItem } from './Models';

export const LOCAL_DB_NAME: string = 'folio_local.db';
export const LOCAL_DB_VERSION: number = 1;

export const BACKUP_FORMAT: string = 'folio-backup';
export const BACKUP_VERSION: number = 1;

// Filter shape accepted by LocalDatabase.listLinks — mirrors the pure-JS
// filter. Every field is optional; a caller supplies only what it needs.
export interface LocalLinkFilter {
  cursor?: number;
  searchQueryString?: string;
  collectionId?: number;
  pinnedOnly?: boolean;
  tagId?: number;
  limit?: number;
}

export interface LocalLinkDraft {
  name?: string;
  url: string;
  description?: string;
  createdAt?: string;
  collectionId?: number;
  pinned?: boolean;
  tags?: Array<LocalLinkDraftTag>;
}

export interface LocalLinkDraftTag {
  name: string;
}

export interface LocalLinkPatch {
  name?: string;
  url?: string;
  description?: string;
  collectionId?: number;
  pinned?: boolean;
  tags?: Array<LocalLinkDraftTag>;
}

export interface LocalCollectionDraft {
  name: string;
  ownerId?: number;
  description?: string;
  color?: string;
  parentId?: number;
}

export interface LocalCollectionPatch {
  name?: string;
  ownerId?: number;
  description?: string;
  color?: string;
  parentId?: number;
}

// Backup envelope types — kept flat to match `folio-backup` JSON on disk.
export interface BackupEnvelope {
  format: string;
  version: number;
  exportedAt: string;
  collections: Array<BackupCollectionRow>;
  tags: Array<BackupTagRow>;
  links: Array<BackupLinkRow>;
}

export interface BackupLinkRow {
  id: number;
  name: string;
  url: string;
  description: string;
  createdAt: string;
  collectionId: number;
  pinned: boolean;
  tagIds: Array<number>;
}

export interface BackupCollectionRow {
  id: number;
  ownerId: number;
  name: string;
  description: string;
  color: string;
  parentId: number;
}

export interface BackupTagRow {
  id: number;
  name: string;
}

export type ImportStrategy = 'replace' | 'merge';

export interface ImportSummary {
  linksImported: number;
  linksSkipped: number;
  collectionsImported: number;
  collectionsReused: number;
  tagsImported: number;
  tagsReused: number;
}

// Re-exported so callers that only need the offline types can import from a
// single module without reaching into common/Models.
export type { LinkItem, LinkTag, CollectionItem };

// ---------------------------------------------------------------------------
// Pure helpers reused by LocalDatabase. Keeping them here (not in a class)
// makes them trivially testable in isolation if we later mirror them under
// tooling/*.mjs, and keeps LocalDatabase focused on persistence.
// ---------------------------------------------------------------------------

/** Returns the next available local (negative) id given the current ids. */
export function nextLocalId(existingIds: Array<number>): number {
  let minId: number = 0;
  for (let i: number = 0; i < existingIds.length; i++) {
    const id: number = existingIds[i];
    if (Number.isFinite(id) && id < minId) {
      minId = id;
    }
  }
  return minId - 1;
}

/** Normalizes + dedupes tag names supplied by a link draft. */
export function normalizeTagNames(tags: Array<LocalLinkDraftTag> | undefined): Array<string> {
  if (!Array.isArray(tags)) {
    return [];
  }
  const seen: Array<string> = [];
  for (let i: number = 0; i < tags.length; i++) {
    const entry: LocalLinkDraftTag = tags[i];
    const rawName: string = typeof entry.name === 'string' ? entry.name : '';
    const trimmed: string = rawName.trim();
    if (trimmed.length === 0) {
      continue;
    }
    if (seen.indexOf(trimmed) === -1) {
      seen.push(trimmed);
    }
  }
  return seen;
}

/** Strict int32-or-zero coercion for column bindings. */
export function toIntegerOrZero(value: number | string | undefined | null): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === 'string') {
    const parsed: number = Number(value);
    return Number.isFinite(parsed) ? Math.trunc(parsed) : 0;
  }
  return 0;
}

/** Strict string-or-empty coercion for column bindings. */
export function toStringOrEmpty(value: string | undefined | null): string {
  return typeof value === 'string' ? value : '';
}
