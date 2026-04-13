export interface LinkTag {
  id: number;
  name: string;
}

export interface LinkItem {
  id: number;
  name: string;
  url: string;
  description: string;
  createdAt: string;
  collectionId: number;
  collectionOwnerId: number;
  collectionName: string;
  collectionColor: string;
  pinned: boolean;
  tags: Array<LinkTag>;
}

export interface PagedLinks {
  links: Array<LinkItem>;
  nextCursor: number;
}

export interface CollectionItem {
  id: number;
  ownerId: number;
  name: string;
  description: string;
  color: string;
  parentId: number;
  parentName: string;
  linkCount: number;
}

export function emptyLinkItem(): LinkItem {
  return {
    id: 0,
    name: '',
    url: '',
    description: '',
    createdAt: '',
    collectionId: 0,
    collectionOwnerId: 0,
    collectionName: '',
    collectionColor: '',
    pinned: false,
    tags: [],
  };
}
