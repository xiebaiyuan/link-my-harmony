// Unified façade that dispatches bookmark operations to either the
// Linkwarden server (LinkwardenApi) or the local SQLite store
// (LocalDatabase), depending on the current SessionMode.
//
// Method surface mirrors LinkwardenApi so that callers (pages/Index.ets)
// can switch from `this.api` to `this.service` with near-zero call-site
// changes. Online-only methods (`signIn`, `fetchCurrentUserId`) proxy
// straight through — offline callers must not invoke them.
//
// Construction is a two-step dance because LocalDatabase needs a Context:
//   1. Field init:    `new BookmarkService(instance, token, mode)`
//   2. aboutToAppear: `await service.attachContext(getContext(this))`
// This keeps the field default cheap and defers DB I/O to the lifecycle
// hook, matching how SessionStorage is already wired in Index.ets.

import { LinkwardenApi } from './LinkwardenApi';
import type { AddLinkOptions, CreateCollectionOptions, DashboardTotals } from './LinkwardenApi';
import { LocalDatabase } from './LocalDatabase';
import type { LinkItem, LinkTag, CollectionItem, PagedLinks } from '../common/Models';
import type { SessionMode } from '../common/SessionState';
import type { ImportStrategy, ImportSummary, LocalLinkDraftTag } from '../common/LocalStore';

const OFFLINE_DASHBOARD_LIMIT: number = 50;
const OFFLINE_PINNED_LIMIT: number = 200;
const OFFLINE_TOTALS_SCAN_LIMIT: number = 10000;

export class BookmarkService {
  private api: LinkwardenApi;
  private local: LocalDatabase | null = null;
  private mode: SessionMode;

  constructor(instance: string, token: string, mode: SessionMode) {
    this.api = new LinkwardenApi(instance, token);
    this.mode = mode;
  }

  // Lifecycle -------------------------------------------------------------

  async attachContext(context: Context): Promise<void> {
    if (this.local !== null) {
      return;
    }
    this.local = new LocalDatabase(context);
    await this.local.init();
  }

  getMode(): SessionMode {
    return this.mode;
  }

  setMode(mode: SessionMode): void {
    this.mode = mode;
  }

  setInstance(instance: string): void {
    this.api.setInstance(instance);
  }

  setToken(token: string): void {
    this.api.setToken(token);
  }

  isOffline(): boolean {
    return this.mode === 'offline';
  }

  // Escape hatches for features that are bound to a specific backend
  // (e.g. P3 merge-on-login uses `onlineClient` + `localDatabase` together).
  onlineClient(): LinkwardenApi {
    return this.api;
  }

  localDatabase(): LocalDatabase {
    return this.requireLocal();
  }

  private requireLocal(): LocalDatabase {
    if (this.local === null) {
      throw new Error('LOCAL_DB_NOT_ATTACHED');
    }
    return this.local;
  }

  // Online-only -----------------------------------------------------------

  async signIn(username: string, password: string): Promise<string> {
    return await this.api.signIn(username, password);
  }

  async fetchCurrentUserId(): Promise<number> {
    return await this.api.fetchCurrentUserId();
  }

  // Links -----------------------------------------------------------------

  async fetchLinks(
    cursor: number,
    searchQueryString: string = '',
    collectionId: number = 0,
    pinnedOnly: boolean = false,
  ): Promise<PagedLinks> {
    if (this.mode === 'offline') {
      return await this.requireLocal().listLinks({
        cursor,
        searchQueryString,
        collectionId,
        pinnedOnly,
      });
    }
    return await this.api.fetchLinks(cursor, searchQueryString, collectionId, pinnedOnly);
  }

  async fetchDashboardLinks(): Promise<Array<LinkItem>> {
    if (this.mode === 'offline') {
      const page: PagedLinks = await this.requireLocal().listLinks({ limit: OFFLINE_DASHBOARD_LIMIT });
      return page.links;
    }
    return await this.api.fetchDashboardLinks();
  }

  async fetchPinnedLinks(): Promise<Array<LinkItem>> {
    if (this.mode === 'offline') {
      const page: PagedLinks = await this.requireLocal().listLinks({
        pinnedOnly: true,
        limit: OFFLINE_PINNED_LIMIT,
      });
      return page.links;
    }
    return await this.api.fetchPinnedLinks();
  }

