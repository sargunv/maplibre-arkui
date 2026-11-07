/**
 * Which direction `MapController.followUserLocation()` turns the map to point
 * up. Values may be added in later releases; give a `switch` over it a
 * `default` branch.
 */
export enum FollowBearing {
  /** The direction of travel, while the location has one: a `speed` above 0. */
  COURSE,
  /** The map's `userHeading`, the direction that the device faces, while it has one. */
  HEADING,
}

/** How `MapController.followUserLocation()` moves the camera. */
export interface FollowUserLocationOptions {
  /**
   * The zoom that the camera eases to with its first move to the location.
   * Keeps the zoom by default. A zoom by the user or the app before that move
   * takes its place.
   */
  zoom?: number;
  /**
   * The direction that the map turns to point up, which
   * `MapController.followedBearing` reports until the user or the app turns
   * the map. While there is none, and by default, the camera keeps its
   * bearing.
   */
  bearing?: FollowBearing;
}
