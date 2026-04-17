import { DEFAULT_INSTANCE_URL } from './query-utils.mjs';

export function createDefaultSessionState() {
  return {
    instance: DEFAULT_INSTANCE_URL,
    token: '',
    theme: 'system',
  };
}

function normalizeTheme(value) {
  return value === 'light' || value === 'dark' || value === 'system'
    ? value
    : 'system';
}

export function serializeSessionState(state) {
  return JSON.stringify({
    instance: typeof state?.instance === 'string' && state.instance.length > 0
      ? state.instance
      : DEFAULT_INSTANCE_URL,
    token: typeof state?.token === 'string' ? state.token : '',
    theme: normalizeTheme(state?.theme),
  });
}

export function parseSessionState(raw) {
  const fallback = createDefaultSessionState();

  if (typeof raw !== 'string' || raw.length === 0) {
    return fallback;
  }

  try {
    const parsed = JSON.parse(raw);
    return {
      instance: typeof parsed?.instance === 'string' && parsed.instance.length > 0
        ? parsed.instance
        : fallback.instance,
      token: typeof parsed?.token === 'string' ? parsed.token : fallback.token,
      theme: normalizeTheme(parsed?.theme),
    };
  } catch (error) {
    return fallback;
  }
}
