// The runner that `aa test` starts. It starts the test ability, which runs the
// suite in a window, so cases can show components.

import abilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import TestRunner from '@ohos.application.testRunner';

export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {
  }

  onRun(): void {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const bundleName = abilityDelegatorRegistry.getArguments().bundleName;
    delegator.startAbility({ bundleName: bundleName, abilityName: 'TestAbility' }, (error) => {
      // The callback gets null when the ability starts.
      if (error) {
        console.error(`MapLibre: can't start the test ability: ${error.message}`);
      }
    });
  }
}
