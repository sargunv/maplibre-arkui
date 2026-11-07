// What a map's click handlers receive.

import { LatLng, ScreenPoint } from './Geometry';

/** Where the user clicked a map. The map creates it; fields may be added in later releases. */
export interface MapClickEvent {
  /**
   * The coordinate under the click. Its longitude isn't wrapped to -180 to
   * 180, so it names the copy of the world that the click is in, as
   * `Viewport.unproject()` does.
   */
  coordinate: LatLng;
  /** The click's position on the map, as `MapController.queryRenderedFeatures()` takes it. */
  point: ScreenPoint;
}
