function stringOrEmpty(value) {
  return typeof value === 'string' ? value : '';
}

function numberOrZero(value) {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : 0;
  }

  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  return 0;
}

function mapTagPayload(tag) {
  return {
    id: numberOrZero(tag?.id),
    name: stringOrEmpty(tag?.name),
  };
}

export function mapLinkPayload(payload) {
  const collection = payload?.collection ?? {};
  const ownerId = numberOrZero(collection?.ownerId) > 0
    ? numberOrZero(collection?.ownerId)
    : numberOrZero(collection?.owner?.id);
  const rawTags = Array.isArray(payload?.tags) ? payload.tags : [];

  return {
    id: numberOrZero(payload?.id),
    name: stringOrEmpty(payload?.name),
    url: stringOrEmpty(payload?.url),
    description: stringOrEmpty(payload?.description),
    createdAt: stringOrEmpty(payload?.createdAt),
    collectionId: numberOrZero(collection?.id),
    collectionOwnerId: ownerId,
    collectionName: stringOrEmpty(collection?.name),
    collectionColor: stringOrEmpty(collection?.color),
    pinned: Array.isArray(payload?.pinnedBy) && payload.pinnedBy.length > 0,
    tags: rawTags.map((tag) => mapTagPayload(tag)),
  };
}

export function mapPagedLinksResponse(payload) {
  const data = payload?.data ?? {};
  const rawLinks = Array.isArray(data?.links) ? data.links : [];

  return {
    links: rawLinks.map((item) => mapLinkPayload(item)),
    nextCursor: typeof data?.nextCursor === 'number' ? data.nextCursor : -1,
  };
}

export function mapLinkDetailResponse(payload) {
  return mapLinkPayload(payload?.response ?? {});
}

export function mapCollectionPayload(payload) {
  return {
    id: numberOrZero(payload?.id),
    ownerId: numberOrZero(payload?.ownerId),
    name: stringOrEmpty(payload?.name),
    description: stringOrEmpty(payload?.description),
    color: stringOrEmpty(payload?.color),
    parentId: numberOrZero(payload?.parentId),
    parentName: stringOrEmpty(payload?.parent?.name),
    linkCount: numberOrZero(payload?._count?.links),
  };
}

export function mapCollectionsResponse(payload) {
  const rawCollections = Array.isArray(payload?.response) ? payload.response : [];
  return rawCollections.map((item) => mapCollectionPayload(item));
}
