import { LayerSummary } from '../content/StyleLayer';

/**
 * A layer of the style that `MapStyle` reads, of the base style or the
 * content, with its properties.
 *
 * A handle belongs to one style. It expires when that style goes, as
 * `MapStyle` describes, and when the content removes or replaces its layer.
 * Then its reads resolve undefined and its writes `false`. Get a new handle
 * for the layer of a new style.
 *
 * The map creates it; members may be added in later releases.
 */
export interface LayerHandle extends LayerSummary {
  /**
   * The value that the layer sets for the property `name`, as style-spec
   * JSON, or undefined when the layer doesn't set it. `name` is a layout or
   * paint property, its `-transition`, such as `'fill-color-transition'`,
   * `'filter'`, `'minzoom'`, or `'maxzoom'`.
   */
  getProperty(name: string): Promise<Object | undefined>;

  /**
   * Sets the layer's property `name`, as `getProperty()` names them, to
   * `value`: an expression, or a plain value as the style spec writes it.
   * `null` restores the property's default.
   *
   * It throws an `Error` for `'id'`, `'type'`, `'source'`, and
   * `'source-layer'`, which a layer keeps, and for a layer of the content, as
   * `MapStyle` describes. It rejects when the map rejects the value, such as
   * one of the wrong type, or a property that the layer's type doesn't have.
   */
  setProperty(name: string, value: Object | null): Promise<boolean>;
}
