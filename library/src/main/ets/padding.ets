// The camera's padding with and without a map's viewport insets. The FFI map's
// padding is the insets plus the app's camera padding; the controller reads
// and takes the app's alone, so the insets never show in a camera that the app
// reads or saves.

import { Camera as CameraPosition, CameraOptions, EdgeInsets, LatLng } from '@maplibre/native-ffi';

export const NO_INSETS: EdgeInsets = { top: 0, left: 0, bottom: 0, right: 0 };

export function addInsets(a: EdgeInsets, b: EdgeInsets): EdgeInsets {
  return { top: a.top + b.top, left: a.left + b.left, bottom: a.bottom + b.bottom, right: a.right + b.right };
}

// FFI rejects negative padding, and padding less insets can come out a little
// below 0.
export function subtractInsets(padding: EdgeInsets, insets: EdgeInsets): EdgeInsets {
  return {
    top: Math.max(0, padding.top - insets.top),
    left: Math.max(0, padding.left - insets.left),
    bottom: Math.max(0, padding.bottom - insets.bottom),
    right: Math.max(0, padding.right - insets.right),
  };
}

export function sameInsets(a: EdgeInsets, b: EdgeInsets): boolean {
  return a.top === b.top && a.left === b.left && a.bottom === b.bottom && a.right === b.right;
}

// The map's camera as the app sees it, without `insets` in its padding.
export function withoutInsets(camera: CameraPosition, insets: EdgeInsets): CameraPosition {
  return {
    center: camera.center,
    centerAltitude: camera.centerAltitude,
    padding: subtractInsets(camera.padding, insets),
    zoom: camera.zoom,
    bearing: camera.bearing,
    pitch: camera.pitch,
    roll: camera.roll,
    fieldOfView: camera.fieldOfView,
  };
}

// `options` with `padding`, and with `center` when it's given.
export function withPadding(options: CameraOptions, padding: EdgeInsets | undefined,
  center?: LatLng): CameraOptions {
  return {
    center: center ?? options.center,
    centerAltitude: options.centerAltitude,
    padding: padding,
    anchor: options.anchor,
    zoom: options.zoom,
    bearing: options.bearing,
    pitch: options.pitch,
    roll: options.roll,
    fieldOfView: options.fieldOfView,
  };
}
