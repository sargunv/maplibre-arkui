// GeoJSON types, https://datatracker.ietf.org/doc/html/rfc7946, so ArkTS apps
// can write GeoJSON as object literals: strict ArkTS accepts an object literal
// only for a declared type. FFI takes GeoJSON as a plain object, and returns it
// from feature queries, so these types only describe it; nothing converts it.

/**
 * A longitude and a latitude, in degrees and in that order, and an optional
 * altitude in meters.
 */
export type GeoJsonPosition = number[];

/** A single position. */
export interface GeoJsonPoint {
  /** The type tag. Closed. */
  type: 'Point';
  /** The point's position. */
  coordinates: GeoJsonPosition;
  /** The box around the geometry: the lowest value on each axis, then the highest. */
  bbox?: number[];
}

/** Several positions. */
export interface GeoJsonMultiPoint {
  /** The type tag. Closed. */
  type: 'MultiPoint';
  /** The positions. */
  coordinates: GeoJsonPosition[];
  /** The box around the geometry: the lowest value on each axis, then the highest. */
  bbox?: number[];
}

/** A line through two or more positions. */
export interface GeoJsonLineString {
  /** The type tag. Closed. */
  type: 'LineString';
  /** The positions that the line goes through, in order. */
  coordinates: GeoJsonPosition[];
  /** The box around the geometry: the lowest value on each axis, then the highest. */
  bbox?: number[];
}

/** Several lines. */
export interface GeoJsonMultiLineString {
  /** The type tag. Closed. */
  type: 'MultiLineString';
  /** The lines, each as a `GeoJsonLineString`'s coordinates. */
  coordinates: GeoJsonPosition[][];
  /** The box around the geometry: the lowest value on each axis, then the highest. */
  bbox?: number[];
}

/**
 * An area: its outer ring, then any holes, each ring closed by repeating its
 * first position.
 */
export interface GeoJsonPolygon {
  /** The type tag. Closed. */
  type: 'Polygon';
  /** The rings: the outer ring, then any holes. */
  coordinates: GeoJsonPosition[][];
  /** The box around the geometry: the lowest value on each axis, then the highest. */
  bbox?: number[];
}

/** Several areas. */
export interface GeoJsonMultiPolygon {
  /** The type tag. Closed. */
  type: 'MultiPolygon';
  /** The areas, each as a `GeoJsonPolygon`'s coordinates. */
  coordinates: GeoJsonPosition[][][];
  /** The box around the geometry: the lowest value on each axis, then the highest. */
  bbox?: number[];
}

/** Several geometries of any type. */
export interface GeoJsonGeometryCollection {
  /** The type tag. Closed. */
  type: 'GeometryCollection';
  /** The geometries. */
  geometries: GeoJsonGeometry[];
  /** The box around the geometry: the lowest value on each axis, then the highest. */
  bbox?: number[];
}

/** Any GeoJSON geometry, told apart by its `type`. Closed. */
export type GeoJsonGeometry = GeoJsonPoint | GeoJsonMultiPoint | GeoJsonLineString | GeoJsonMultiLineString |
  GeoJsonPolygon | GeoJsonMultiPolygon | GeoJsonGeometryCollection;

/** A geometry with properties, and an optional ID. */
export interface GeoJsonFeature {
  /** The type tag. Closed. */
  type: 'Feature';
  /** The feature's ID. The map compares IDs as text, so 7 and '7' are one ID. */
  id?: number | string;
  /** The feature's geometry, or `null` for a feature without one. */
  geometry: GeoJsonGeometry | null;
  /** The feature's properties, or `null` for a feature without any. */
  properties: Record<string, Object | null> | null;
  /** The box around the feature: the lowest value on each axis, then the highest. */
  bbox?: number[];
}

/** A collection of features, as a GeoJSON source usually takes. */
export interface GeoJsonFeatureCollection {
  /** The type tag. Closed. */
  type: 'FeatureCollection';
  /** The features. */
  features: GeoJsonFeature[];
  /** The box around the features: the lowest value on each axis, then the highest. */
  bbox?: number[];
}

/** Any GeoJSON object, told apart by its `type`. Closed. */
export type GeoJsonObject = GeoJsonGeometry | GeoJsonFeature | GeoJsonFeatureCollection;
