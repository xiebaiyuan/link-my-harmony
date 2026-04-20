// Runs a one-way "local → server" merge: walks the LocalDatabase, creates
// collections + links on the Linkwarden server for every row whose id is
// still negative (local-only), reuses existing server entities by name,
// and skips server-side duplicates by (collectionId, url).
//
// The algorithm matches `harmony/tooling/merge-planner.mjs` — that module
// and its 14 tests document the semantics; this class is the online
// execution counterpart. Local data is NOT touched (neither deleted nor
// id-rewritten): the caller decides whether to keep it as archive or wipe
// it via LocalDatabase.clear() afterwards.

import type { CollectionItem, LinkItem, PagedLinks, LinkTag } from '../common/Models';
import type { CreateCollectionOptions, LinkwardenApi } from './LinkwardenApi';
import type { LocalDatabase } from './LocalDatabase';

const SERVER_FETCH_PAGE_GUARD: number = 500;
const LOCAL_FETCH_PAGE_SIZE: number = 200;
const LOCAL_FETCH_PAGE_GUARD: number = 500;
const MERGE_ERRORS_KEPT: number = 10;

export interface MergeSummary {
  collectionsCreated: number;
  collectionsReused: number;
  collectionsFailed: number;
  linksCreated: number;
  linksSkipped: number;
  linksFailed: number;
  errors: Array<string>;
}

export type MergeProgressPhase = 'preparing' | 'collections' | 'links' | 'done';

export interface MergeProgress {
  phase: MergeProgressPhase;
  current: number;
  total: number;
}

export type MergeProgressCallback = (progress: MergeProgress) => void;

function createEmptySummary(): MergeSummary {
  return {
    collectionsCreated: 0,
    collectionsReused: 0,
    collectionsFailed: 0,
    linksCreated: 0,
    linksSkipped: 0,
    linksFailed: 0,
    errors: [],
  };
}

function serverLinkKey(collectionId: number, url: string): string {
  return `${collectionId}::${url}`;
}

function minimalCollectionArg(
  collectionId: number,
  ownerId: number,
  servers: Array<CollectionItem>,
): CollectionItem | null {
  if (collectionId <= 0) {
    return null;
  }
  for (let i: number = 0; i < servers.length; i++) {
    if (servers[i].id === collectionId) {
      return servers[i];
    }
  }
  if (ownerId <= 0) {
    return null;
  }
  const placeholder: CollectionItem = {
    id: collectionId,
    ownerId,
    name: '',
    description: '',
    color: '',
    parentId: 0,
    parentName: '',
    linkCount: 0,
  };
  return placeholder;
}

export class MergeRunner {
  private local: LocalDatabase;
  private api: LinkwardenApi;

  constructor(local: LocalDatabase, api: LinkwardenApi) {
    this.local = local;
    this.api = api;
  }

