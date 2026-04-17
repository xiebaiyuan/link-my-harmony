export const DEFAULT_INSTANCE_URL = 'https://cloud.linkwarden.app';

export function normalizeInstanceUrl(input) {
  const trimmed = String(input ?? '').trim();
  if (trimmed.length === 0) {
    return DEFAULT_INSTANCE_URL;
  }

  const withScheme = /^https?:\/\//i.test(trimmed)
    ? trimmed
    : `https://${trimmed}`;

  return withScheme.replace(/\/+$/, '');
}

export function buildQueryString(params) {
  return Object.entries(params)
    .filter(([, value]) => value !== undefined && value !== null && value !== '')
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`)
    .join('&');
}
