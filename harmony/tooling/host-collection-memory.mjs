const SCORE_HALF_LIFE_MS = 7 * 24 * 60 * 60 * 1000;

const URL_PATTERN = /https?:\/\/[^\s]+/i;
const URL_TRAILING_NOISE_PATTERN = /["'\]\[\)\(\}\{>,.;!?]+$/;

export function extractHostname(raw) {
  if (typeof raw !== 'string') {
    return '';
  }
  const trimmed = raw.trim();
  if (trimmed.length === 0) {
    return '';
  }
  const matched = trimmed.match(URL_PATTERN);
  if (!matched || !matched[0]) {
    return '';
  }
  const cleaned = matched[0].replace(URL_TRAILING_NOISE_PATTERN, '');
  const afterScheme = cleaned.slice(cleaned.indexOf('://') + 3);
  const endIndex = findFirstIndex(afterScheme, ['/', '?', '#']);
  const authority = endIndex >= 0 ? afterScheme.slice(0, endIndex) : afterScheme;
  const hostWithPort = authority.includes('@') ? authority.slice(authority.indexOf('@') + 1) : authority;
  const portIndex = hostWithPort.indexOf(':');
  const host = portIndex >= 0 ? hostWithPort.slice(0, portIndex) : hostWithPort;
  const lower = host.toLowerCase();
  if (lower.length === 0) {
    return '';
  }
  return lower.startsWith('www.') ? lower.slice(4) : lower;
}

function findFirstIndex(text, candidates) {
  let best = -1;
  for (const c of candidates) {
    const idx = text.indexOf(c);
    if (idx >= 0 && (best < 0 || idx < best)) {
      best = idx;
    }
  }
  return best;
}

export function createDefaultHostCollectionMemory() {
  return { entries: [] };
}

export function findHostCollectionEntry(state, host, collectionId) {
  const entries = Array.isArray(state?.entries) ? state.entries : [];
  for (const entry of entries) {
    if (entry && entry.host === host && entry.collectionId === collectionId) {
      return entry;
    }
  }
  return null;
}

export function recordHostChoice(state, hostOrUrl, collectionId, now) {
  const host = extractHostname(hostOrUrl) || (typeof hostOrUrl === 'string' ? hostOrUrl.trim().toLowerCase() : '');
  if (host.length === 0 || typeof collectionId !== 'number' || collectionId <= 0) {
    return state ?? createDefaultHostCollectionMemory();
  }
  const entries = Array.isArray(state?.entries) ? state.entries : [];
  const existing = findHostCollectionEntry(state, host, collectionId);
  const rest = entries.filter((entry) => !(entry.host === host && entry.collectionId === collectionId));
  const nextCount = existing === null ? 1 : existing.count + 1;
  return {
    entries: [
      { host, collectionId, count: nextCount, lastUsedAt: now },
      ...rest,
    ],
  };
}

export function hostCollectionScore(entry, now) {
  if (entry === null || entry === undefined) {
    return 0;
  }
  const age = now - entry.lastUsedAt;
  if (age <= 0) {
    return entry.count;
  }
  const decay = Math.pow(0.5, age / SCORE_HALF_LIFE_MS);
  return entry.count * decay;
}

export function pickBestCollectionForHost(state, hostOrUrl, now) {
  const host = extractHostname(hostOrUrl) || (typeof hostOrUrl === 'string' ? hostOrUrl.trim().toLowerCase() : '');
  if (host.length === 0) {
    return 0;
  }
  const entries = Array.isArray(state?.entries) ? state.entries : [];
  let bestId = 0;
  let bestScore = 0;
  for (const entry of entries) {
    if (!entry || entry.host !== host) continue;
    const score = hostCollectionScore(entry, now);
    if (score > bestScore) {
      bestScore = score;
      bestId = entry.collectionId;
    }
  }
  return bestId;
}

export function serializeHostCollectionMemory(state) {
  return JSON.stringify({ entries: Array.isArray(state?.entries) ? state.entries : [] });
}

export function parseHostCollectionMemory(raw) {
  if (typeof raw !== 'string' || raw.length === 0) {
    return createDefaultHostCollectionMemory();
  }
  try {
    const parsed = JSON.parse(raw);
    const rawEntries = parsed?.entries;
    if (!Array.isArray(rawEntries)) {
      return createDefaultHostCollectionMemory();
    }
    const sanitized = [];
    for (const candidate of rawEntries) {
      const host = candidate?.host;
      const collectionId = candidate?.collectionId;
      const count = candidate?.count;
      const lastUsedAt = candidate?.lastUsedAt;
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

export const HOST_COLLECTION_SCORE_HALF_LIFE_MS = SCORE_HALF_LIFE_MS;
