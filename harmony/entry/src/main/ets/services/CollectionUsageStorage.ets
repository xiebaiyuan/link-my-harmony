import preferences from '@ohos.data.preferences';
import {
  parseCollectionUsage,
  serializeCollectionUsage,
  type CollectionUsageState,
} from '../common/CollectionUsage';

const PREFERENCES_NAME: string = 'linkwarden.preferences';
const USAGE_KEY: string = 'collection_usage';

export class CollectionUsageStorage {
  private context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  async load(): Promise<CollectionUsageState> {
    const pref = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const raw = await pref.get(USAGE_KEY, '');
    return parseCollectionUsage(typeof raw === 'string' ? raw : '');
  }

  async save(state: CollectionUsageState): Promise<void> {
    const pref = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await pref.put(USAGE_KEY, serializeCollectionUsage(state));
    await pref.flush();
  }
}
