/**
 * How a camera move travels. Values may be added in later releases; give a
 * `switch` over it a `default` branch.
 */
export enum CameraTransitionMode {
  /** Moves the camera at once. */
  JUMP,
  /** Animates the camera along a straight path to the target. */
  EASE,
  /** Zooms out, travels to the target, and zooms back in. */
  FLY,
}

/** How a camera move travels and how long it takes. */
export interface CameraTransitionOptions {
  /** Whether the camera jumps, eases, or flies. Jumps by default. */
  mode?: CameraTransitionMode;
  /**
   * How long an ease or a fly takes. Must be finite and at least 0. By default,
   * an ease takes 300 ms and a fly takes longer for longer distances.
   */
  durationMs?: number;
}

/**
 * How the fit methods of `MapController`, such as `fitCameraToBounds()`, move
 * the camera.
 */
export interface FitCameraOptions extends CameraTransitionOptions {
  /** The bearing after the fit, in degrees. Keeps the current bearing by default. */
  bearing?: number;
  /** The pitch after the fit, in degrees. Keeps the current pitch by default. */
  pitch?: number;
  /**
   * Space around what the camera fits, for this fit only. None by default.
   * Each side is at least 0, not a percentage.
   */
  fitPadding?: Padding | LocalizedPadding;
  /**
   * The camera's padding after the fit. Keeps the current padding by default.
   * Each side is at least 0, not a percentage.
   */
  cameraPadding?: Padding | LocalizedPadding;
}
