import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { captureSharedUrlFromWant } from '../common/ShareIntent';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want): void {
    const keys = Object.keys(want?.parameters ?? {});
    console.info(`EntryAbility onCreate action=${want?.action ?? ''} uri=${want?.uri ?? ''} keys=${JSON.stringify(keys)} params=${JSON.stringify(want?.parameters ?? {})}`);
    const url = captureSharedUrlFromWant(want);
    if (url.length > 0) {
      console.info(`Captured shared URL in onCreate: ${url}`);
    } else {
      console.info('No shared URL extracted in onCreate');
    }
  }

  onNewWant(want: Want): void {
    const keys = Object.keys(want?.parameters ?? {});
    console.info(`EntryAbility onNewWant action=${want?.action ?? ''} uri=${want?.uri ?? ''} keys=${JSON.stringify(keys)} params=${JSON.stringify(want?.parameters ?? {})}`);
    const url = captureSharedUrlFromWant(want);
    if (url.length > 0) {
      console.info(`Captured shared URL in onNewWant: ${url}`);
    } else {
      console.info('No shared URL extracted in onNewWant');
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        console.error(`Failed to load page: ${JSON.stringify(err)}`);
      }
    });
  }
}
