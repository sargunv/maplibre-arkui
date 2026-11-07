import { CameraDelta, ScreenPoint } from '@maplibre/native-ffi';

// Momentum on release.
export const VELOCITY_WINDOW_MS = 100;
const FLING_MIN_SPEED = 250;
const FLING_STEP = 16;
const TRANSFORM_MOMENTUM_MS = 600;
const MAX_ZOOM_MOMENTUM = 2.5;

/**
 * The camera's motion after a release, eased out over its duration. Pan alone
 * slows as a fling; zoom and rotation slow faster, and a pan with them follows
 * their curve so neither runs ahead. From MapLibre Compose's GestureMath.
 */
export class Momentum {
  readonly offsetX: number;
  readonly offsetY: number;
  readonly zoomLevels: number;
  readonly bearing: number;
  readonly anchor: ScreenPoint | undefined;
  readonly durationMs: number;
  readonly power: number;
  done: boolean = false;
  private progress: number = 0;

  constructor(offsetX: number, offsetY: number, zoomLevels: number, bearing: number,
    anchor: ScreenPoint | undefined, durationMs: number, power: number) {
    this.offsetX = offsetX;
    this.offsetY = offsetY;
    this.zoomLevels = zoomLevels;
    this.bearing = bearing;
    this.anchor = anchor;
    this.durationMs = durationMs;
    this.power = power;
  }

  /**
   * Plans the momentum of a release at these velocities, in vp, zoom levels,
   * and degrees of bearing per second, or none when it's too slow.
   */
  static plan(panX: number, panY: number, zoom: number, bearing: number,
    anchor: ScreenPoint | undefined): Momentum | undefined {
    const speed = Math.hypot(panX, panY);
    let offsetX = 0;
    let offsetY = 0;
    let panMs = 0;
    if (speed >= FLING_MIN_SPEED) {
      panMs = speed / 10.5 + 150;
      offsetX = panX * panMs * 0.28 / 1000;
      offsetY = panY * panMs * 0.28 / 1000;
    }
    // Quartic easing travels a quarter of the initial speed times the duration.
    const seconds = TRANSFORM_MOMENTUM_MS / 1000;
    const levels = Math.max(-MAX_ZOOM_MOMENTUM, Math.min(MAX_ZOOM_MOMENTUM, zoom * seconds / 4));
    const degrees = bearing * seconds / 4;
    const transform = Math.abs(levels) >= 0.01 || Math.abs(degrees) >= 0.1;
    if (!transform) {
      return panMs > 0 ? new Momentum(offsetX, offsetY, 0, 0, anchor, panMs, 2) : undefined;
    }
    // Keep the pan's initial speed on the quartic curve without adding travel.
    const scale = panMs > 0 ? Math.min(1, TRANSFORM_MOMENTUM_MS / panMs * 2 / 4) : 0;
    return new Momentum(offsetX * scale, offsetY * scale, levels, degrees, anchor,
      TRANSFORM_MOMENTUM_MS, 4);
  }

  /**
   * The camera changes from the last call to `elapsedMs` after the release. A
   * long frame's pan comes in steps of at most 16 vp, so a pitched map doesn't
   * project one large offset.
   */
  advance(elapsedMs: number): CameraDelta[] {
    const t = Math.min(1, Math.max(0, elapsedMs / this.durationMs));
    const progress = 1 - Math.pow(1 - t, this.power);
    const fraction = progress - this.progress;
    this.progress = progress;
    this.done = t >= 1;
    const deltas: CameraDelta[] = [];
    if (this.zoomLevels !== 0 || this.bearing !== 0) {
      const delta: CameraDelta = { anchor: this.anchor };
      if (this.zoomLevels !== 0) {
        delta.scale = Math.pow(2, this.zoomLevels * fraction);
      }
      if (this.bearing !== 0) {
        delta.bearing = this.bearing * fraction;
      }
      deltas.push(delta);
    }
    const x = this.offsetX * fraction;
    const y = this.offsetY * fraction;
    const steps = Math.ceil(Math.hypot(x, y) / FLING_STEP);
    for (let i = 0; i < steps; i++) {
      deltas.push({ offset: { x: x / steps, y: y / steps } });
    }
    return deltas;
  }
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
