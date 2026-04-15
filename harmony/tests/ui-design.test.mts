import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createQuickMenuActions,
  createThemeOptions,
  createThemePalette,
  shouldReturnToDashboard,
} from '../entry/src/main/ets/common/UiDesign.ts';

test('createQuickMenuActions exposes add search and menu destinations', () => {
  const actions = createQuickMenuActions();

  assert.equal(actions.length, 3);
  assert.deepEqual(
    actions.map((action) => action.id),
    ['add', 'search', 'settings']
  );
});

test('createThemePalette returns higher-contrast dark tokens', () => {
  const palette = createThemePalette('dark');

  assert.equal(palette.page, '#000000');
  assert.equal(palette.card, '#161616');
  assert.equal(palette.textPrimary, '#f8fbff');
  assert.equal(palette.accent, '#7dd3fc');
});

test('createThemePalette keeps bright light tokens for system mode fallback', () => {
  const palette = createThemePalette('system');

  assert.equal(palette.page, '#f5f7fb');
  assert.equal(palette.card, '#ffffff');
  assert.equal(palette.textPrimary, '#0f172a');
  assert.equal(palette.accent, '#2563eb');
  assert.equal(palette.dockSurface, '#ffffff');
});

test('shouldReturnToDashboard only handles non-home pages', () => {
  assert.equal(shouldReturnToDashboard('dashboard'), false);
  assert.equal(shouldReturnToDashboard('elements'), true);
  assert.equal(shouldReturnToDashboard('search'), true);
  assert.equal(shouldReturnToDashboard('settings'), true);
});

test('createThemeOptions uses compact subtitles to avoid wrapping', () => {
  const options = createThemeOptions();

  assert.deepEqual(
    options.map((option) => option.subtitle),
    ['Auto', 'Bright', 'Dim']
  );
});
