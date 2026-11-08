// The library's positions on the earth and on the screen.

/** A geographic position in degrees. */
export interface LatLng {
  /** Degrees north of the equator, from -90 to 90. */
  latitude: number;
  /**
   * Degrees east of the prime meridian. Any finite value; values past ±180
   * are on a repeated copy of the world.
   */
  longitude: number;
}

/**
 * A geographic rectangle. The east longitude is always greater than the west,
 * so a rectangle that crosses the antimeridian has `northeast.longitude` past
 * 180.
 */
export interface LatLngBounds {
  /** The corner with the lowest latitude and longitude. */
  southwest: LatLng;
  /** The corner with the highest latitude and longitude. */
  northeast: LatLng;
}

/** A position on a map, in vp from its top-left corner. It can be outside the map. */
export interface ScreenPoint {
  /** The distance from the map's left edge, in vp. */
  x: number;
  /** The distance from the map's top edge, in vp. */
  y: number;
}
