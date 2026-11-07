// Limits on where a map's camera goes.

import { LatLngBounds } from '../geometry/Geometry';

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
