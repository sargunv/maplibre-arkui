/**
 * What moved the camera. Values may be added in later releases; give a `switch`
 * over it a `default` branch.
 */
export enum CameraMoveReason {
  /** The user's input on the map. */
  GESTURE,
  /**
   * Anything else, such as a `MapController` method, a control like
   * `ZoomButtons`, or following the user's location.
   */
  PROGRAMMATIC,
}
