/**
 * How a camera move travels. Values may be added in later releases; give a
 * `switch` over it a `default` branch.
 */
export enum CameraTransitionMode {
  /** Moves the camera at once. */
  JUMP,
  /** Animates the camera straight to the target. */
  EASE,
  /** Zooms out, travels to the target, and zooms back in. */
  FLY,
}

/** How a camera move travels, and how long it takes. */
export interface CameraTransitionOptions {
  /** Whether the camera jumps, eases, or flies. Jumps by default. */
  mode?: CameraTransitionMode;
  /**
   * How long an ease or a fly takes, in ms, finite and at least 0. An ease
   * takes 300 by default; a fly takes a time that follows from the distance.
   * A jump ignores it.
   */
  durationMs?: number;
}

/**
 * How `fitCameraToBounds()` and the other fit methods of `MapController`
 * move the camera.
 */
export interface FitCameraOptions extends CameraTransitionOptions {
  /** The bearing of the camera, in degrees. Keeps the camera's by default. */
  bearing?: number;
  /** The pitch of the camera, in degrees. Keeps the camera's by default. */
  pitch?: number;
  /**
   * Space to keep between what the camera fits and the edges of the part of
   * the map that the viewport insets and the camera padding leave. The camera
   * keeps it only for the fit; it doesn't stay in the camera's padding. None
   * by default. Each side is a length of at least 0, not a percentage. A
   * `LocalizedPadding`'s `start` and `end` follow the app's language, not an
   * ancestor's `.direction()`.
   */
  fitPadding?: Padding | LocalizedPadding;
  /**
   * The padding of the camera after the fit, which stays as `updateCamera()`
   * sets it. Keeps the camera's padding by default. Each side is a length of
   * at least 0, not a percentage. A `LocalizedPadding`'s `start` and `end`
   * follow the app's language, not an ancestor's `.direction()`.
   */
  cameraPadding?: Padding | LocalizedPadding;
}
