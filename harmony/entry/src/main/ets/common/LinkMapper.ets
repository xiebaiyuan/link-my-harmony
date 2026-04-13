import type { LinkItem, PagedLinks, LinkTag, CollectionItem } from './Models';

export interface LinkOwnerPayload {
  id?: number;
}

export interface LinkCollectionPayload {
  id?: number;
  ownerId?: number;
  owner?: LinkOwnerPayload;
  name?: string;
  color?: string;
}

export interface LinkTagPayload {
  id?: number;
  name?: string;
}

export interface LinkPinnedPayload {
  id?: number;
}

export interface LinkPayload {
  id?: number;
  name?: string;
  url?: string;
  description?: string;
  createdAt?: string;
  collection?: LinkCollectionPayload;
  tags?: Array<LinkTagPayload>;
  pinnedBy?: Array<LinkPinnedPayload>;
}

export interface SearchResponseBody {
  links: Array<LinkPayload>;
  nextCursor?: number;
}

export interface SearchResponse {
  data: SearchResponseBody;
}

export interface LinkDetailResponse {
  response: LinkPayload;
}

export interface CollectionCountPayload {
  links?: number;
}

export interface CollectionParentPayload {
  name?: string;
}

export interface CollectionPayload {
  id?: number;
  ownerId?: number;
  name?: string;
  description?: string;
  color?: string;
  parentId?: number;
  _count?: CollectionCountPayload;
  parent?: CollectionParentPayload;
}

export interface CollectionsResponse {
  response: Array<CollectionPayload>;
}

function stringOrEmpty(value: string | undefined): string {
  return typeof value === 'string' ? value : '';
}

function numberOrZero(value: number | undefined): number {
  return typeof value === 'number' ? value : 0;
}

function parseNumberOrZero(value: number | string | undefined): number {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : 0;
  }

  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  return 0;
}

function mapTagPayload(payload: LinkTagPayload): LinkTag {
  const tag: LinkTag = {
    id: parseNumberOrZero(payload.id),
    name: stringOrEmpty(payload.name),
  };

  return tag;
}

export function mapLinkPayload(payload: LinkPayload): LinkItem {
  const collection = payload.collection;
  const rawTags = payload.tags ?? [];
  const tags: Array<LinkTag> = rawTags.map((tag) => mapTagPayload(tag));
  const collectionOwnerId = parseNumberOrZero(collection?.ownerId) > 0
    ? parseNumberOrZero(collection?.ownerId)
    : parseNumberOrZero(collection?.owner?.id);

  const link: LinkItem = {
    id: parseNumberOrZero(payload.id),
    name: stringOrEmpty(payload.name),
    url: stringOrEmpty(payload.url),
    description: stringOrEmpty(payload.description),
    createdAt: stringOrEmpty(payload.createdAt),
    collectionId: parseNumberOrZero(collection?.id),
    collectionOwnerId,
    collectionName: stringOrEmpty(collection?.name),
    collectionColor: stringOrEmpty(collection?.color),
    pinned: Array.isArray(payload.pinnedBy) && payload.pinnedBy.length > 0,
    tags,
  };

  return link;
}

export function mapPagedLinksResponse(response: SearchResponse): PagedLinks {
  const links: Array<LinkItem> = response.data.links.map((item: LinkPayload) => mapLinkPayload(item));
  const nextCursorValue = response.data.nextCursor;
  const nextCursor = typeof nextCursorValue === 'number' ? nextCursorValue : -1;

  const paged: PagedLinks = {
    links,
    nextCursor,
  };

  return paged;
}

export function mapLinkDetailResponse(response: LinkDetailResponse): LinkItem {
  return mapLinkPayload(response.response);
}

export function mapCollectionPayload(payload: CollectionPayload): CollectionItem {
  return {
    id: parseNumberOrZero(payload.id),
    ownerId: parseNumberOrZero(payload.ownerId),
    name: stringOrEmpty(payload.name),
    description: stringOrEmpty(payload.description),
    color: stringOrEmpty(payload.color),
    parentId: parseNumberOrZero(payload.parentId),
    parentName: stringOrEmpty(payload.parent?.name),
    linkCount: parseNumberOrZero(payload._count?.links),
  };
}

export function mapCollectionsResponse(response: CollectionsResponse): Array<CollectionItem> {
  if (!Array.isArray(response.response)) {
    return [];
  }

  return response.response.map((item: CollectionPayload) => mapCollectionPayload(item));
}
