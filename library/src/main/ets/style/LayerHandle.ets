import { LayerSummary } from '../content/StyleLayer';
import { refsOf } from '../expression/internal/StyleRefs';
import { LayerKey } from './internal/HandleKeys';
import { checkOwned, propertyValue, read, write } from './internal/StyleCommands';

// The properties that a layer keeps for its life.
const FIXED_PROPERTIES = ['id', 'type', 'source', 'source-layer'];

/**
 * A layer of the loaded style, from the base style or the content.
 *
 * A handle expires when its style is replaced, or when the content removes or
 * replaces its layer. After that, reads resolve undefined and writes resolve
 * `false`.
 *
 * Only the library creates handles. Members may be added in later releases.
 */
export class LayerHandle implements LayerSummary {
  /** The layer's ID. */
  readonly id: string;
  /** The layer's style-spec type, such as `'fill'` or `'symbol'`. Open identity. */
  readonly type: string;
  /** The ID of the layer's source, or undefined for a layer without one. */
  readonly source: string | undefined;
  /** The source layer that the layer draws, or undefined for a source without layers. */
  readonly sourceLayer: string | undefined;
  /** Whether the layer belonged to the map's content when the handle was made. */
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
   * The value of a property, as style-spec JSON, or undefined when the layer
   * doesn't set it. `name` is a layout or paint property, a property's
   * `-transition`, `'filter'`, `'minzoom'`, or `'maxzoom'`.
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
   * Sets a property, named as for `getProperty()`, to an expression or a plain
   * value. `null` restores the default. Throws an `Error` for a layer that the
   * content owns, and for `'id'`, `'type'`, `'source'`, and `'source-layer'`.
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
    key.style.reconciler.trackRefs(`layer/${this.id}/${name}`, refsOf(value));
    return write(() => key.holds(), `setting ${name} of layer ${this.id}`,
      () => key.style.map.setStyleLayerProperty(this.id, name, propertyValue(name, value)));
  }
}
