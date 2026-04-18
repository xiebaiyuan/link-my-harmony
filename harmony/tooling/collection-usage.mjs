const SCORE_HALF_LIFE_MS = 7 * 24 * 60 * 60 * 1000;

export function createDefaultCollectionUsage() {
  return { entries: [] };
}

export function findCollectionUsageEntry(state, collectionId) {
  const entries = Array.isArray(state?.entries) ? state.entries : [];
  for (const entry of entries) {
    if (entry && entry.collectionId === collectionId) {
      return entry;
    }
  }
  return null;
}

export function recordCollectionView(state, collectionId, now) {
  const entries = Array.isArray(state?.entries) ? state.entries : [];
  const rest = entries.filter((entry) => entry.collectionId !== collectionId);
  const existing = findCollectionUsageEntry(state, collectionId);
  const nextCount = existing === null ? 1 : existing.viewCount + 1;
  return {
    entries: [
      { collectionId, viewCount: nextCount, lastViewedAt: now },
      ...rest,
    ],
  };
}

export function collectionUsageScore(entry, now) {
  if (entry === null || entry === undefined) {
    return 0;
  }
  const age = now - entry.lastViewedAt;
  if (age <= 0) {
    return entry.viewCount;
  }
  const decay = Math.pow(0.5, age / SCORE_HALF_LIFE_MS);
  return entry.viewCount * decay;
}

export function serializeCollectionUsage(state) {
  return JSON.stringify({ entries: Array.isArray(state?.entries) ? state.entries : [] });
}

export function parseCollectionUsage(raw) {
  if (typeof raw !== 'string' || raw.length === 0) {
    return createDefaultCollectionUsage();
  }
  try {
    const parsed = JSON.parse(raw);
    const rawEntries = parsed?.entries;
    if (!Array.isArray(rawEntries)) {
      return createDefaultCollectionUsage();
    }
    const sanitized = [];
    for (const candidate of rawEntries) {
      const collectionId = candidate?.collectionId;
      const viewCount = candidate?.viewCount;
      const lastViewedAt = candidate?.lastViewedAt;
      if (
        typeof collectionId === 'number'
        && typeof viewCount === 'number'
        && typeof lastViewedAt === 'number'
      ) {
        sanitized.push({
          collectionId,
          viewCount: viewCount < 0 ? 0 : viewCount,
          lastViewedAt: lastViewedAt < 0 ? 0 : lastViewedAt,
        });
      }
    }
    return { entries: sanitized };
  } catch (error) {
    return createDefaultCollectionUsage();
  }
}

export const COLLECTION_USAGE_SCORE_HALF_LIFE_MS = SCORE_HALF_LIFE_MS;
