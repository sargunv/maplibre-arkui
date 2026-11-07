// GeoJSON types, https://datatracker.ietf.org/doc/html/rfc7946, so ArkTS apps
// can write GeoJSON as object literals: strict ArkTS accepts an object literal
// only for a declared type. FFI takes GeoJSON as a plain object, and returns it
// from feature queries, so these types only describe it; nothing converts it.

/**
 * A longitude and a latitude, in degrees and in that order, and an optional
 * altitude in meters. Closed.
 */
export type GeoJsonPosition = number[];

/** A single position. Closed. */
export interface GeoJsonPoint {
  type: 'Point';
  coordinates: GeoJsonPosition;
  /** The box around the geometry: its lowest positions, then its highest. */
  bbox?: number[];
}

/** Several positions. Closed. */
export interface GeoJsonMultiPoint {
  type: 'MultiPoint';
  coordinates: GeoJsonPosition[];
  /** The box around the geometry: its lowest positions, then its highest. */
  bbox?: number[];
}

/** A line through two or more positions. Closed. */
export interface GeoJsonLineString {
  type: 'LineString';
  coordinates: GeoJsonPosition[];
  /** The box around the geometry: its lowest positions, then its highest. */
  bbox?: number[];
}

/** Several lines. Closed. */
export interface GeoJsonMultiLineString {
  type: 'MultiLineString';
  coordinates: GeoJsonPosition[][];
  /** The box around the geometry: its lowest positions, then its highest. */
  bbox?: number[];
}

/**
 * An area: its outer ring, then any holes, each ring closed by repeating its
 * first position. Closed.
 */
export interface GeoJsonPolygon {
  type: 'Polygon';
  coordinates: GeoJsonPosition[][];
  /** The box around the geometry: its lowest positions, then its highest. */
  bbox?: number[];
}

/** Several areas. Closed. */
export interface GeoJsonMultiPolygon {
  type: 'MultiPolygon';
  coordinates: GeoJsonPosition[][][];
  /** The box around the geometry: its lowest positions, then its highest. */
  bbox?: number[];
}

/** Several geometries of any type. Closed. */
export interface GeoJsonGeometryCollection {
  type: 'GeometryCollection';
  geometries: GeoJsonGeometry[];
  /** The box around the geometry: its lowest positions, then its highest. */
  bbox?: number[];
}

/** Any GeoJSON geometry, told apart by its `type`. Closed. */
export type GeoJsonGeometry = GeoJsonPoint | GeoJsonMultiPoint | GeoJsonLineString | GeoJsonMultiLineString |
  GeoJsonPolygon | GeoJsonMultiPolygon | GeoJsonGeometryCollection;

/** A geometry with properties, and an optional ID. Closed. */
export interface GeoJsonFeature {
  type: 'Feature';
  /** The feature's ID. The map compares IDs as text, so 7 and '7' are one ID. */
  id?: number | string;
  geometry: GeoJsonGeometry | null;
  properties: Record<string, Object | null> | null;
  /** The box around the feature: its lowest positions, then its highest. */
  bbox?: number[];
}

/** A collection of features, as a GeoJSON source usually takes. Closed. */
export interface GeoJsonFeatureCollection {
  type: 'FeatureCollection';
  features: GeoJsonFeature[];
  /** The box around the features: their lowest positions, then their highest. */
  bbox?: number[];
}

/** Any GeoJSON object, told apart by its `type`. Closed. */
export type GeoJsonObject = GeoJsonGeometry | GeoJsonFeature | GeoJsonFeatureCollection;
