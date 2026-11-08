/**
 * A direction that the map turns to point up while it follows the user's
 * location. Values may be added in later releases; give a `switch` over it a
 * `default` branch.
 */
export enum FollowBearing {
  /**
   * The direction of travel, while the location has one: while its `speed` is
   * above 0.
   */
  COURSE,
  /**
   * The direction that the device faces, from the map's `userHeading`, while
   * it has one.
   */
  HEADING,
}

/** Options for `MapController.followUserLocation()`. */
export interface FollowUserLocationOptions {
  /**
   * The zoom for the first move to the location. Keeps the current zoom by
   * default.
   */
  zoom?: number;
  /**
   * The direction that the map turns to point up. Turning stops when the user
   * or the app turns the map. By default, the camera keeps its bearing.
   */
  bearing?: FollowBearing;
}
