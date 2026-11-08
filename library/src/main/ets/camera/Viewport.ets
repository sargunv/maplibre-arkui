// What a map shows in one frame, and the conversions between its screen
// points and coordinates.

import { LatLng, ScreenPoint } from '../geometry/Geometry';
import { CameraPosition } from './CameraPosition';

/**
 * A frame that the map drew: its camera, its size, and conversions between
 * screen points and coordinates. Screen points are in vp from the map's
 * top-left corner. Members may be added in later releases.
 */
export interface Viewport {
  /** The camera of the frame. */
  readonly camera: CameraPosition;
  /** The size of the map, in vp. */
  readonly size: Size;

  /** The screen point of `coordinate`, in the copy of the world nearest the camera's center. */
  project(coordinate: LatLng): ScreenPoint;

  /** The coordinate at `point`. The longitude isn't wrapped to -180 to 180. */
  unproject(point: ScreenPoint): LatLng;

  /** How many meters one vp covers at `latitude` and the frame's zoom, ignoring pitch. */
  metersPerVpAtLatitude(latitude: number): number;
}
