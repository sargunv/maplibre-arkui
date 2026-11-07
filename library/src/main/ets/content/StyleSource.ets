/**
 * A source, as the style spec writes it.
 *
 * ```ets
 * const places: StyleSource = { id: 'places', json: { 'type': 'geojson', 'data': PLACES } };
 * const tiles: StyleSource = { id: 'osm', json: {
 *   'type': 'raster', 'tiles': ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'], 'tileSize': 256 } };
 * ```
 *
 * A GeoJSON source's `data` is a URL or a `GeoJsonObject`, such as a
 * `GeoJsonFeatureCollection`. When only its `data` changes, the source keeps
 * its tiles and loads the new data. Give changed data as a new object: the map
 * compares `data` by identity first, and takes the object it applied last as
 * unchanged. Any other change replaces the source and the layers that draw it.
 */
export interface StyleSource {
  /** The source's ID, unique in the content and the base style. */
  id: string;
  /** The source's style-spec JSON without its ID: its `type` and what that type takes. */
  json: Record<string, Object>;
}
