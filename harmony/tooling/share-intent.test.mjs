import test from 'node:test';
import assert from 'node:assert/strict';
import { extractSharedUrlFromWantLike } from './share-intent.mjs';

test('extractSharedUrlFromWantLike prefers want.uri', () => {
  const url = extractSharedUrlFromWantLike({
    uri: 'https://example.com/page',
    parameters: {
      text: 'https://fallback.example',
    },
  });

  assert.equal(url, 'https://example.com/page');
});

test('extractSharedUrlFromWantLike extracts url from text payload', () => {
  const url = extractSharedUrlFromWantLike({
    action: 'ohos.want.action.sendData',
    parameters: {
      'android.intent.extra.TEXT': 'Check this https://example.com/a?x=1',
    },
  });

  assert.equal(url, 'https://example.com/a?x=1');
});

test('extractSharedUrlFromWantLike supports ohos shareUrl key', () => {
  const url = extractSharedUrlFromWantLike({
    parameters: {
      'ohos.extra.param.key.shareUrl': 'https://example.com/share',
    },
  });

  assert.equal(url, 'https://example.com/share');
});

test('extractSharedUrlFromWantLike supports ability.params.stream', () => {
  const url = extractSharedUrlFromWantLike({
    parameters: {
      'ability.params.stream': 'https://example.com/stream',
    },
  });

  assert.equal(url, 'https://example.com/stream');
});

test('extractSharedUrlFromWantLike supports browser ability.picker.records payload', () => {
  const url = extractSharedUrlFromWantLike({
    parameters: {
      'ability.picker.records': {
        'general.hyperlink': [
          {
            '2': 'https://example.com/from-record',
            '4': 'Title',
            '5': 'https://example.com/from-record',
            '6': 'base64blob',
          },
        ],
      },
    },
  });

  assert.equal(url, 'https://example.com/from-record');
});

test('extractSharedUrlFromWantLike scans unknown structured parameters', () => {
  const url = extractSharedUrlFromWantLike({
    parameters: {
      randomPayload: {
        nested: 'https://example.com/from-object',
      },
    },
  });

  assert.equal(url, 'https://example.com/from-object');
});

test('extractSharedUrlFromWantLike supports naked host and normalizes scheme', () => {
  const url = extractSharedUrlFromWantLike({
    parameters: {
      text: 'news.ycombinator.com',
    },
  });

  assert.equal(url, 'https://news.ycombinator.com');
});

test('extractSharedUrlFromWantLike returns empty string for non-url text', () => {
  const url = extractSharedUrlFromWantLike({
    parameters: {
      text: 'just some words',
    },
  });

  assert.equal(url, '');
});

test('extractSharedUrlFromWantLike does not treat bundle name as url', () => {
  const url = extractSharedUrlFromWantLike({
    parameters: {
      'ability.picker.caller': {
        bundleName: 'com.huawei.hmos.browser',
      },
    },
  });

  assert.equal(url, '');
});
