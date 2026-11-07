// After MapLibre Compose's BearingHapticDetector: a notch ticks as the bearing
// comes within 1° of it or crosses it, and again only after the bearing has
// gone 2° away. Ticks come at most once in 50 ms.
const NOTCH_CAPTURE = 1;
const NOTCH_REARM = 2;
const NOTCH_MIN_MS = 50;

// The haptic notches of one rotation by the pointer, after MapLibre Compose's
// BearingHapticDetector. A notch that the rotation starts at is silent until
// the bearing leaves it.
export class BearingNotches {
  private readonly bearings: number[];
  private readonly armed: boolean[];
  private bearing: number;
  private lastTick: number = -Infinity;

  constructor(bearings: number[], bearing: number) {
    this.bearings = bearings;
    this.bearing = bearing;
    this.armed = bearings.map((notch: number) => Math.abs(wrap(notch - bearing)) > NOTCH_CAPTURE);
  }

  // Turns by `degrees` at `time`, and returns whether that reached a notch. A
  // tick too soon after the last one is dropped, not delayed.
  turn(degrees: number, time: number): boolean {
    const from = this.bearing;
    const to = from + degrees;
    this.bearing = to;
    if (degrees === 0) {
      return false;
    }
    let reached = false;
    for (let i = 0; i < this.bearings.length; i++) {
      const ahead = wrap(this.bearings[i] - from);
      if (this.armed[i] && ahead >= Math.min(0, degrees) - NOTCH_CAPTURE &&
        ahead <= Math.max(0, degrees) + NOTCH_CAPTURE) {
        reached = true;
        this.armed[i] = false;
      }
      if (Math.abs(wrap(this.bearings[i] - to)) > NOTCH_REARM) {
        this.armed[i] = true;
      }
    }
    if (!reached || time - this.lastTick < NOTCH_MIN_MS) {
      return false;
    }
    this.lastTick = time;
    return true;
  }
}

// An angle in degrees, wrapped to [-180, 180).
export function wrap(degrees: number): number {
  return (((degrees + 180) % 360) + 360) % 360 - 180;
}
