export interface CollectionUsageEntry {
  collectionId: number;
  viewCount: number;
  lastViewedAt: number;
}

export interface CollectionUsageState {
  entries: Array<CollectionUsageEntry>;
}

interface CollectionUsagePayload {
  entries?: Array<CollectionUsageEntryPayload>;
}

interface CollectionUsageEntryPayload {
  collectionId?: number;
  viewCount?: number;
  lastViewedAt?: number;
}

const SCORE_HALF_LIFE_MS: number = 7 * 24 * 60 * 60 * 1000;

export function createDefaultCollectionUsage(): CollectionUsageState {
  return { entries: [] };
}

export function findCollectionUsageEntry(
  state: CollectionUsageState,
  collectionId: number,
): CollectionUsageEntry | null {
  for (let i: number = 0; i < state.entries.length; i++) {
    if (state.entries[i].collectionId === collectionId) {
      return state.entries[i];
    }
  }
  return null;
}

export function recordCollectionView(
  state: CollectionUsageState,
  collectionId: number,
  now: number,
): CollectionUsageState {
  const rest: Array<CollectionUsageEntry> = state.entries.filter(
    (entry: CollectionUsageEntry) => entry.collectionId !== collectionId,
  );
  const existing: CollectionUsageEntry | null = findCollectionUsageEntry(state, collectionId);
  const nextCount: number = existing === null ? 1 : existing.viewCount + 1;
  const nextEntry: CollectionUsageEntry = {
    collectionId,
    viewCount: nextCount,
    lastViewedAt: now,
  };
  return { entries: [nextEntry].concat(rest) };
}

export function collectionUsageScore(
  entry: CollectionUsageEntry | null,
  now: number,
): number {
  if (entry === null) {
    return 0;
  }

  const age: number = now - entry.lastViewedAt;
  if (age <= 0) {
    return entry.viewCount;
  }

  const decay: number = Math.pow(0.5, age / SCORE_HALF_LIFE_MS);
  return entry.viewCount * decay;
}

export function serializeCollectionUsage(state: CollectionUsageState): string {
  return JSON.stringify({ entries: state.entries });
}

export function parseCollectionUsage(raw: string): CollectionUsageState {
  if (raw.length === 0) {
    return createDefaultCollectionUsage();
  }

  try {
    const parsed = JSON.parse(raw) as CollectionUsagePayload;
    const rawEntries = parsed.entries;

    if (!Array.isArray(rawEntries)) {
      return createDefaultCollectionUsage();
    }

    const sanitized: Array<CollectionUsageEntry> = [];
    for (let i: number = 0; i < rawEntries.length; i++) {
      const candidate: CollectionUsageEntryPayload = rawEntries[i];
      const collectionId = candidate.collectionId;
      const viewCount = candidate.viewCount;
      const lastViewedAt = candidate.lastViewedAt;
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
