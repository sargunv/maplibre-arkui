// Conversions between the library's value types and FFI's, and the checks
// that the library's values pass before they reach FFI.
//
// Values pass from the library to FFI as they are where the linter allows it:
// its structural check skips FFI's declared types, so a library `LatLng` is an
// FFI `LatLng`. Only FFI-to-library conversions copy fields, so the app gets
// objects of the library's types: a camera, which leaves out the insets and
// FFI's other fields, and projection results.

import {
  Camera as FfiCamera,
  CameraOptions as FfiCameraOptions,
  CameraUpdateMode,
  LatLng as FfiLatLng,
  ScreenPoint as FfiScreenPoint,
} from '@maplibre/native-ffi';

import {
  CameraPosition,
  CameraTransitionMode,
  CameraTransitionOptions,
  CameraUpdate,
  FitCameraOptions,
} from './CameraPosition';
import {
  GeoJsonGeometry,
  GeoJsonGeometryCollection,
  GeoJsonLineString,
  GeoJsonMultiLineString,
  GeoJsonMultiPoint,
  GeoJsonMultiPolygon,
  GeoJsonPoint,
  GeoJsonPolygon,
  GeoJsonPosition,
} from './GeoJson';
import { LatLng, LatLngBounds, ScreenPoint } from './Geometry';
import { checkPadding, Insets, PaddingMetrics } from './Insets';

// How long an ease takes when the app doesn't say.
const EASE_MS = 300;

export function toLatLng(coordinate: FfiLatLng): LatLng {
  return { latitude: coordinate.latitude, longitude: coordinate.longitude };
}

export function toScreenPoint(point: FfiScreenPoint): ScreenPoint {
  return { x: point.x, y: point.y };
}

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

export function checkLatLng(coordinate: LatLng, what: string): void {
  if (!Number.isFinite(coordinate.latitude) || coordinate.latitude < -90 || coordinate.latitude > 90 ||
    !Number.isFinite(coordinate.longitude)) {
    throw new Error(`${what} must have a finite latitude from -90 to 90 and a finite longitude: ` +
      `${JSON.stringify(coordinate)}`);
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

// The mode and duration of a move. Without a mode, a move with a duration
// eases and one without jumps; a duration of 0 jumps.
export function checkTransition(options: CameraTransitionOptions | undefined): CheckedTransition {
  const durationMs = options?.durationMs;
  if (durationMs !== undefined && !(Number.isFinite(durationMs) && durationMs >= 0)) {
    throw new Error(`A camera transition's durationMs must be finite and at least 0: ${durationMs}`);
  }
  const mode = durationMs === 0 ? CameraTransitionMode.JUMP :
    options?.mode ?? (durationMs === undefined ? CameraTransitionMode.JUMP : CameraTransitionMode.EASE);
  switch (mode) {
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

export function checkBounds(bounds: LatLngBounds): void {
  checkLatLng(bounds.southwest, 'The bounds\' southwest');
  checkLatLng(bounds.northeast, 'The bounds\' northeast');
  if (bounds.southwest.latitude > bounds.northeast.latitude ||
    bounds.southwest.longitude > bounds.northeast.longitude) {
    throw new Error(`The bounds' southwest must be south and west of its northeast: ${JSON.stringify(bounds)}`);
  }
}

export function checkCoordinates(coordinates: LatLng[]): void {
  if (coordinates.length === 0) {
    throw new Error('The coordinates to fit must not be empty');
  }
  coordinates.forEach((coordinate: LatLng) => checkLatLng(coordinate, 'Each coordinate to fit'));
}

// Throws unless `geometry` has a position, each with a finite longitude and a
// latitude from -90 to 90.
export function checkGeometry(geometry: GeoJsonGeometry): void {
  const positions = positionsOf(geometry);
  if (positions.length === 0) {
    throw new Error(`The geometry to fit must have a position: ${JSON.stringify(geometry)}`);
  }
  for (const position of positions) {
    if (position.length < 2) {
      throw new Error(`Each position of the geometry to fit must have a longitude and a latitude: ` +
        `${JSON.stringify(position)}`);
    }
    checkLatLng({ latitude: position[1], longitude: position[0] }, 'Each position of the geometry to fit');
  }
}

function flatten(rings: GeoJsonPosition[][]): GeoJsonPosition[] {
  return rings.reduce((all: GeoJsonPosition[], ring: GeoJsonPosition[]) => all.concat(ring), []);
}

function positionsOf(geometry: GeoJsonGeometry): GeoJsonPosition[] {
  switch (geometry.type) {
    case 'Point':
      return [(geometry as GeoJsonPoint).coordinates];
    case 'MultiPoint':
      return (geometry as GeoJsonMultiPoint).coordinates;
    case 'LineString':
      return (geometry as GeoJsonLineString).coordinates;
    case 'MultiLineString':
      return flatten((geometry as GeoJsonMultiLineString).coordinates);
    case 'Polygon':
      return flatten((geometry as GeoJsonPolygon).coordinates);
    case 'MultiPolygon':
      return flatten((geometry as GeoJsonMultiPolygon).coordinates.map(flatten));
    case 'GeometryCollection':
      return (geometry as GeoJsonGeometryCollection).geometries.reduce(
        (all: GeoJsonPosition[], part: GeoJsonGeometry) => all.concat(positionsOf(part)), []);
    default:
      throw new Error(`Unknown geometry type: ${JSON.stringify(geometry)}`);
  }
}