  async run(onProgress?: MergeProgressCallback): Promise<MergeSummary> {
    const summary: MergeSummary = createEmptySummary();
    const report = (phase: MergeProgressPhase, current: number, total: number): void => {
      if (onProgress !== undefined) {
        onProgress({ phase, current, total });
      }
    };
    report('preparing', 0, 0);

    // 1. Server state snapshot (collections + (collectionId, url) dedup set).
    const serverCollections: Array<CollectionItem> = await this.api.fetchCollections();
    const collectionByName: Map<string, CollectionItem> = new Map();
    for (let i: number = 0; i < serverCollections.length; i++) {
      collectionByName.set(serverCollections[i].name, serverCollections[i]);
    }
    const serverLinkIndex: Set<string> = new Set();
    let serverCursor: number = 0;
    for (let guard: number = 0; guard < SERVER_FETCH_PAGE_GUARD; guard++) {
      const page: PagedLinks = await this.api.fetchLinks(serverCursor, '', 0, false);
      for (let i: number = 0; i < page.links.length; i++) {
        const l: LinkItem = page.links[i];
        serverLinkIndex.add(serverLinkKey(l.collectionId, l.url));
      }
      if (page.nextCursor < 0 || page.links.length === 0) {
        break;
      }
      serverCursor = page.nextCursor;
    }

    // 2. All local rows.
    const localCollections: Array<CollectionItem> = await this.local.listCollections();
    const localLinks: Array<LinkItem> = [];
    let localCursor: number = 0;
    for (let guard: number = 0; guard < LOCAL_FETCH_PAGE_GUARD; guard++) {
      const page: PagedLinks = await this.local.listLinks({
        cursor: localCursor,
        limit: LOCAL_FETCH_PAGE_SIZE,
      });
      for (let i: number = 0; i < page.links.length; i++) {
        localLinks.push(page.links[i]);
      }
      if (page.nextCursor < 0 || page.links.length === 0) {
        break;
      }
      localCursor = page.nextCursor;
    }

    // 3. Collections: reuse by name or create. Build localId -> serverId map.
    const collectionIdMap: Map<number, number> = new Map();
    const collectionOwnerByServerId: Map<number, number> = new Map();
    for (let i: number = 0; i < serverCollections.length; i++) {
      collectionOwnerByServerId.set(serverCollections[i].id, serverCollections[i].ownerId);
    }

    const pendingLocalCollections: Array<CollectionItem> = localCollections.filter(
      (c: CollectionItem) => c.id <= 0,
    );
    let processedCollections: number = 0;
    for (let i: number = 0; i < localCollections.length; i++) {
      const c: CollectionItem = localCollections[i];
      if (c.id > 0) {
        collectionIdMap.set(c.id, c.id);
        continue;
      }
      processedCollections += 1;
      report('collections', processedCollections, pendingLocalCollections.length);
      const match: CollectionItem | undefined = collectionByName.get(c.name);
      if (match !== undefined) {
        collectionIdMap.set(c.id, match.id);
        summary.collectionsReused += 1;
        continue;
      }
      try {
        const mappedParentId: number = collectionIdMap.get(c.parentId) ?? 0;
        const opts: CreateCollectionOptions = {};
        if (c.description.length > 0) {
          opts.description = c.description;
        }
        if (c.color.length > 0) {
          opts.color = c.color;
        }
        if (mappedParentId > 0) {
          opts.parentId = mappedParentId;
        }
        const created: CollectionItem = await this.api.createCollection(c.name, opts);
        collectionIdMap.set(c.id, created.id);
        collectionByName.set(created.name, created);
        serverCollections.push(created);
        collectionOwnerByServerId.set(created.id, created.ownerId);
        summary.collectionsCreated += 1;
      } catch (error) {
        summary.collectionsFailed += 1;
        if (summary.errors.length < MERGE_ERRORS_KEPT) {
          summary.errors.push(`collection "${c.name}": ${String(error)}`);
        }
      }
    }

    // 4. Links: dedup by (mappedCollectionId, url), then upload.
    const pendingLocalLinks: Array<LinkItem> = localLinks.filter((l: LinkItem) => l.id <= 0);
    let processedLinks: number = 0;
    for (let i: number = 0; i < localLinks.length; i++) {
      const l: LinkItem = localLinks[i];
      if (l.id > 0) {
        continue; // already synced
      }
      processedLinks += 1;
      report('links', processedLinks, pendingLocalLinks.length);
      const mappedCollectionId: number = collectionIdMap.get(l.collectionId) ?? 0;
      if (l.collectionId !== 0 && mappedCollectionId === 0) {
        summary.linksFailed += 1;
        if (summary.errors.length < MERGE_ERRORS_KEPT) {
          summary.errors.push(`link "${l.url}": parent collection did not sync`);
        }
        continue;
      }
      const key: string = serverLinkKey(mappedCollectionId, l.url);
      if (serverLinkIndex.has(key)) {
        summary.linksSkipped += 1;
        continue;
      }
      try {
        const ownerId: number = collectionOwnerByServerId.get(mappedCollectionId) ?? 0;
        const colArg: CollectionItem | null = minimalCollectionArg(
          mappedCollectionId, ownerId, serverCollections,
        );
        const tagNames: Array<string> = l.tags.map((t: LinkTag) => t.name);
        await this.api.addLink(l.url, l.name, {
          tagNames,
          collection: colArg,
        });
        serverLinkIndex.add(key);
        summary.linksCreated += 1;
      } catch (error) {
        summary.linksFailed += 1;
        if (summary.errors.length < MERGE_ERRORS_KEPT) {
          summary.errors.push(`link "${l.url}": ${String(error)}`);
        }
      }
    }

    report('done', pendingLocalLinks.length, pendingLocalLinks.length);
    return summary;
  }
}
