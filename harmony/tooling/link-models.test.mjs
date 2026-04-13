import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mapLinkPayload,
  mapPagedLinksResponse,
  mapLinkDetailResponse,
  mapCollectionsResponse,
} from './link-models.mjs';

test('mapLinkPayload keeps detail fields and falls back safely', () => {
  const mapped = mapLinkPayload({
    id: 7,
    name: 'Example',
    url: 'https://example.com',
    description: 'Saved article',
    createdAt: '2026-04-09T00:00:00.000Z',
    collection: {
      id: 3,
      ownerId: 17,
      name: 'Reading',
      color: '#0ea5e9',
    },
    tags: [
      { id: 10, name: 'tech' },
      { id: 11, name: 'news' },
    ],
  });

  assert.deepEqual(mapped, {
    id: 7,
    name: 'Example',
    url: 'https://example.com',
    description: 'Saved article',
    createdAt: '2026-04-09T00:00:00.000Z',
    collectionId: 3,
    collectionOwnerId: 17,
    collectionName: 'Reading',
    collectionColor: '#0ea5e9',
    pinned: false,
    tags: [
      { id: 10, name: 'tech' },
      { id: 11, name: 'news' },
    ],
  });
});

test('mapPagedLinksResponse maps list payloads and missing nextCursor to -1', () => {
  const mapped = mapPagedLinksResponse({
    data: {
      links: [
        {
          id: 1,
          url: 'https://a.example',
          description: 'A',
        },
      ],
    },
  });

  assert.deepEqual(mapped, {
    links: [
      {
        id: 1,
        name: '',
        url: 'https://a.example',
        description: 'A',
        createdAt: '',
        collectionId: 0,
        collectionOwnerId: 0,
        collectionName: '',
        collectionColor: '',
        pinned: false,
        tags: [],
      },
    ],
    nextCursor: -1,
  });
});

test('mapLinkDetailResponse unwraps response payload', () => {
  const mapped = mapLinkDetailResponse({
    response: {
      id: 11,
      name: 'Detail',
      url: 'https://detail.example',
      description: '',
      createdAt: '2026-04-09T01:02:03.000Z',
      collection: {
        name: 'Inbox',
      },
    },
  });

  assert.equal(mapped.id, 11);
  assert.equal(mapped.collectionId, 0);
  assert.equal(mapped.collectionName, 'Inbox');
  assert.equal(mapped.createdAt, '2026-04-09T01:02:03.000Z');
});

test('mapLinkPayload supports collection.owner.id and numeric strings', () => {
  const mapped = mapLinkPayload({
    id: '19',
    url: 'https://example.org',
    collection: {
      id: '8',
      owner: {
        id: '41',
      },
    },
    tags: [{ id: '5', name: 'inbox' }],
  });

  assert.deepEqual(mapped, {
    id: 19,
    name: '',
    url: 'https://example.org',
    description: '',
    createdAt: '',
    collectionId: 8,
    collectionOwnerId: 41,
    collectionName: '',
    collectionColor: '',
    pinned: false,
    tags: [{ id: 5, name: 'inbox' }],
  });
});

test('mapLinkPayload maps pinnedBy into pinned flag', () => {
  const mapped = mapLinkPayload({
    id: 22,
    url: 'https://example.net',
    pinnedBy: [{ id: 1 }],
  });

  assert.equal(mapped.pinned, true);
});

test('mapCollectionsResponse keeps description and parent id fields', () => {
  const mapped = mapCollectionsResponse({
    response: [
      {
        id: '9',
        ownerId: '12',
        name: 'Reading',
        description: 'Articles to revisit',
        color: '#2563eb',
        parentId: '3',
        parent: { name: 'Inbox' },
        _count: { links: 8 },
      },
    ],
  });

  assert.deepEqual(mapped, [
    {
      id: 9,
      ownerId: 12,
      name: 'Reading',
      description: 'Articles to revisit',
      color: '#2563eb',
      parentId: 3,
      parentName: 'Inbox',
      linkCount: 8,
    },
  ]);
});
