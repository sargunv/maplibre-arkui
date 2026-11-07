import { LayerSummary } from '../content/StyleLayer';
import { LayerKey } from './internal/HandleKeys';
import { checkOwned, propertyValue, read, write } from './internal/StyleCommands';

// The properties that a layer keeps for its life.
const FIXED_PROPERTIES = ['id', 'type', 'source', 'source-layer'];

/**
 * A layer of the style that `MapStyle` reads, of the base style or the
 * content, with its properties.
 *
 * A handle belongs to one style. It expires when that style goes, as
 * `MapStyle` describes, and when the content removes or replaces its layer.
 * Then its reads resolve undefined and its writes `false`. Get a new handle
 * for the layer of a new style.
 *
 * The map creates handles; apps can't. Members may be added in later
 * releases.
 */
export class LayerHandle implements LayerSummary {
  /** The layer's ID. */
  readonly id: string;
  /** The layer's style-spec type, such as `'fill'` or `'symbol'`. Open identity. */
  readonly type: string;
  /** The ID of the source that the layer draws, or undefined for a layer without one. */
  readonly source?: string;
  /** The layer of a vector source that the layer draws, or undefined for a source without layers. */
  readonly sourceLayer?: string;
  /**
   * Whether the layer is one of the map's content, when the map made the
   * handle. `setProperty()` throws for a layer of the content.
   */
  readonly fromContent: boolean;
  private readonly key: LayerKey;

  /** @internal The map creates handles. */
  constructor(key: LayerKey) {
    this.id = key.summary.id;
    this.type = key.summary.type;
    this.source = key.summary.source;
    this.sourceLayer = key.summary.sourceLayer;
    this.fromContent = key.fromContent;
    this.key = key;
  }

  /**
   * The value that the layer sets for the property `name`, as style-spec
   * JSON, or undefined when the layer doesn't set it. `name` is a layout or
   * paint property, its `-transition`, such as `'fill-color-transition'`,
   * `'filter'`, `'minzoom'`, or `'maxzoom'`.
   */
  getProperty(name: string): Promise<Object | undefined> {
    const key = this.key;
    if (!key.holds()) {
      return Promise.resolve(undefined);
    }
    return read(() => key.holds(), `reading ${name} of layer ${this.id}`,
      () => key.style.map.getStyleLayerProperty(this.id, name) as Promise<Object | undefined>,
      (value: Object | undefined): Object | undefined => value);
  }

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
  setProperty(name: string, value: Object | null): Promise<boolean> {
    if (FIXED_PROPERTIES.includes(name)) {
      throw new Error(`A layer keeps its ${name}, which setProperty() can't change: ${name}`);
    }
    const key = this.key;
    if (!key.holds()) {
      return Promise.resolve(false);
    }
    checkOwned(key.style.reconciler.ownsLayer(this.id), 'layer', this.id);
    return write(() => key.holds(), `setting ${name} of layer ${this.id}`,
      () => key.style.map.setStyleLayerProperty(this.id, name, propertyValue(name, value)));
  }
}
