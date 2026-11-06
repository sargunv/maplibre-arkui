// The tick that rotation plays as it crosses a haptic notch.

import { BusinessError } from '@ohos.base';
import vibrator from '@ohos.vibrator';

/**
 * Plays a soft tick, which follows the system's touch feedback setting.
 * Resolves with the vibrator's error when it refuses, for tests, and never
 * rejects: without `ohos.permission.VIBRATE`, which a library can't declare
 * for its apps, the vibrator refuses with 201, and a device without one
 * refuses too. Neither is a failure of the map, so neither is reported.
 */
export function playTick(): Promise<BusinessError | undefined> {
  try {
    return vibrator.startVibration(
      { type: 'preset', effectId: vibrator.HapticFeedback.EFFECT_SOFT, count: 1 },
      { usage: 'touch' },
    ).then((): BusinessError | undefined => undefined, (error: BusinessError): BusinessError | undefined => error);
  } catch (error) {
    return Promise.resolve(error as BusinessError);
  }
}
