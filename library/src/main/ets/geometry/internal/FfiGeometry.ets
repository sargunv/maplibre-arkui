// Conversions between the library's positions and FFI's, and the checks that
// positions and geometries pass before they reach FFI.
//
// Values pass from the library to FFI as they are where the linter allows it:
// its structural check skips FFI's declared types, so a library `LatLng` is an
// FFI `LatLng`. Only FFI-to-library conversions copy fields, so the app gets
// objects of the library's types: a camera, which leaves out the insets and
// FFI's other fields, and projection results.

import { LatLng as FfiLatLng, ScreenPoint as FfiScreenPoint } from '@maplibre/native-ffi';

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
} from '../GeoJson';
import { LatLng, LatLngBounds, ScreenPoint } from '../Geometry';

export function toLatLng(coordinate: FfiLatLng): LatLng {
  return { latitude: coordinate.latitude, longitude: coordinate.longitude };
}

export function toScreenPoint(point: FfiScreenPoint): ScreenPoint {
  return { x: point.x, y: point.y };
}

export function checkLatLng(coordinate: LatLng, what: string): void {
  if (!Number.isFinite(coordinate.latitude) || coordinate.latitude < -90 || coordinate.latitude > 90 ||
    !Number.isFinite(coordinate.longitude)) {
    throw new Error(`${what} must have a finite latitude from -90 to 90 and a finite longitude: ` +
      `${coordinate.latitude}, ${coordinate.longitude}`);
  }
}

// Each check returns a copy of what it checked, so a move that waits for a map
// uses the values the app passed, even if the app changes them meanwhile.
export function checkBounds(input: LatLngBounds): LatLngBounds {
  const bounds: LatLngBounds = { southwest: copyLatLng(input.southwest), northeast: copyLatLng(input.northeast) };
  checkLatLng(bounds.southwest, 'The bounds\' southwest');
  checkLatLng(bounds.northeast, 'The bounds\' northeast');
  if (bounds.southwest.latitude > bounds.northeast.latitude ||
    bounds.southwest.longitude > bounds.northeast.longitude) {
    throw new Error('The bounds\' southwest must be south and west of its northeast: ' +
      `${bounds.southwest.latitude}, ${bounds.southwest.longitude} and ` +
      `${bounds.northeast.latitude}, ${bounds.northeast.longitude}`);
  }
  return bounds;
}

export function checkCoordinates(input: LatLng[]): LatLng[] {
  const coordinates = input.map(copyLatLng);
  if (coordinates.length === 0) {
    throw new Error('The coordinates to fit must not be empty');
  }
  coordinates.forEach((coordinate: LatLng) => checkLatLng(coordinate, 'Each coordinate to fit'));
  return coordinates;
}

function copyLatLng(coordinate: LatLng): LatLng {
  return { latitude: coordinate.latitude, longitude: coordinate.longitude };
}

// Throws unless `geometry` has a position, each with a finite longitude and a
// latitude from -90 to 90.
export function checkGeometry(input: GeoJsonGeometry): GeoJsonGeometry {
  const geometry = JSON.parse(JSON.stringify(input)) as GeoJsonGeometry;
  const positions: GeoJsonPosition[] = [];
  collectPositions(geometry, positions);
  if (positions.length === 0) {
    throw new Error(`The geometry to fit must have a position: ${JSON.stringify(geometry)}`);
  }
  for (const position of positions) {
    if (position.length < 2) {
      throw new Error(`Each position of the geometry to fit must have a longitude and a latitude: [${position}]`);
    }
    checkLatLng({ latitude: position[1], longitude: position[0] }, 'Each position of the geometry to fit');
  }
  return geometry;
}

function append(positions: GeoJsonPosition[], into: GeoJsonPosition[]): void {
  for (const position of positions) {
    into.push(position);
  }
}

// Appends the positions of `geometry` to `into`, so a geometry of many parts
// takes time in proportion to its positions.
function collectPositions(geometry: GeoJsonGeometry, into: GeoJsonPosition[]): void {
  switch (geometry.type) {
    case 'Point':
      into.push((geometry as GeoJsonPoint).coordinates);
      return;
    case 'MultiPoint':
      append((geometry as GeoJsonMultiPoint).coordinates, into);
      return;
    case 'LineString':
      append((geometry as GeoJsonLineString).coordinates, into);
      return;
    case 'MultiLineString':
      (geometry as GeoJsonMultiLineString).coordinates.forEach((line: GeoJsonPosition[]) => append(line, into));
      return;
    case 'Polygon':
      (geometry as GeoJsonPolygon).coordinates.forEach((ring: GeoJsonPosition[]) => append(ring, into));
      return;
    case 'MultiPolygon':
      (geometry as GeoJsonMultiPolygon).coordinates.forEach((polygon: GeoJsonPosition[][]) =>
        polygon.forEach((ring: GeoJsonPosition[]) => append(ring, into)));
      return;
    case 'GeometryCollection':
      (geometry as GeoJsonGeometryCollection).geometries.forEach((part: GeoJsonGeometry) =>
        collectPositions(part, into));
      return;
    default:
      throw new Error(`Unknown geometry type: ${JSON.stringify(geometry)}`);
  }
}
