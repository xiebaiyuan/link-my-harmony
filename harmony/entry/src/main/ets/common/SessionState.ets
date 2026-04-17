export type ThemeMode = 'light' | 'dark' | 'system';

export const DEFAULT_INSTANCE_URL = 'https://cloud.linkwarden.app';

export interface SessionState {
  instance: string;
  token: string;
  theme: ThemeMode;
}

interface SessionStatePayload {
  instance?: string;
  token?: string;
  theme?: string;
}

export function createDefaultSessionState(): SessionState {
  return {
    instance: DEFAULT_INSTANCE_URL,
    token: '',
    theme: 'system',
  };
}

export function normalizeThemeMode(value: string): ThemeMode {
  if (value === 'light' || value === 'dark') {
    return value;
  }

  return 'system';
}

export function serializeSessionState(state: SessionState): string {
  return JSON.stringify({
    instance: state.instance.length > 0 ? state.instance : DEFAULT_INSTANCE_URL,
    token: state.token,
    theme: state.theme,
  });
}

export function parseSessionState(raw: string): SessionState {
  const fallback = createDefaultSessionState();

  if (raw.length === 0) {
    return fallback;
  }

  try {
    const parsed = JSON.parse(raw) as SessionStatePayload;
    const instanceValue = parsed.instance;
    const tokenValue = parsed.token;
    const themeValue = parsed.theme;

    const state: SessionState = {
      instance: typeof instanceValue === 'string' && instanceValue.length > 0 ? instanceValue : fallback.instance,
      token: typeof tokenValue === 'string' ? tokenValue : fallback.token,
      theme: normalizeThemeMode(typeof themeValue === 'string' ? themeValue : ''),
    };

    return state;
  } catch (error) {
    return fallback;
  }
}
