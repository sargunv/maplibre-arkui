// The library's camera, and how a camera move travels.

import { LatLng } from './Geometry';

/** Camera fields to change; fields left out keep their values. */
export interface CameraUpdate {
  /** The position at the middle of the part of the map that the padding leaves. */
  center?: LatLng;
  /** The zoom level. Each level doubles the map's scale; 0 shows the whole world in 512 vp. */
  zoom?: number;
  /** The direction at the top of the map, in degrees clockwise from north. */
  bearing?: number;
  /** The tilt toward the horizon, in degrees. 0 looks straight down. */
  pitch?: number;
  /**
   * The space around the part of the map that the camera centers in, inside
   * the map's `viewportInsets`. Each side is a length of at least 0, not a
   * percentage; a side left out is 0.
   */
  padding?: Padding | LocalizedPadding;
}

/**
 * Where the camera is: a complete `CameraUpdate`, so a reported or JSON-parsed
 * camera passes back as it is. Only a `CameraPosition`, not every
 * `CameraUpdate`, survives `JSON.stringify()` and `JSON.parse()`.
 */
export interface CameraPosition extends CameraUpdate {
  /** The position at the middle of the part of the map that the padding leaves. */
  center: LatLng;
  /** The zoom level. */
  zoom: number;
  /** The direction at the top of the map, in degrees clockwise from north. */
  bearing: number;
  /** The tilt toward the horizon, in degrees. 0 looks straight down. */
  pitch: number;
  /** The app's padding: all four sides are numbers of vp; never includes `viewportInsets`. */
  padding: Padding;
}

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
  /** Jumps by default, or eases when `durationMs` is given. */
  mode?: CameraTransitionMode;
  /**
   * How long an ease or a fly takes, in ms, finite and at least 0. An ease
   * takes 300 by default; a fly takes a time that follows from the distance.
   * 0 makes it a jump.
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
   * by default. Each side is a length of at least 0, not a percentage.
   */
  fitPadding?: Padding | LocalizedPadding;
  /**
   * The padding of the camera after the fit, which stays as `updateCamera()`
   * sets it. Keeps the camera's padding by default. Each side is a length of
   * at least 0, not a percentage.
   */
  cameraPadding?: Padding | LocalizedPadding;
}
