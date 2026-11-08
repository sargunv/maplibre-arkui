// The library's camera: the fields that a move changes, and where it rests.

import { LatLng } from '../geometry/Geometry';

/** A change to the camera. Fields left out keep their current values. */
export interface CameraUpdate {
  /** The coordinate at the center of the padded area of the map. */
  center?: LatLng;
  /**
   * The zoom level. At zoom 0 the world is 512 vp wide, and each level doubles
   * the scale.
   */
  zoom?: number;
  /**
   * The compass direction at the top of the map, in degrees clockwise from
   * north.
   */
  bearing?: number;
  /** The tilt toward the horizon, in degrees. 0 looks straight down. */
  pitch?: number;
  /**
   * Space at the edges of the map, inside the map's `viewportInsets`, that the
   * camera centers away from. Each side is at least 0, not a percentage, and 0
   * when left out.
   */
  padding?: Padding | LocalizedPadding;
}

/** Where the camera is: a `CameraUpdate` with every field set. */
export interface CameraPosition extends CameraUpdate {
  /** The coordinate at the center of the padded area of the map. */
  center: LatLng;
  /** The zoom level. */
  zoom: number;
  /**
   * The compass direction at the top of the map, in degrees clockwise from
   * north.
   */
  bearing: number;
  /** The tilt toward the horizon, in degrees. 0 looks straight down. */
  pitch: number;
  /** The camera's padding, in vp, without the map's `viewportInsets`. */
  padding: Padding;
}
