// GeoJSON types, https://datatracker.ietf.org/doc/html/rfc7946, so ArkTS apps
// can write GeoJSON as object literals: strict ArkTS accepts an object literal
// only for a declared type. FFI takes GeoJSON as a plain object, in a source's
// `data` or in `GeoJsonSourceDataHandle.create()`, and returns it from feature
// queries. These types only describe it; nothing converts it.

/** A longitude and a latitude, in that order, and an optional altitude. */
export type GeoJsonPosition = number[];

/**
 * A geometry: `type` is `'Point'`, `'MultiPoint'`, `'LineString'`,
 * `'MultiLineString'`, `'Polygon'`, or `'MultiPolygon'`, and `coordinates`
 * nests positions as that type needs. A `'GeometryCollection'` has
 * `geometries` instead.
 */
export interface GeoJsonGeometry {
  type: string;
  coordinates?: GeoJsonPosition | GeoJsonPosition[] | GeoJsonPosition[][] | GeoJsonPosition[][][];
  geometries?: GeoJsonGeometry[];
}

/** A feature: a geometry with properties, and an optional ID. */
export interface GeoJsonFeature {
  type: 'Feature';
  /** The feature's ID. The map compares IDs as text, so 7 and '7' are one ID. */
  id?: number | string;
  geometry: GeoJsonGeometry | null;
  properties: Record<string, Object | null> | null;
}

/** A collection of features, as a GeoJSON source usually takes. */
export interface GeoJsonFeatureCollection {
  type: 'FeatureCollection';
  features: GeoJsonFeature[];
}
