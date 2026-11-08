// After MapLibre Compose's BearingHapticDetector: a notch ticks as the bearing
// comes within 1° of it or crosses it, and again only after the bearing has
// gone 2° away. Ticks come at most once in 50 ms.
const NOTCH_CAPTURE = 1;
const NOTCH_REARM = 2;
const NOTCH_MIN_MS = 50;

/** Bearings every `interval` degrees from `offset` through each turn. */
export interface Bearings {
  interval: number;
  offset: number;
}

// The haptic notches of one rotation by the pointer. A notch that the rotation
// starts at is silent until the bearing leaves it.
export class BearingNotches {
  private readonly notches: Bearings;
  private bearing: number;
  // The notch that ticked last, or that the rotation started at, until the
  // bearing leaves it.
  private silent: number | undefined;
  private lastTick: number = -Infinity;

  constructor(notches: Bearings, bearing: number) {
    this.notches = notches;
    this.bearing = bearing;
    this.silent = this.reached(bearing, bearing);
  }

  // Turns by `degrees` at `time`, and returns whether that reached a notch. A
  // tick too soon after the last one is dropped, not delayed.
  turn(degrees: number, time: number): boolean {
    const from = this.bearing;
    const to = from + degrees;
    this.bearing = to;
    const notch = this.reached(from, to);
    const reached = notch !== undefined && notch !== this.silent;
    if (reached) {
      this.silent = notch;
    }
    if (this.silent !== undefined && Math.abs(to - this.silent) > NOTCH_REARM) {
      this.silent = undefined;
    }
    if (!reached || time - this.lastTick < NOTCH_MIN_MS) {
      return false;
    }
    this.lastTick = time;
    return true;
  }

  // The last notch that a turn from `from` to `to` reaches, if any: the one
  // at or before the edge of its capture past `to`.
  private reached(from: number, to: number): number | undefined {
    const forward = to >= from;
    const edge = (forward ? to + NOTCH_CAPTURE : to - NOTCH_CAPTURE) - this.notches.offset;
    const turn = Math.floor(edge / 360) * 360;
    const steps = (edge - turn) / this.notches.interval;
    const notch = this.notches.offset +
      Math.min(turn + (forward ? Math.floor(steps) : Math.ceil(steps)) * this.notches.interval, turn + 360);
    return notch >= Math.min(from, to) - NOTCH_CAPTURE && notch <= Math.max(from, to) + NOTCH_CAPTURE ? notch :
      undefined;
  }
}

// An angle in degrees, wrapped to [-180, 180).
export function wrap(degrees: number): number {
  return (((degrees + 180) % 360) + 360) % 360 - 180;
}
