export interface LinkSearchQueryParams {
  cursor: number;
  searchQueryString?: string;
  collectionId?: number;
  pinnedOnly?: boolean;
}

export function normalizeInstanceUrl(input: string): string {
  const trimmed = input.trim();
  if (trimmed.length === 0) {
    return 'https://link.xiebaiyuan.com:45456';
  }

  const withScheme = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
  return withScheme.replace(/\/+$/, '');
}

export function buildQueryString(params: LinkSearchQueryParams): string {
  const pairs: Array<string> = [];
  pairs.push(`cursor=${encodeURIComponent(String(params.cursor))}`);

  if (params.searchQueryString !== undefined && params.searchQueryString !== null && params.searchQueryString !== '') {
    pairs.push(`searchQueryString=${encodeURIComponent(params.searchQueryString)}`);
  }

  if (typeof params.collectionId === 'number' && params.collectionId > 0) {
    pairs.push(`collectionId=${encodeURIComponent(String(params.collectionId))}`);
  }

  if (params.pinnedOnly === true) {
    pairs.push('pinnedOnly=true');
  }

  return pairs.join('&');
}
