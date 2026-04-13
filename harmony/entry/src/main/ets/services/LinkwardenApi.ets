import http from '@ohos.net.http';
import type { BusinessError } from '@ohos.base';
import type { LinkItem, PagedLinks, CollectionItem } from '../common/Models';
import { buildQueryString, normalizeInstanceUrl } from '../common/Query';
import type { LinkSearchQueryParams } from '../common/Query';
import {
  mapLinkDetailResponse,
  mapLinkPayload,
  mapPagedLinksResponse,
  mapCollectionPayload,
  mapCollectionsResponse,
} from '../common/LinkMapper';
import type {
  CollectionPayload,
  LinkDetailResponse,
  SearchResponse,
  CollectionsResponse,
  LinkPayload,
} from '../common/LinkMapper';

interface SignInRequest {
  username: string;
  password: string;
}

interface SignInResponseBody {
  token: string;
}

interface SignInResponse {
  response: SignInResponseBody;
}

interface DashboardResponse {
  response?: Array<LinkPayload>;
}

interface CurrentUserResponse {
  response?: CurrentUserResponseBody;
}

interface CurrentUserResponseBody {
  id?: number;
}

interface CollectionCountResponseBody {
  links?: number;
}

interface CollectionParentResponseBody {
  name?: string;
}

interface CollectionDetailPayload extends CollectionPayload {
  _count?: CollectionCountResponseBody;
  parent?: CollectionParentResponseBody;
}

interface CollectionDetailResponse {
  response: CollectionDetailPayload;
}

interface AddLinkRequest {
  url: string;
  name: string;
  tags?: Array<UpdateLinkTagRequest>;
  collection?: UpdateLinkCollectionRequest;
}

export interface AddLinkOptions {
  tagNames?: Array<string>;
  collection?: CollectionItem | null;
}

export interface CreateCollectionOptions {
  description?: string;
  color?: string;
  parentId?: number;
}

interface CreateCollectionRequest {
  name: string;
  description?: string;
  color?: string;
  parentId?: number;
}

interface UpdateLinkCollectionRequest {
  id: number;
  ownerId: number;
}

interface UpdateLinkTagRequest {
  id?: number;
  name: string;
}

interface UpdateLinkPinRequest {
  id?: number;
}

interface UpdateLinkRequest {
  id: number;
  name: string;
  url: string;
  description: string;
  collection: UpdateLinkCollectionRequest;
  tags: Array<UpdateLinkTagRequest>;
  pinnedBy?: Array<UpdateLinkPinRequest>;
}

export class LinkwardenApi {
  private instance: string;
  private token: string;

  constructor(instance: string, token: string = '') {
    this.instance = normalizeInstanceUrl(instance);
    this.token = token;
  }

  setInstance(instance: string): void {
    this.instance = normalizeInstanceUrl(instance);
  }

  setToken(token: string): void {
    this.token = token;
  }

  async signIn(username: string, password: string): Promise<string> {
    const payload: SignInRequest = { username, password };
    const responseText = await this.request(
      '/api/v1/session',
      http.RequestMethod.POST,
      JSON.stringify(payload)
    );
    const response = JSON.parse(responseText) as SignInResponse;
    const token = response.response.token;
    if (typeof token !== 'string' || token.length === 0) {
      throw new Error('TOKEN_MISSING');
    }

    this.token = token;
    return token;
  }

  async fetchLinks(
    cursor: number,
    searchQueryString: string = '',
    collectionId: number = 0,
    pinnedOnly: boolean = false
  ): Promise<PagedLinks> {
    const queryParams: LinkSearchQueryParams = {
      cursor,
      searchQueryString: searchQueryString.trim().length > 0 ? searchQueryString.trim() : undefined,
      collectionId: collectionId > 0 ? collectionId : undefined,
      pinnedOnly,
    };
    const query = buildQueryString(queryParams);

    const path = query.length > 0 ? `/api/v1/search?${query}` : '/api/v1/search';
    const responseText = await this.request(path, http.RequestMethod.GET);
    const response = JSON.parse(responseText) as SearchResponse;
    return mapPagedLinksResponse(response);
  }

  async fetchDashboardLinks(): Promise<Array<LinkItem>> {
    const responseText = await this.request('/api/v1/dashboard?sort=0', http.RequestMethod.GET);
    const response = JSON.parse(responseText) as DashboardResponse;
    const links = Array.isArray(response.response)
      ? response.response.map((item: LinkPayload) => mapLinkPayload(item))
      : [];
    return links;
  }

  async fetchPinnedLinks(): Promise<Array<LinkItem>> {
    const page = await this.fetchLinks(0, '', 0, true);
    return page.links;
  }

  async fetchCollections(): Promise<Array<CollectionItem>> {
    const responseText = await this.request('/api/v1/collections', http.RequestMethod.GET);
    const response = JSON.parse(responseText) as CollectionsResponse;
    return mapCollectionsResponse(response);
  }

  async getLink(id: number): Promise<LinkItem> {
    const responseText = await this.request(`/api/v1/links/${id}`, http.RequestMethod.GET);
    const response = JSON.parse(responseText) as LinkDetailResponse;
    return mapLinkDetailResponse(response);
  }

  async addLink(url: string, name: string = '', options?: AddLinkOptions): Promise<LinkItem> {
    const payload: AddLinkRequest = { url, name };

    if (options?.tagNames && options.tagNames.length > 0) {
      const tags: Array<UpdateLinkTagRequest> = options.tagNames.map((tagName) => {
        const item: UpdateLinkTagRequest = {
          name: tagName,
        };
        return item;
      });
      payload.tags = tags;
    }

    if (options?.collection && options.collection.id > 0 && options.collection.ownerId > 0) {
      payload.collection = {
        id: options.collection.id,
        ownerId: options.collection.ownerId,
      };
    }

    const responseText = await this.request('/api/v1/links', http.RequestMethod.POST, JSON.stringify(payload));
    const response = JSON.parse(responseText) as LinkDetailResponse;
    return mapLinkDetailResponse(response);
  }

