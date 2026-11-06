import abilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import { Hypium } from '@ohos/hypium';

import testsuite from '../test/List.test';
import { testMap } from './TestMaps';

export default class TestAbility extends UIAbility {
  // The suite starts once the page has loaded, so the cases can use its map.
  onWindowStageCreate(windowStage: window.WindowStage): void {
    testMap.windowStage = windowStage;
    windowStage.loadContent('testability/pages/Index', (error) => {
      if (error.code !== 0) {
        console.error(`MapLibre: can't load the test page: ${error.message}`);
        return;
      }
      Hypium.hypiumTest(abilityDelegatorRegistry.getAbilityDelegator(),
        abilityDelegatorRegistry.getArguments(), testsuite);
    });
  }
}
