export interface HostCollectionEntry {
  host: string;
  collectionId: number;
  count: number;
  lastUsedAt: number;
}

export interface HostCollectionMemoryState {
  entries: Array<HostCollectionEntry>;
}

interface HostCollectionMemoryPayload {
  entries?: Array<HostCollectionEntryPayload>;
}

interface HostCollectionEntryPayload {
  host?: string;
  collectionId?: number;
  count?: number;
  lastUsedAt?: number;
}

const SCORE_HALF_LIFE_MS: number = 7 * 24 * 60 * 60 * 1000;
const URL_PATTERN: RegExp = /https?:\/\/[^\s]+/i;
const URL_TRAILING_NOISE_PATTERN: RegExp = /["'\]\[\)\(\}\{>,.;!?]+$/;

export function extractHostname(raw: string): string {
  const trimmed: string = raw.trim();
  if (trimmed.length === 0) {
    return '';
  }
  const matched = trimmed.match(URL_PATTERN);
  if (matched === null || matched.length === 0) {
    return '';
  }
  const cleaned: string = matched[0].replace(URL_TRAILING_NOISE_PATTERN, '');
  const schemeIndex: number = cleaned.indexOf('://');
  if (schemeIndex < 0) {
    return '';
  }
  const afterScheme: string = cleaned.slice(schemeIndex + 3);
  const endIndex: number = findFirstIndex(afterScheme, ['/', '?', '#']);
  const authority: string = endIndex >= 0 ? afterScheme.slice(0, endIndex) : afterScheme;
  const atIndex: number = authority.indexOf('@');
  const hostWithPort: string = atIndex >= 0 ? authority.slice(atIndex + 1) : authority;
  const portIndex: number = hostWithPort.indexOf(':');
  const host: string = portIndex >= 0 ? hostWithPort.slice(0, portIndex) : hostWithPort;
  const lower: string = host.toLowerCase();
  if (lower.length === 0) {
    return '';
  }
  return lower.startsWith('www.') ? lower.slice(4) : lower;
}

function findFirstIndex(text: string, candidates: Array<string>): number {
  let best: number = -1;
  for (let i: number = 0; i < candidates.length; i++) {
    const idx: number = text.indexOf(candidates[i]);
    if (idx >= 0 && (best < 0 || idx < best)) {
      best = idx;
    }
  }
  return best;
}

export function createDefaultHostCollectionMemory(): HostCollectionMemoryState {
  return { entries: [] };
}

export function findHostCollectionEntry(
  state: HostCollectionMemoryState,
  host: string,
  collectionId: number,
): HostCollectionEntry | null {
  for (let i: number = 0; i < state.entries.length; i++) {
    const entry = state.entries[i];
    if (entry.host === host && entry.collectionId === collectionId) {
      return entry;
    }
  }
  return null;
}

export function recordHostChoice(
  state: HostCollectionMemoryState,
  hostOrUrl: string,
  collectionId: number,
  now: number,
): HostCollectionMemoryState {
  const host: string = extractHostname(hostOrUrl);
  if (host.length === 0 || collectionId <= 0) {
    return state;
  }
  const existing: HostCollectionEntry | null = findHostCollectionEntry(state, host, collectionId);
  const rest: Array<HostCollectionEntry> = state.entries.filter(
    (entry: HostCollectionEntry) => !(entry.host === host && entry.collectionId === collectionId),
  );
  const nextCount: number = existing === null ? 1 : existing.count + 1;
  const nextEntry: HostCollectionEntry = {
    host,
    collectionId,
    count: nextCount,
    lastUsedAt: now,
  };
  return { entries: [nextEntry].concat(rest) };
}

export function hostCollectionScore(
  entry: HostCollectionEntry | null,
  now: number,
): number {
  if (entry === null) {
    return 0;
  }
  const age: number = now - entry.lastUsedAt;
  if (age <= 0) {
    return entry.count;
  }
  const decay: number = Math.pow(0.5, age / SCORE_HALF_LIFE_MS);
  return entry.count * decay;
}

export function pickBestCollectionForHost(
  state: HostCollectionMemoryState,
  hostOrUrl: string,
  now: number,
): number {
  const host: string = extractHostname(hostOrUrl);
  if (host.length === 0) {
    return 0;
  }
  let bestId: number = 0;
  let bestScore: number = 0;
  for (let i: number = 0; i < state.entries.length; i++) {
    const entry = state.entries[i];
    if (entry.host !== host) {
      continue;
    }
    const score: number = hostCollectionScore(entry, now);
    if (score > bestScore) {
      bestScore = score;
      bestId = entry.collectionId;
    }
  }
  return bestId;
}

export function serializeHostCollectionMemory(state: HostCollectionMemoryState): string {
  return JSON.stringify({ entries: state.entries });
}

export function parseHostCollectionMemory(raw: string): HostCollectionMemoryState {
  if (raw.length === 0) {
    return createDefaultHostCollectionMemory();
  }

  try {
    const parsed = JSON.parse(raw) as HostCollectionMemoryPayload;
    const rawEntries = parsed.entries;

    if (!Array.isArray(rawEntries)) {
      return createDefaultHostCollectionMemory();
    }

    const sanitized: Array<HostCollectionEntry> = [];
    for (let i: number = 0; i < rawEntries.length; i++) {
      const candidate: HostCollectionEntryPayload = rawEntries[i];
      const host = candidate.host;
      const collectionId = candidate.collectionId;
      const count = candidate.count;
      const lastUsedAt = candidate.lastUsedAt;
      if (
        typeof host === 'string'
        && host.length > 0
        && typeof collectionId === 'number'
        && typeof count === 'number'
        && typeof lastUsedAt === 'number'
      ) {
        sanitized.push({
          host,
          collectionId,
          count: count < 0 ? 0 : count,
          lastUsedAt: lastUsedAt < 0 ? 0 : lastUsedAt,
        });
      }
    }

    return { entries: sanitized };
  } catch (error) {
    return createDefaultHostCollectionMemory();
  }
}
