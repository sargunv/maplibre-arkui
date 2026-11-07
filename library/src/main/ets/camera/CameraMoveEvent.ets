// What a map's onCameraMoveStart receives, and what moved the camera.

/**
 * What moved the camera. Values may be added in later releases; give a
 * `switch` over it a `default` branch.
 */
export enum CameraMoveReason {
  /** The user's input on the map, as `InteractionOptions` describes it. */
  GESTURE,
  /**
   * Anything else: the controller's methods and the controls that call them,
   * following the user's location, the map's `viewportInsets` and
   * `cameraBounds`, and a map that starts.
   */
  PROGRAMMATIC,
}

/** The camera left rest. The map creates it; fields may be added in later releases. */
export interface CameraMoveEvent {
  /** What moved the camera. */
  reason: CameraMoveReason;
}
