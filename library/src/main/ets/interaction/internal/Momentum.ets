import { AnchoredMomentum, MomentumDecay, PanMomentum, ScreenPoint } from '@maplibre/native-ffi';

import { InteractionOptions, IntervalOptions, MomentumOptions, SnapOptions } from '../InteractionOptions';
import { Interval } from './BearingNotches';

// A release's speed is over its last 100 ms.
export const VELOCITY_WINDOW_MS = 100;

/** How a movement glides and settles, as `checkGlides()` checked it. */
export interface Glide {
  momentum: MomentumOptions;
  snap: Snap;
}

export interface Snap extends Interval {
  tolerance: number | undefined;
  durationMs: number | undefined;
}

/** The options' numbers, each one that's out of range left out, so it takes its default. */
export interface Glides {
  pan: Glide;
  zoom: Glide;
  rotate: Glide;
  pitch: Glide;
  haptics: Interval;
}

/**
 * The glides and haptics of `options`. Each value out of range goes to `fail`
 * and is left out. A snap's interval, and the haptics', takes its default
 * here: north for rotation, and none for the rest.
 */
export function checkGlides(options: InteractionOptions, fail: (error: Error) => void): Glides {
  // `value`, or undefined when it's out of range: not finite, or not positive
  // or negative as `least` says.
  const checked = (path: string, value: number | undefined, least: 'any' | 'zero' | 'positive'): number | undefined => {
    if (value === undefined ||
      (Number.isFinite(value) && (least === 'any' || value > 0 || (least === 'zero' && value === 0)))) {
      return value;
    }
    const range = least === 'any' ? 'finite' : least === 'zero' ? 'finite and not negative' : 'finite and positive';
    fail(new Error(`interactions.${path} must be ${range}: ${value}`));
    return undefined;
  };
  const interval = (path: string, given: IntervalOptions | undefined, fallback: number): Interval => ({
    interval: checked(`${path}.interval`, given?.interval, 'zero') ?? fallback,
    offset: checked(`${path}.offset`, given?.offset, 'any') ?? 0,
  });
  const glide = (name: string, momentum: MomentumOptions | undefined, snap: SnapOptions | undefined,
    snapInterval: number): Glide => {
    const spaced = interval(`${name}.snap`, snap, snapInterval);
    return {
      momentum: {
        enabled: momentum?.enabled,
        halfLifeMs: checked(`${name}.momentum.halfLifeMs`, momentum?.halfLifeMs, 'positive'),
        minSpeed: checked(`${name}.momentum.minSpeed`, momentum?.minSpeed, 'zero'),
        stopSpeed: checked(`${name}.momentum.stopSpeed`, momentum?.stopSpeed, 'positive'),
        maxSpeed: checked(`${name}.momentum.maxSpeed`, momentum?.maxSpeed, 'positive'),
        maxDistance: checked(`${name}.momentum.maxDistance`, momentum?.maxDistance, 'positive'),
      },
      snap: {
        interval: spaced.interval,
        offset: spaced.offset,
        tolerance: checked(`${name}.snap.tolerance`, snap?.tolerance, 'zero'),
        durationMs: checked(`${name}.snap.durationMs`, snap?.durationMs, 'zero'),
      },
    };
  };
  return {
    pan: glide('pan', options.pan?.momentum, undefined, 0),
    zoom: glide('zoom', options.zoom?.momentum, options.zoom?.snap, 0),
    rotate: glide('rotate', options.rotate?.momentum, options.rotate?.snap, 360),
    pitch: glide('pitch', options.pitch?.momentum, options.pitch?.snap, 0),
    haptics: interval('rotate.haptics', options.rotate?.haptics, 360),
  };
}

/**
 * The momentum of a zoom, rotation, or pitch released at `velocity` units per
 * second, or not moving if undefined, and its snap if `snaps`.
 */
export function anchoredMomentum(glide: Glide, velocity: number | undefined, snaps: boolean,
  anchor: ScreenPoint | undefined): AnchoredMomentum {
  const snap = glide.snap;
  return {
    velocity: glide.momentum.enabled === false ? undefined : velocity,
    anchor: anchor,
    decay: decay(glide.momentum),
    snap: snaps && snap.interval > 0 ?
      { spacing: snap.interval, offset: snap.offset, tolerance: snap.tolerance, durationMs: snap.durationMs } : undefined,
  };
}

/**
 * The glide of a pan released at `x`, `y` vp/s on a display of `density` px
 * per vp. By default it glides as ArkUI's `Scroll` and `List` fling
 * (ace_engine's `scrollable.cpp`, OpenHarmony 7.0, and the SDK's `friction()`
 * and `flingSpeedLimit()`): the release speed times a gain decays at 4.2 times
 * the friction per second, from a release of at least 240 px/s, down to
 * 120 px/s, starting at most 9000 vp/s. A release under 3000 px/s takes a gain of 1.2 and
 * friction 1, and a faster one 1.5 and the default friction, 0.75. A half-life
 * that the app gives replaces the gain and the friction.
 */
export function panMomentum(glide: Glide, x: number, y: number, density: number): PanMomentum | undefined {
  const momentum = glide.momentum;
  if (momentum.enabled === false) {
    return undefined;
  }
  const slow = Math.hypot(x, y) * density < 3000;
  const gain = momentum.halfLifeMs !== undefined ? 1 : slow ? 1.2 : 1.5;
  const result = decay(momentum);
  result.halfLifeMs = momentum.halfLifeMs ?? Math.LN2 / (4.2 * (slow ? 1 : 0.75)) * 1000;
  // The minimum is the release's, before the gain.
  result.minSpeed = (momentum.minSpeed ?? 240 / density) * gain;
  result.stopSpeed = momentum.stopSpeed ?? 120 / density;
  result.maxSpeed = momentum.maxSpeed ?? 9000;
  return { velocity: { x: x * gain, y: y * gain }, decay: result };
}

// The settings of `momentum` that the app gave, which FFI takes as its decay;
// FFI's defaults fill in the rest.
function decay(momentum: MomentumOptions): MomentumDecay {
  return {
    halfLifeMs: momentum.halfLifeMs,
    minSpeed: momentum.minSpeed,
    stopSpeed: momentum.stopSpeed,
    maxSpeed: momentum.maxSpeed,
    maxDistance: momentum.maxDistance,
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
