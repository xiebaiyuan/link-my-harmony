export type ThemeMode = 'light' | 'dark' | 'system';
export type MainView = 'dashboard' | 'elements' | 'search' | 'settings';

export interface DockAction {
  id: 'dashboard' | 'add' | 'search' | 'settings';
  symbol: string;
  label: string;
  selected: boolean;
  primary: boolean;
}

export interface ThemePalette {
  page: string;
  surface: string;
  card: string;
  cardMuted: string;
  cardSelected: string;
  cardSuccess: string;
  input: string;
  border: string;
  textPrimary: string;
  textSecondary: string;
  textMuted: string;
  accent: string;
  accentStrong: string;
  accentSoft: string;
  accentText: string;
  danger: string;
  dockSurface: string;
  dockBorder: string;
  dockShadow: string;
  dockItem: string;
  dockItemActive: string;
  dockItemPrimary: string;
  dockText: string;
  dockTextActive: string;
  dockTextPrimary: string;
}

export interface DockMetrics {
  itemWidth: number;
  itemHeight: number;
  gap: number;
  padding: number;
}

export interface ThemeOption {
  mode: ThemeMode;
  title: string;
  subtitle: string;
}

export interface QuickMenuAction {
  id: 'add' | 'search' | 'settings';
  symbolKey: string;
  label: string;
}

export function createDockActions(mainView: MainView): Array<DockAction> {
  return [
    {
      id: 'dashboard',
      symbol: '⌂',
      label: 'Home',
      selected: mainView === 'dashboard',
      primary: false,
    },
    {
      id: 'add',
      symbol: '＋',
      label: 'Add',
      selected: false,
      primary: true,
    },
    {
      id: 'search',
      symbol: '⌕',
      label: 'Find',
      selected: mainView === 'search',
      primary: false,
    },
    {
      id: 'settings',
      symbol: '≡',
      label: 'Menu',
      selected: mainView === 'settings',
      primary: false,
    },
  ];
}

export function createQuickMenuActions(): Array<QuickMenuAction> {
  return [
    { id: 'add', symbolKey: 'plus_circle_fill', label: 'Add Link' },
    { id: 'search', symbolKey: 'magnifyingglass', label: 'Search' },
    { id: 'settings', symbolKey: 'gearshape', label: 'Settings' },
  ];
}

export function createDockMetrics(): DockMetrics {
  return {
    itemWidth: 64,
    itemHeight: 54,
    gap: 8,
    padding: 10,
  };
}

export function createThemeOptions(): Array<ThemeOption> {
  return [
    { mode: 'system', title: 'System', subtitle: 'Auto' },
    { mode: 'light', title: 'Light', subtitle: 'Bright' },
    { mode: 'dark', title: 'Dark', subtitle: 'Dim' },
  ];
}

export function shouldReturnToDashboard(mainView: MainView): boolean {
  return mainView !== 'dashboard';
}

export function createThemePalette(themeMode: ThemeMode): ThemePalette {
  if (themeMode === 'dark') {
    return {
      page: '#000000',
      surface: '#0c0c0c',
      card: '#161616',
      cardMuted: '#1c1c1e',
      cardSelected: '#0e253a',
      cardSuccess: '#0d2820',
      input: '#0f0f0f',
      border: '#2a2a2e',
      textPrimary: '#f8fbff',
      textSecondary: '#c7d2e3',
      textMuted: '#8fa1bb',
      accent: '#7dd3fc',
      accentStrong: '#0ea5e9',
      accentSoft: '#0b2940',
      accentText: '#032235',
      danger: '#fb7185',
      dockSurface: '#161616',
      dockBorder: '#2a2a2e',
      dockShadow: '#66000000',
      dockItem: '#1c1c1e',
      dockItemActive: '#15314d',
      dockItemPrimary: '#0ea5e9',
      dockText: '#c7d2e3',
      dockTextActive: '#f8fbff',
      dockTextPrimary: '#f8fbff',
    };
  }

  return {
    page: '#f5f7fb',
    surface: '#edf2f8',
    card: '#ffffff',
    cardMuted: '#f8fafc',
    cardSelected: '#e0f2fe',
    cardSuccess: '#dcfce7',
    input: '#f8fafc',
    border: '#dbe4f0',
    textPrimary: '#0f172a',
    textSecondary: '#475569',
    textMuted: '#64748b',
    accent: '#2563eb',
    accentStrong: '#1d4ed8',
    accentSoft: '#dbeafe',
    accentText: '#eff6ff',
    danger: '#dc2626',
    dockSurface: '#ffffff',
    dockBorder: '#dbe4f0',
    dockShadow: '#1f334155',
    dockItem: '#f8fafc',
    dockItemActive: '#dbeafe',
    dockItemPrimary: '#2563eb',
    dockText: '#475569',
    dockTextActive: '#1e3a8a',
    dockTextPrimary: '#eff6ff',
  };
}