  async updateLink(link: LinkItem): Promise<LinkItem> {
    const linkId = Number(link.id);
    const collectionId = Number(link.collectionId);
    const collectionOwnerId = Number(link.collectionOwnerId);

    if (!Number.isFinite(linkId) || linkId <= 0) {
      throw new Error('INVALID_LINK_ID');
    }

    if (!Number.isFinite(collectionId) || collectionId <= 0 || !Number.isFinite(collectionOwnerId) || collectionOwnerId <= 0) {
      throw new Error('MISSING_COLLECTION_METADATA');
    }

    const tags: Array<UpdateLinkTagRequest> = link.tags
      .filter((tag) => tag.name.trim().length > 0)
      .map((tag) => {
        const id = Number(tag.id);
        const item: UpdateLinkTagRequest = id > 0
          ? {
              id,
              name: tag.name,
            }
          : {
              name: tag.name,
            };

        return item;
      });

    const payload: UpdateLinkRequest = {
      id: linkId,
      name: link.name,
      url: link.url,
      description: link.description,
      collection: {
        id: collectionId,
        ownerId: collectionOwnerId,
      },
      tags,
    };
    const responseText = await this.request(
      `/api/v1/links/${linkId}`,
      http.RequestMethod.PUT,
      JSON.stringify(payload)
    );
    const response = JSON.parse(responseText) as LinkDetailResponse;
    return mapLinkDetailResponse(response);
  }

  async fetchCurrentUserId(): Promise<number> {
    const responseText = await this.request('/api/v1/users/me', http.RequestMethod.GET);
    const response = JSON.parse(responseText) as CurrentUserResponse;
    const userId = Number(response.response?.id ?? 0);

    if (!Number.isFinite(userId) || userId <= 0) {
      throw new Error('USER_ID_MISSING');
    }

    return userId;
  }

  async setPinned(link: LinkItem, pinned: boolean, userId: number): Promise<LinkItem> {
    const linkId = Number(link.id);
    const collectionId = Number(link.collectionId);
    const collectionOwnerId = Number(link.collectionOwnerId);

    if (!Number.isFinite(linkId) || linkId <= 0) {
      throw new Error('INVALID_LINK_ID');
    }

    if (!Number.isFinite(collectionId) || collectionId <= 0 || !Number.isFinite(collectionOwnerId) || collectionOwnerId <= 0) {
      throw new Error('MISSING_COLLECTION_METADATA');
    }

    if (!Number.isFinite(userId) || userId <= 0) {
      throw new Error('USER_ID_MISSING');
    }

    const pinRequest: UpdateLinkPinRequest = pinned ? { id: userId } : {};

    const payload: UpdateLinkRequest = {
      id: linkId,
      name: link.name,
      url: link.url,
      description: link.description,
      collection: {
        id: collectionId,
        ownerId: collectionOwnerId,
      },
      tags: [],
      pinnedBy: [pinRequest],
    };
    const responseText = await this.request(
      `/api/v1/links/${linkId}`,
      http.RequestMethod.PUT,
      JSON.stringify(payload)
    );
    const response = JSON.parse(responseText) as LinkDetailResponse;
    return mapLinkDetailResponse(response);
  }

  async createCollection(name: string, options?: CreateCollectionOptions): Promise<CollectionItem> {
    const trimmedName = name.trim();
    if (trimmedName.length === 0) {
      throw new Error('COLLECTION_NAME_REQUIRED');
    }

    const payload: CreateCollectionRequest = {
      name: trimmedName,
    };

    const description = options?.description?.trim() ?? '';
    if (description.length > 0) {
      payload.description = description;
    }

    const color = options?.color?.trim() ?? '';
    if (color.length > 0) {
      payload.color = color;
    }

    if (typeof options?.parentId === 'number' && options.parentId > 0) {
      payload.parentId = options.parentId;
    }

    const responseText = await this.request('/api/v1/collections', http.RequestMethod.POST, JSON.stringify(payload));
    const response = JSON.parse(responseText) as CollectionDetailResponse;
    return mapCollectionPayload(response.response);
  }

  async deleteLink(id: number): Promise<void> {
    await this.request(`/api/v1/links/${id}`, http.RequestMethod.DELETE);
  }

  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };

    if (this.token.length > 0) {
      headers.Authorization = `Bearer ${this.token}`;
    }

    return headers;
  }

  private request(path: string, method: http.RequestMethod, body: string = ''): Promise<string> {
    return new Promise((resolve, reject) => {
      const request = http.createHttp();
      const options: http.HttpRequestOptions = {
        method,
        header: this.buildHeaders(),
        readTimeout: 30000,
        connectTimeout: 30000,
        expectDataType: http.HttpDataType.STRING,
      };

      if (body.length > 0) {
        options.extraData = body;
      }

      request.request(`${this.instance}${path}`, options, (err: BusinessError, data: http.HttpResponse) => {
        request.destroy();

        if (err) {
          reject(new Error(`REQUEST_${err.code}`));
          return;
        }

        const resultText = typeof data.result === 'string' ? data.result : JSON.stringify(data.result ?? {});

        if (data.responseCode < 200 || data.responseCode > 299) {
          reject(new Error(`HTTP_${data.responseCode}:${resultText}`));
          return;
        }

        resolve(resultText);
      });
    });
  }
}
