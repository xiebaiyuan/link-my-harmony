import preferences from '@ohos.data.preferences';
import {
  createDefaultSessionState,
  parseSessionState,
  serializeSessionState,
  type SessionState,
} from '../common/SessionState';

const PREFERENCES_NAME: string = 'linkwarden.preferences';
const SESSION_STATE_KEY: string = 'session_state';

export class SessionStorage {
  private context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  async load(): Promise<SessionState> {
    const pref = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const raw = await pref.get(SESSION_STATE_KEY, '');
    return parseSessionState(typeof raw === 'string' ? raw : '');
  }

  async save(state: SessionState): Promise<void> {
    const pref = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await pref.put(SESSION_STATE_KEY, serializeSessionState(state));
    await pref.flush();
  }

  async clear(): Promise<void> {
    await this.save(createDefaultSessionState());
  }

  async loadLastAddedCollectionId(): Promise<number> {
    const pref = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const raw = await pref.get('last_added_collection_id', 0);
    return typeof raw === 'number' ? raw : 0;
  }

  async saveLastAddedCollectionId(id: number): Promise<void> {
    const pref = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await pref.put('last_added_collection_id', id);
    await pref.flush();
  }
}
