// How fast a gesture moved as it was released, and how its pan glides from
// there, which FFI runs.

import { PanMomentum } from '@maplibre/native-ffi';

// A release's speed is over its last 100 ms.
export const VELOCITY_WINDOW_MS = 100;

// A pan glides as ArkUI's Scroll, List, and Grid fling (Scrollable in ArkUI's
// ace_engine, OpenHarmony 7.0). The speed decays at 4.2 times the friction per
// second, from the release speed times a gain: with the default `friction()`,
// 0.75, and a gain of 1.5, or with 1 and 1.2 for a release slower than 3000 px/s.
const FRICTION_SCALE = 4.2;
const FRICTION = 0.75;
const GAIN = 1.5;
const SLOW_SPEED_PX = 3000;
const SLOW_FRICTION = 1;
const SLOW_GAIN = 1.2;
// A fling starts from 240 px/s, ends at 120 px/s, and starts no faster than
// `flingSpeedLimit()`'s default, 9000 vp/s.
const MIN_SPEED_PX = 240;
const STOP_SPEED_PX = 120;
const MAX_SPEED = 9000;

/**
 * The glide of a pan released at `x`, `y` vp/s, on a display of `density` px
 * per vp.
 */
export function panMomentum(x: number, y: number, density: number): PanMomentum {
  const slow = Math.hypot(x, y) * density < SLOW_SPEED_PX;
  const gain = slow ? SLOW_GAIN : GAIN;
  const friction = slow ? SLOW_FRICTION : FRICTION;
  return {
    velocity: { x: x * gain, y: y * gain },
    decay: {
      halfLifeMs: Math.LN2 / (FRICTION_SCALE * friction) * 1000,
      minSpeed: MIN_SPEED_PX / density,
      stopSpeed: STOP_SPEED_PX / density,
      maxSpeed: MAX_SPEED,
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
