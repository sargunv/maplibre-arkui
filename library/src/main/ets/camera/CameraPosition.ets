// The library's camera: the fields that a move changes, and where it rests.

import { LatLng } from '../geometry/Geometry';

/** Camera fields to change; fields left out keep their values. */
export interface CameraUpdate {
  /** The position at the middle of the part of the map that the padding leaves. */
  center?: LatLng;
  /** The zoom level. Each level doubles the map's scale; 0 shows the whole world in 512 vp. */
  zoom?: number;
  /** The direction at the top of the map, in degrees clockwise from north. */
  bearing?: number;
  /** The tilt toward the horizon, in degrees. 0 looks straight down. */
  pitch?: number;
  /**
   * The space around the part of the map that the camera centers in, inside
   * the map's `viewportInsets`. Each side is a length of at least 0, not a
   * percentage; a side left out is 0. A `LocalizedPadding`'s `start` and
   * `end` follow the app's language, not an ancestor's `.direction()`.
   */
  padding?: Padding | LocalizedPadding;
}

/**
 * Where the camera is: a complete `CameraUpdate`, so a reported or JSON-parsed
 * camera passes back as it is. Only a `CameraPosition`, not every
 * `CameraUpdate`, survives `JSON.stringify()` and `JSON.parse()`.
 */
export interface CameraPosition extends CameraUpdate {
  /** The position at the middle of the part of the map that the padding leaves. */
  center: LatLng;
  /** The zoom level. */
  zoom: number;
  /** The direction at the top of the map, in degrees clockwise from north. */
  bearing: number;
  /** The tilt toward the horizon, in degrees. 0 looks straight down. */
  pitch: number;
  /** The app's padding: all four sides are numbers of vp; never includes `viewportInsets`. */
  padding: Padding;
}
