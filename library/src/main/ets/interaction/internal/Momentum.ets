import { PanMomentum } from '@maplibre/native-ffi';

// A release's speed is over its last 100 ms.
export const VELOCITY_WINDOW_MS = 100;

/**
 * The glide of a pan released at `x`, `y` vp/s on a display of `density` px
 * per vp, as ArkUI's `Scroll` and `List` fling (ace_engine's `scrollable.cpp`,
 * OpenHarmony 7.0, and the SDK's `friction()` and `flingSpeedLimit()`): the
 * release speed times a gain decays at 4.2 times the friction per second, from
 * at least 240 px/s, down to 120 px/s, starting at most 9000 vp/s. A release
 * under 3000 px/s takes a gain of 1.2 and friction 1, and a faster one 1.5 and
 * the default friction, 0.75.
 */
export function panMomentum(x: number, y: number, density: number): PanMomentum {
  const slow = Math.hypot(x, y) * density < 3000;
  const gain = slow ? 1.2 : 1.5;
  return {
    velocity: { x: x * gain, y: y * gain },
    decay: {
      halfLifeMs: Math.LN2 / (4.2 * (slow ? 1 : 0.75)) * 1000,
      minSpeed: 240 / density,
      stopSpeed: 120 / density,
      maxSpeed: 9000,
    },
  };
}

// A velocity from the samples of the last 100 ms before a release.
export class Velocity {
  private times: number[] = [];
  private values: number[] = [];

  add(time: number, value: number): void {
    const last = this.times.length - 1;
    if (last >= 0 && time < this.times[last]) {
      this.clear();
    }
    this.times.push(time);
    this.values.push(value);
    if (this.times.length > 20) {
      this.times.shift();
      this.values.shift();
    }
  }

  clear(): void {
    this.times = [];
    this.values = [];
  }

  perSecond(now: number): number {
    let first = -1;
    for (let i = 0; i < this.times.length; i++) {
      if (now - this.times[i] <= VELOCITY_WINDOW_MS) {
        first = i;
        break;
      }
    }
    const last = this.times.length - 1;
    if (first < 0 || last <= first || this.times[last] <= this.times[first]) {
      return 0;
    }
    return (this.values[last] - this.values[first]) / (this.times[last] - this.times[first]) * 1000;
  }
}
