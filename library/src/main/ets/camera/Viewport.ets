// What a map shows in one frame, and the conversions between its screen
// points and coordinates.

import { LatLng, ScreenPoint } from '../geometry/Geometry';
import { CameraPosition } from './CameraPosition';

/**
 * One frame that a map drew: its camera and size, and the conversions between
 * its screen points and coordinates. `MapController.viewport` holds the
 * latest. The map creates it; members may be added in later releases.
 *
 * Each member answers for the frame that it came with, also after later
 * frames replace it. Screen points are in vp from the map's top-left corner,
 * and can be outside the map.
 */
export interface Viewport {
  /**
   * The camera of the frame. Its `padding` is the app's, as
   * `MapController.camera` reports it, without the map's `viewportInsets`.
   */
  readonly camera: CameraPosition;
  /** The size of the map, in vp. */
  readonly size: Size;

  /**
   * Where `coordinate` is on the map, in the copy of the world nearest the
   * camera's center.
   */
  project(coordinate: LatLng): ScreenPoint;

  /**
   * The coordinate at `point`. Its longitude isn't wrapped to -180 to 180, so
   * it names the copy of the world that the point is in.
   */
  unproject(point: ScreenPoint): LatLng;

  /** How many meters one vp covers at `latitude`, at the frame's zoom, ignoring pitch. */
  metersPerVpAtLatitude(latitude: number): number;
}
