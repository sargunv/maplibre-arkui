// Conversions between the library's camera types and FFI's, and the checks
// that a camera, a camera move, a fit, and camera bounds pass before they
// reach FFI. FfiGeometry converts and checks the positions in them.

import {
  BoundOptions,
  Camera as FfiCamera,
  CameraOptions as FfiCameraOptions,
  CameraUpdateMode,
} from '@maplibre/native-ffi';

import { LatLng } from '../../geometry/Geometry';
import { checkBounds, checkLatLng, toLatLng } from '../../geometry/internal/FfiGeometry';
import { CameraBoundsOptions } from '../../map/CameraBoundsOptions';
import { CameraPosition, CameraUpdate } from '../CameraPosition';
import { CameraTransitionMode, CameraTransitionOptions, FitCameraOptions } from '../CameraTransitionOptions';
import { checkPadding, Insets, PaddingMetrics } from './Insets';

// The limits as FFI takes them, with the defaults filled in, which are those
// of a new FFI map. Throws for a value that isn't finite, a minimum above its
// maximum, or bounds that `fitCameraToBounds()` would throw for.
export function toBoundOptions(options: CameraBoundsOptions): BoundOptions {
  const limits: BoundOptions = {
    bounds: options.bounds,
    unbounded: options.bounds === undefined,
    minZoom: options.minZoom ?? 0,
    maxZoom: options.maxZoom ?? 22,
    minPitch: options.minPitch ?? 0,
    maxPitch: options.maxPitch ?? 60,
  };
  if (options.bounds !== undefined) {
    checkBounds(options.bounds);
  }
  checkRange('zoom', limits.minZoom!, limits.maxZoom!);
  checkRange('pitch', limits.minPitch!, limits.maxPitch!);
  return limits;
}

function checkRange(what: string, min: number, max: number): void {
  if (!Number.isFinite(min) || !Number.isFinite(max) || min > max) {
    throw new Error(`cameraBounds needs a finite ${what} range whose minimum isn't above its maximum: ` +
      `${min} to ${max}`);
  }
}

// How long an ease takes when the app doesn't say.
const EASE_MS = 300;

// The map's camera as the app sees it, with the app's `padding` in place of
// the map's.
export function toCameraPosition(camera: FfiCamera, padding: Insets): CameraPosition {
  return {
    center: toLatLng(camera.center),
    zoom: camera.zoom,
    bearing: camera.bearing,
    pitch: camera.pitch,
    padding: { top: padding.top, left: padding.left, bottom: padding.bottom, right: padding.right },
  };
}

// A camera update whose fields are checked, with its padding as lengths that
// any UI context, or a snapshot's scale, converts to vp.
export interface CheckedCamera {
  center?: LatLng;
  zoom?: number;
  bearing?: number;
  pitch?: number;
  padding?: PaddingMetrics;
}

// How a checked camera move travels: FFI's mode, and its duration, if any.
export interface CheckedTransition {
  mode: CameraUpdateMode;
  durationMs?: number;
}

// A fit's checked options, with its paddings as lengths.
export interface CheckedFit {
  transition: CheckedTransition;
  bearing?: number;
  pitch?: number;
  fitPadding?: PaddingMetrics;
  cameraPadding?: PaddingMetrics;
}

function checkNumber(value: number | undefined, what: string): void {
  if (value !== undefined && !Number.isFinite(value)) {
    throw new Error(`${what} must be finite: ${value}`);
  }
}

// A copy of `update`, so the app can change its object later, once each field
// is checked. Throws for the first invalid field.
export function checkCamera(update: CameraUpdate): CheckedCamera {
  if (update.center !== undefined) {
    checkLatLng(update.center, 'The camera center');
  }
  checkNumber(update.zoom, 'The camera zoom');
  checkNumber(update.bearing, 'The camera bearing');
  checkNumber(update.pitch, 'The camera pitch');
  return {
    center: update.center === undefined ? undefined : toLatLng(update.center),
    zoom: update.zoom,
    bearing: update.bearing,
    pitch: update.pitch,
    padding: update.padding === undefined ? undefined : checkPadding(update.padding, 'the camera padding'),
  };
}

// `camera` as FFI takes it, with the map's whole `padding`: the insets around
// the app's.
export function toFfiCamera(camera: CheckedCamera, padding: Insets | undefined): FfiCameraOptions {
  return {
    center: camera.center,
    zoom: camera.zoom,
    bearing: camera.bearing,
    pitch: camera.pitch,
    padding: padding,
  };
}

// The mode and duration of a move. Without a mode, a move jumps; an ease
// without a duration takes EASE_MS, and a fly without one takes FFI's time.
export function checkTransition(options: CameraTransitionOptions | undefined): CheckedTransition {
  const durationMs = options?.durationMs;
  if (durationMs !== undefined && !(Number.isFinite(durationMs) && durationMs >= 0)) {
    throw new Error(`A camera transition's durationMs must be finite and at least 0: ${durationMs}`);
  }
  switch (options?.mode ?? CameraTransitionMode.JUMP) {
    case CameraTransitionMode.EASE:
      return { mode: CameraUpdateMode.ease, durationMs: durationMs ?? EASE_MS };
    case CameraTransitionMode.FLY:
      return { mode: CameraUpdateMode.fly, durationMs: durationMs };
    default:
      return { mode: CameraUpdateMode.jump };
  }
}

export function checkFit(options: FitCameraOptions | undefined): CheckedFit {
  checkNumber(options?.bearing, 'The fit\'s bearing');
  checkNumber(options?.pitch, 'The fit\'s pitch');
  const fitPadding = options?.fitPadding;
  const cameraPadding = options?.cameraPadding;
  return {
    transition: checkTransition(options),
    bearing: options?.bearing,
    pitch: options?.pitch,
    fitPadding: fitPadding === undefined ? undefined : checkPadding(fitPadding, 'the fit padding'),
    cameraPadding: cameraPadding === undefined ? undefined : checkPadding(cameraPadding, 'the camera padding'),
  };
}
