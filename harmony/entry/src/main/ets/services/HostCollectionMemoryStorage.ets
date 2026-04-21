import preferences from '@ohos.data.preferences';
import {
  parseHostCollectionMemory,
  serializeHostCollectionMemory,
  type HostCollectionMemoryState,
} from '../common/HostCollectionMemory';

const PREFERENCES_NAME: string = 'linkwarden.preferences';
const MEMORY_KEY: string = 'host_collection_memory';

export class HostCollectionMemoryStorage {
  private context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  async load(): Promise<HostCollectionMemoryState> {
    const pref = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const raw = await pref.get(MEMORY_KEY, '');
    return parseHostCollectionMemory(typeof raw === 'string' ? raw : '');
  }

  async save(state: HostCollectionMemoryState): Promise<void> {
    const pref = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await pref.put(MEMORY_KEY, serializeHostCollectionMemory(state));
    await pref.flush();
  }
}
