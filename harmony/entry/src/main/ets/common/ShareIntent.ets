import Want from '@ohos.app.ability.Want';

const URL_PATTERN: RegExp = /https?:\/\/[^\s]+/i;
const HOST_PATTERN: RegExp = /^([a-z0-9-]+\.)+[a-z]{2,}([/?#].*)?$/i;
const URL_TRAILING_NOISE_PATTERN: RegExp = /["'\]\[\)\(\}\{>,.;!?]+$/;
const SHARE_LOG_TAG: string = 'ShareIntent';

let pendingSharedUrl: string = '';
let pendingSharedTitle: string = '';

export interface PendingSharedIntent {
  url: string;
  title: string;
}

function readStringValue(value: Object | undefined): string {
  if (typeof value === 'string') {
    return value;
  }

  if (Array.isArray(value) && value.length > 0 && typeof value[0] === 'string') {
    return value[0];
  }

  return '';
}

function extractUrlFromUnknownValue(value: Object | undefined, allowHostFallback: boolean = false): string {
  const direct = readStringValue(value);
  const normalizedDirect = normalizeSharedUrl(direct, allowHostFallback);
  if (normalizedDirect.length > 0) {
    return normalizedDirect;
  }

  if (value === undefined || value === null) {
    return '';
  }

  if (Array.isArray(value)) {
    for (let i = 0; i < value.length; i += 1) {
      const normalizedItem = extractUrlFromUnknownValue(value[i], false);
      if (normalizedItem.length > 0) {
        return normalizedItem;
      }
    }
    return '';
  }

  if (typeof value === 'object') {
    const record = value as Record<string, Object>;
    const preferredKeys: Array<string> = ['uri', 'url', 'link', '2', '5'];
    for (let i = 0; i < preferredKeys.length; i += 1) {
      const key = preferredKeys[i];
      const normalizedPreferred = extractUrlFromUnknownValue(record[key], false);
      if (normalizedPreferred.length > 0) {
        return normalizedPreferred;
      }
    }

    const keys = Object.keys(record);
    for (let i = 0; i < keys.length; i += 1) {
      const key = keys[i];
      const normalizedNested = extractUrlFromUnknownValue(record[key], false);
      if (normalizedNested.length > 0) {
        return normalizedNested;
      }
    }
  }

  const fallback = normalizeSharedUrl(`${value}`, false);
  if (fallback.length > 0) {
    return fallback;
  }

  return '';
}

function normalizeSharedUrl(raw: string, allowHostFallback: boolean = true): string {
  const value = raw.trim();
  if (value.length === 0) {
    return '';
  }

  const matched = value.match(URL_PATTERN);
  if (matched && matched.length > 0) {
    return matched[0].replace(URL_TRAILING_NOISE_PATTERN, '');
  }

  if (allowHostFallback && HOST_PATTERN.test(value)) {
    return `https://${value}`;
  }

  return '';
}

function normalizeSharedTitle(raw: string): string {
  const value = raw.trim().replace(/\s+/g, ' ');
  if (value.length === 0) {
    return '';
  }

  if (normalizeSharedUrl(value).length > 0) {
    return '';
  }

  if (value.length > 200) {
    return value.slice(0, 200);
  }

  return value;
}

function extractTitleFromUnknownValue(value: Object | undefined): string {
  const direct = normalizeSharedTitle(readStringValue(value));
  if (direct.length > 0) {
    return direct;
  }

  if (value === undefined || value === null) {
    return '';
  }

  if (Array.isArray(value)) {
    for (let i = 0; i < value.length; i += 1) {
      const nested = extractTitleFromUnknownValue(value[i]);
      if (nested.length > 0) {
        return nested;
      }
    }
    return '';
  }

  if (typeof value === 'object') {
    const record = value as Record<string, Object>;
    const preferredKeys: Array<string> = ['title', 'name', 'subject', '4'];
    for (let i = 0; i < preferredKeys.length; i += 1) {
      const key = preferredKeys[i];
      const nested = extractTitleFromUnknownValue(record[key]);
      if (nested.length > 0) {
        return nested;
      }
    }

    const keys = Object.keys(record);
    for (let i = 0; i < keys.length; i += 1) {
      const key = keys[i];
      const nested = extractTitleFromUnknownValue(record[key]);
      if (nested.length > 0) {
        return nested;
      }
    }
  }

  return '';
}

export function extractSharedUrlFromWant(want: Want | undefined): string {
  if (!want) {
    console.info(`${SHARE_LOG_TAG}: want is empty`);
    return '';
  }

  const normalizedUri = normalizeSharedUrl(want.uri ?? '', true);
  if (normalizedUri.length > 0) {
    console.info(`${SHARE_LOG_TAG}: matched want.uri -> ${normalizedUri}`);
    return normalizedUri;
  }

  const parameters = want.parameters;
  const parameterKeys = parameters ? Object.keys(parameters) : [];
  console.info(`${SHARE_LOG_TAG}: action=${want.action ?? ''}, uri=${want.uri ?? ''}, parameterKeys=${JSON.stringify(parameterKeys)}`);
  const candidates: Array<string> = [
    'ohos.extra.param.key.shareUrl',
    'ohos.extra.param.key.shareAbstract',
    'ability.params.stream',
    'ability.params.streams',
    'ability.params.intent',
    'url',
    'URL',
    'link',
    'shareUrl',
    'text',
    'content',
    'android.intent.extra.TEXT',
  ];

  for (let i = 0; i < candidates.length; i += 1) {
    const key = candidates[i];
    const allowHostFallback = key === 'text' || key === 'content' || key === 'android.intent.extra.TEXT';
    const normalized = extractUrlFromUnknownValue(parameters?.[key], allowHostFallback);
    if (normalized.length > 0) {
      console.info(`${SHARE_LOG_TAG}: matched candidate key=${key} -> ${normalized}`);
      return normalized;
    }
  }

  if (parameters) {
    const keys = Object.keys(parameters);
    for (let i = 0; i < keys.length; i += 1) {
      const key = keys[i];
      const normalized = extractUrlFromUnknownValue(parameters[key]);
      if (normalized.length > 0) {
        console.info(`${SHARE_LOG_TAG}: matched fallback key=${key} -> ${normalized}`);
        return normalized;
      }
    }
  }

  console.info(`${SHARE_LOG_TAG}: no url extracted from want`);
  return '';
}

export function extractSharedTitleFromWant(want: Want | undefined): string {
  if (!want) {
    return '';
  }

  const parameters = want.parameters;
  const candidates: Array<string> = [
    'ohos.extra.param.key.shareAbstract',
    'title',
    'name',
    'subject',
    'android.intent.extra.SUBJECT',
    'ability.picker.records',
  ];

  for (let i = 0; i < candidates.length; i += 1) {
    const key = candidates[i];
    const title = extractTitleFromUnknownValue(parameters?.[key]);
    if (title.length > 0) {
      console.info(`${SHARE_LOG_TAG}: matched title key=${key} -> ${title}`);
      return title;
    }
  }

  return '';
}

export function captureSharedUrlFromWant(want: Want | undefined): string {
  const url = extractSharedUrlFromWant(want);
  const title = extractSharedTitleFromWant(want);
  if (url.length > 0) {
    pendingSharedUrl = url;
    pendingSharedTitle = title;
    console.info(`${SHARE_LOG_TAG}: captured pending url=${url}, title=${title}`);
  } else {
    console.info(`${SHARE_LOG_TAG}: capture skipped, empty url`);
  }

  return url;
}

export function consumePendingSharedIntent(): PendingSharedIntent {
  const payload: PendingSharedIntent = {
    url: pendingSharedUrl,
    title: pendingSharedTitle,
  };
  pendingSharedUrl = '';
  pendingSharedTitle = '';
  if (payload.url.length > 0) {
    console.info(`${SHARE_LOG_TAG}: consumed pending intent url=${payload.url}, title=${payload.title}`);
  }
  return payload;
}

export function consumePendingSharedUrl(): string {
  const current = pendingSharedUrl;
  pendingSharedUrl = '';
  pendingSharedTitle = '';
  if (current.length > 0) {
    console.info(`${SHARE_LOG_TAG}: consumed pending url=${current}`);
  }
  return current;
}
