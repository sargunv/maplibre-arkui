// The library's positions on the earth and on the screen.

/** A geographic position in degrees. */
export interface LatLng {
  /** Degrees north of the equator, from -90 to 90. */
  latitude: number;
  /**
   * Degrees east of the prime meridian. Any finite value; values past ±180
   * name another copy of the world.
   */
  longitude: number;
}

/**
 * A rectangle of positions. To cross the antimeridian, give
 * `northeast.longitude` past 180 (east is always greater than west).
 */
export interface LatLngBounds {
  /** The corner with the lowest latitude and longitude. */
  southwest: LatLng;
  /** The corner with the highest latitude and longitude. */
  northeast: LatLng;
}

/**
 * A position on a map, in vp from its top-left corner, as an ArkUI
 * `ClickEvent`'s `x` and `y` are. It can be outside the map.
 */
export interface ScreenPoint {
  /** The distance from the map's left edge, in vp. */
  x: number;
  /** The distance from the map's top edge, in vp. */
  y: number;
}
