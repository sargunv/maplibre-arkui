import abilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import { Hypium } from '@ohos/hypium';

import testsuite from '../test/List.test';

export default class TestAbility extends UIAbility {
  onCreate(): void {
    Hypium.hypiumTest(abilityDelegatorRegistry.getAbilityDelegator(),
      abilityDelegatorRegistry.getArguments(), testsuite);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('testability/pages/Index', (error) => {
      if (error.code !== 0) {
        console.error(`MapLibre: can't load the test page: ${error.message}`);
      }
    });
  }
}
