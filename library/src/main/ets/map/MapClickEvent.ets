// What a map's click handlers receive.

import { LatLng, ScreenPoint } from '../geometry/Geometry';

/** Where the user clicked the map. Fields may be added in later releases. */
export interface MapClickEvent {
  /** The coordinate under the click. The longitude isn't wrapped to -180 to 180. */
  readonly coordinate: LatLng;
  /** The screen point of the click, in vp from the map's top-left corner. */
  readonly point: ScreenPoint;
}
