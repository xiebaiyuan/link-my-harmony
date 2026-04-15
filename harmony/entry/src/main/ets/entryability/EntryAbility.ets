import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import window from '@ohos.window';
import { Configuration, ConfigurationConstant } from '@kit.AbilityKit';
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
    // Sync system color mode on creation
    this.syncSystemColorMode(this.context?.config?.colorMode);
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

  // Called by OS whenever system configuration changes (including dark mode toggle)
  onConfigurationUpdate(config: Configuration): void {
    this.syncSystemColorMode(config.colorMode);
  }

  // Called when app returns to foreground — sync in case theme changed while backgrounded
  onForeground(): void {
    this.syncSystemColorMode(this.context?.config?.colorMode);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      const mainWin = windowStage.getMainWindowSync();
      mainWin.setWindowLayoutFullScreen(true);

      // Re-query avoid area every time layout changes (fires after fullscreen takes effect)
      mainWin.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          const h = px2vp(data.area.topRect.height);
          AppStorage.setOrCreate<number>('safeAreaTop', h > 0 ? h : 44);
        }
      });

      // Initial value (may be 0 before fullscreen; the listener above will correct it)
      const avoidArea = mainWin.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const topH = px2vp(avoidArea.topRect.height);
      AppStorage.setOrCreate<number>('safeAreaTop', topH > 0 ? topH : 44);
    } catch (e) {
      AppStorage.setOrCreate<number>('safeAreaTop', 44);
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        console.error(`Failed to load page: ${JSON.stringify(err)}`);
      }
    });
  }

  private syncSystemColorMode(colorMode: ConfigurationConstant.ColorMode | undefined): void {
    const isDark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate<boolean>('deviceDarkMode', isDark);
  }
}
