// Limits on where a map's camera goes.

import { BoundOptions } from '@maplibre/native-ffi';

import { checkBounds } from './FfiValues';
import { LatLngBounds } from './Geometry';

/**
 * Limits on the camera of a `MaplibreMap`: an area that its center stays
 * within, and ranges of zoom and pitch. Each limit left out takes its default,
 * not the map's earlier limit.
 */
export interface CameraBoundsOptions {
  /** The area that the camera's center stays within. The whole world by default. */
  bounds?: LatLngBounds;
  /** The lowest zoom. 0 by default. */
  minZoom?: number;
  /** The highest zoom. 22 by default. */
  maxZoom?: number;
  /** The lowest pitch, in degrees. 0 by default. */
  minPitch?: number;
  /** The highest pitch, in degrees. 60 by default. */
  maxPitch?: number;
}

// The limits as FFI takes them, with the defaults filled in, which are those
// of a new FFI map. Throws for a value that isn't finite, a minimum above its
// maximum, or bounds that `fitCameraToBounds()` would throw for.
export function toBoundOptions(options: CameraBoundsOptions): BoundOptions {
  const limits: BoundOptions = {
    bounds: options.bounds,
    unbounded: options.bounds === undefined,
    minZoom: options.minZoom ?? 0,
    maxZoom: options.maxZoom ?? 22,
    minPitch: options.minPitch ?? 0,
    maxPitch: options.maxPitch ?? 60,
  };
  if (options.bounds !== undefined) {
    checkBounds(options.bounds);
  }
  checkRange('zoom', limits.minZoom!, limits.maxZoom!);
  checkRange('pitch', limits.minPitch!, limits.maxPitch!);
  return limits;
}

function checkRange(what: string, min: number, max: number): void {
  if (!Number.isFinite(min) || !Number.isFinite(max) || min > max) {
    throw new Error(`cameraBounds needs a finite ${what} range whose minimum isn't above its maximum: ` +
      `${min} to ${max}`);
  }
}
