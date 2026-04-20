// Integration tests against a real Linkwarden instance.
//
// Gated by `FOLIO_INTEGRATION=1` to keep the default `node --test` run
// hermetic — these tests open outbound HTTPS connections and mutate the
// target account. Defaults point at the fixture server kindly provided by
// the project owner; override via env vars when running against your own
// instance.
//
// Usage:
//   FOLIO_INTEGRATION=1 node --test tooling/linkwarden-integration.test.mjs
//
// Env vars (all optional — defaults are the fixture account):
//   FOLIO_INSTANCE   e.g. https://link.example.com:45456
//   FOLIO_USERNAME   Linkwarden username
//   FOLIO_PASSWORD   Linkwarden password
//
// The write-side tests create a uniquely-named temporary collection,
// attach a link, then delete the link + collection to leave the account
// clean.

import test from 'node:test';
import assert from 'node:assert/strict';

const RUN = process.env.FOLIO_INTEGRATION === '1';
const INSTANCE = (process.env.FOLIO_INSTANCE ?? 'https://link.xiebaiyuan.com:45456').replace(/\/+$/, '');
const USERNAME = process.env.FOLIO_USERNAME ?? 'testtest';
const PASSWORD = process.env.FOLIO_PASSWORD ?? 'testtest';

const SKIP_MSG = 'Skipped — set FOLIO_INTEGRATION=1 to run integration tests.';

function skipSuite(title) {
  test(title, { skip: SKIP_MSG }, () => {});
}

if (!RUN) {
  skipSuite('linkwarden-integration (all tests)');
} else {
  let token = null;

  async function call(path, { method = 'GET', body = undefined } = {}) {
    const headers = { 'Content-Type': 'application/json' };
    if (token) {
      headers.Authorization = `Bearer ${token}`;
    }
    const res = await fetch(`${INSTANCE}${path}`, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    if (res.status < 200 || res.status > 299) {
      throw new Error(`HTTP_${res.status}:${text.slice(0, 200)}`);
    }
    return text.length > 0 ? JSON.parse(text) : {};
  }

  test('sign in returns a bearer token', async () => {
    const data = await call('/api/v1/session', {
      method: 'POST',
      body: { username: USERNAME, password: PASSWORD },
    });
    assert.equal(typeof data.response?.token, 'string');
    assert.ok(data.response.token.length > 0);
    token = data.response.token;
  });

  test('fetch current user id', async () => {
    assert.ok(token, 'prior sign-in test must have set the token');
    const data = await call('/api/v1/users/me');
    const id = Number(data.response?.id);
    assert.ok(Number.isFinite(id) && id > 0, `expected positive user id, got ${data.response?.id}`);
  });

  test('dashboard v2 totals match contract', async () => {
    assert.ok(token);
    const data = await call('/api/v2/dashboard');
    // numberOfPinnedLinks must be a non-negative integer; numberOfTags may
    // be absent on older servers (null → tolerated by LinkwardenApi).
    const pinned = data.data?.numberOfPinnedLinks;
    assert.ok(typeof pinned === 'number' && pinned >= 0, `bad pinned count: ${pinned}`);
    if (data.data && 'numberOfTags' in data.data) {
      const tags = data.data.numberOfTags;
      assert.ok(tags === null || (typeof tags === 'number' && tags >= 0), `bad tag count: ${tags}`);
    }
  });

  test('fetch collections returns a non-null array', async () => {
    assert.ok(token);
    const data = await call('/api/v1/collections');
    assert.ok(Array.isArray(data.response));
  });

  test('fetch first page of links honors cursor shape', async () => {
    assert.ok(token);
    const data = await call('/api/v1/search');
    assert.ok(Array.isArray(data.data?.links), `expected data.links array, got ${JSON.stringify(data).slice(0, 200)}`);
    // nextCursor is number (could be for next page) or absent at end
    if ('nextCursor' in data.data) {
      assert.ok(typeof data.data.nextCursor === 'number' || data.data.nextCursor === null);
    }
  });

  // --- write round-trip (create collection → create link → delete both) ---

  let tempCollectionId = 0;
  let tempLinkId = 0;
  let tempOwnerId = 0;
  const runTag = `folio-int-${Date.now()}`;
  const runCollectionName = `Folio Test ${new Date().toISOString().replace(/[:.]/g, '-')}`;

  test('create temporary collection', async () => {
    assert.ok(token);
    const data = await call('/api/v1/collections', {
      method: 'POST',
      body: {
        name: runCollectionName,
        description: 'Ephemeral — created by folio integration tests',
        color: '#2563eb',
      },
    });
    const id = Number(data.response?.id);
    const ownerId = Number(data.response?.ownerId);
    assert.ok(id > 0, `expected positive collection id, got ${data.response?.id}`);
    assert.ok(ownerId > 0, `expected positive owner id, got ${data.response?.ownerId}`);
    tempCollectionId = id;
    tempOwnerId = ownerId;
  });

  test('add a link into the temporary collection', async () => {
    assert.ok(tempCollectionId > 0);
    const data = await call('/api/v1/links', {
      method: 'POST',
      body: {
        url: `https://example.com/folio-int/${Date.now()}`,
        name: 'Folio integration probe',
        tags: [{ name: runTag }],
        collection: { id: tempCollectionId, ownerId: tempOwnerId },
      },
    });
    const id = Number(data.response?.id);
    assert.ok(id > 0, `expected positive link id, got ${data.response?.id}`);
    tempLinkId = id;
  });

  test('delete the temporary link', async () => {
    assert.ok(tempLinkId > 0);
    await call(`/api/v1/links/${tempLinkId}`, { method: 'DELETE' });
  });

  test('delete the temporary collection', async () => {
    assert.ok(tempCollectionId > 0);
    await call(`/api/v1/collections/${tempCollectionId}`, { method: 'DELETE' });
  });
}
