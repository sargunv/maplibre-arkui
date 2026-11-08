/**
 * A source of the map's content.
 *
 * A GeoJSON source's `data` is a URL or a `GeoJsonObject`. To change the data,
 * pass a new object; the map doesn't see changes made inside the object it
 * has.
 */
export interface StyleSource {
  /** The source's ID, which no other source in the style may have. */
  id: string;
  /** The source's style-spec JSON, without the ID. */
  json: Record<string, Object>;
}