  async fetchDashboardTotals(): Promise<DashboardTotals> {
    if (this.mode === 'offline') {
      const local: LocalDatabase = this.requireLocal();
      const pinned: PagedLinks = await local.listLinks({
        pinnedOnly: true,
        limit: OFFLINE_TOTALS_SCAN_LIMIT,
      });
      const tags: Array<LinkTag> = await local.listTags();
      const totals: DashboardTotals = {
        numberOfPinnedLinks: pinned.links.length,
        numberOfTags: tags.length,
      };
      return totals;
    }
    return await this.api.fetchDashboardTotals();
  }

  async getLink(id: number): Promise<LinkItem> {
    if (this.mode === 'offline') {
      const link: LinkItem | null = await this.requireLocal().getLinkById(id);
      if (link === null) {
        throw new Error(`LINK_NOT_FOUND:${id}`);
      }
      return link;
    }
    return await this.api.getLink(id);
  }

  async addLink(url: string, name: string = '', options?: AddLinkOptions): Promise<LinkItem> {
    if (this.mode === 'offline') {
      const rawTagNames: Array<string> | undefined = options?.tagNames;
      const tagNames: Array<string> = Array.isArray(rawTagNames) ? rawTagNames : [];
      const collection: CollectionItem | null | undefined = options?.collection;
      const collectionId: number = collection !== null && collection !== undefined ? collection.id : 0;
      const tagDrafts: Array<LocalLinkDraftTag> = tagNames.map((n: string) => {
        const entry: LocalLinkDraftTag = { name: n };
        return entry;
      });
      return await this.requireLocal().addLink({
        url,
        name,
        collectionId,
        tags: tagDrafts,
      });
    }
    return await this.api.addLink(url, name, options);
  }

  async updateLink(link: LinkItem): Promise<LinkItem> {
    if (this.mode === 'offline') {
      const tagDrafts: Array<LocalLinkDraftTag> = link.tags.map((t: LinkTag) => {
        const entry: LocalLinkDraftTag = { name: t.name };
        return entry;
      });
      return await this.requireLocal().updateLink(link.id, {
        name: link.name,
        url: link.url,
        description: link.description,
        collectionId: link.collectionId,
        pinned: link.pinned,
        tags: tagDrafts,
      });
    }
    return await this.api.updateLink(link);
  }

  async deleteLink(id: number): Promise<void> {
    if (this.mode === 'offline') {
      await this.requireLocal().deleteLink(id);
      return;
    }
    await this.api.deleteLink(id);
  }

  async setPinned(link: LinkItem, pinned: boolean, userId: number): Promise<LinkItem> {
    if (this.mode === 'offline') {
      return await this.requireLocal().setLinkPinned(link.id, pinned);
    }
    return await this.api.setPinned(link, pinned, userId);
  }

  // Collections -----------------------------------------------------------

  async fetchCollections(): Promise<Array<CollectionItem>> {
    if (this.mode === 'offline') {
      return await this.requireLocal().listCollections();
    }
    return await this.api.fetchCollections();
  }

  async createCollection(name: string, options?: CreateCollectionOptions): Promise<CollectionItem> {
    if (this.mode === 'offline') {
      const description: string = typeof options?.description === 'string' ? options.description : '';
      const color: string = typeof options?.color === 'string' ? options.color : '';
      const parentId: number = typeof options?.parentId === 'number' ? options.parentId : 0;
      return await this.requireLocal().addCollection({
        name,
        description,
        color,
        parentId,
      });
    }
    return await this.api.createCollection(name, options);
  }

  // Tags ------------------------------------------------------------------

  async fetchTags(): Promise<Array<LinkTag>> {
    if (this.mode === 'offline') {
      return await this.requireLocal().listTags();
    }
    return await this.api.fetchTags();
  }

  // Backup / local-data ---------------------------------------------------
  // Available regardless of mode — so an online user can still export or
  // seed a local backup from their current cloud session once they import
  // something, for example.

  async exportLocal(exportedAt?: string): Promise<string> {
    return await this.requireLocal().exportAll(exportedAt);
  }

  async importLocal(raw: string, strategy: ImportStrategy): Promise<ImportSummary> {
    return await this.requireLocal().importBackup(raw, strategy);
  }

  async clearLocal(): Promise<void> {
    await this.requireLocal().clear();
  }

  async hasLocalData(): Promise<boolean> {
    const local: LocalDatabase = this.requireLocal();
    const page: PagedLinks = await local.listLinks({ limit: 1 });
    if (page.links.length > 0) {
      return true;
    }
    const cols: Array<CollectionItem> = await local.listCollections();
    return cols.length > 0;
  }

  async countLocalLinks(): Promise<number> {
    const local: LocalDatabase = this.requireLocal();
    const page: PagedLinks = await local.listLinks({ limit: OFFLINE_TOTALS_SCAN_LIMIT });
    return page.links.length;
  }
}
