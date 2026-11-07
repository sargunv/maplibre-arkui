import { StyleImage } from '../content/StyleImage';
import { StyleSource } from '../content/StyleSource';
import { LayerHandle } from './LayerHandle';
import { GeoJsonSourceHandle, ImageSourceHandle, SourceHandle, VectorSourceHandle } from './SourceHandle';

/**
 * Reads and changes the style that the map has loaded: its sources, layers,
 * images, global state, transition, and light. `MapController.style` gives it.
 * For what the app keeps in its state, declare the map's `content` instead.
 *
 * ```ets
 * MaplibreMap({
 *   style: STYLE,
 *   controller: this.controller,
 *   onStyleLoaded: () => {
 *     this.controller.style.getLayer('water')
 *       .then((water: LayerHandle | undefined) => water?.setProperty('fill-color', '#1565c0'));
 *   },
 * })
 * ```
 *
 * It acts on the style of the map that shows the controller, from that map's
 * `onStyleLoaded`, once `MapController.styleLoaded` is true and the map has
 * added its content, until the map starts another style or leaves, or another
 * map takes the controller. At other times, reads resolve undefined, writes
 * resolve `false`, and `addSource()` resolves undefined, without an error.
 *
 * A change lasts for the current style only. A new `style` value, a map that
 * appears again, and a map that starts again at a new display density each
 * load a style from its document, without the changes, so make them again in
 * `onStyleLoaded`, or declare them as content, which the map adds to each
 * style.
 *
 * The content owns the IDs of the sources, layers, and images in the latest
 * content that the map received. Reads find them, but a method that would
 * change, remove, or add one with such an ID throws an `Error` that names the
 * ID; change the content instead. When the content declares the ID of a source
 * that the app added, the content's source replaces the app's, and the app's
 * handle expires. The library reserves the IDs that start with
 * `maplibre-arkui` and the global state names that start with
 * `maplibre-arkui:`: reads leave them out, and writes throw.
 *
 * Call its methods on the UI thread. Their commands reach the map in the order
 * of the calls, among the commands that apply the content, and a read resolves
 * after the writes before it. A write resolves `true` once the map has applied
 * it. A method throws an `Error` for an invalid argument, and includes the
 * value in its message. When the map rejects a command, such as a value that
 * isn't valid for the property, the promise rejects with an `Error`, and the
 * style keeps what it had.
 *
 * The map creates it; members may be added in later releases.
 */
export interface MapStyle {
  /** The source with `id`, or undefined when the style has none. */
  getSource(id: string): Promise<SourceHandle | undefined>;

  /** The GeoJSON source with `id`, or undefined when the style has no GeoJSON source with it. */
  getGeoJsonSource(id: string): Promise<GeoJsonSourceHandle | undefined>;

  /** The image source with `id`, or undefined when the style has no image source with it. */
  getImageSource(id: string): Promise<ImageSourceHandle | undefined>;

  /** The vector tile source with `id`, or undefined when the style has no vector tile source with it. */
  getVectorSource(id: string): Promise<VectorSourceHandle | undefined>;

  /** The style's sources, in the order that the style lists them. */
  getSources(): Promise<SourceHandle[] | undefined>;

  /**
   * Adds `source` to the style, and resolves its handle once the map has added
   * it, and with it the content's layers that draw a source with its ID.
   *
   * It throws an `Error` for an ID of the content or the library. It rejects
   * when the map rejects the source, such as for an ID that the style already
   * has.
   */
  addSource(source: StyleSource): Promise<SourceHandle | undefined>;

  /** The layer with `id`, or undefined when the style has none. */
  getLayer(id: string): Promise<LayerHandle | undefined>;

  /**
   * The style's layers, from bottom to top: those of the base style and the
   * content, without the library's own, such as the user location indicator.
   */
  getLayers(): Promise<LayerHandle[] | undefined>;

  /**
   * Adds `image` to the style, or replaces the style's image with its ID, such
   * as one from the sprite. It reads the pixels during the call, so the app
   * can release the pixel map once the call returns. Its `pixelRatio` is the
   * map's display density by default, and its `sdf` false.
   *
   * It throws an `Error` for an ID of the content or the library, a pixel map
   * that isn't `RGBA_8888` or `BGRA_8888` or can't be read, and a
   * `pixelRatio` that isn't finite and greater than 0.
   */
  setImage(image: StyleImage): Promise<boolean>;

  /**
   * Removes the style's image with `id`, such as one from the sprite, and
   * resolves `false` when the style has no image with `id`. It throws an
   * `Error` for an ID of the content or the library.
   */
  removeImage(id: string): Promise<boolean>;

  /**
   * The value of the style's global state property `name`, which
   * `globalState()` expressions read: the default of the style's `state`, or
   * the value set since. It resolves undefined when the property has none, or
   * its value is null, and for a name of the library.
   */
  getGlobalStateProperty(name: string): Promise<Object | undefined>;

  /**
   * Sets the global state property `name`, which `globalState()` expressions
   * read, to `value`. `null` restores the default of the style's `state`, or
   * null where it has none. It throws an `Error` for a name of the library.
   */
  setGlobalStateProperty(name: string, value: Object | null): Promise<boolean>;

  /**
   * The transition that the style's properties take to a new value, unless
   * the property's own `-transition` sets one, with every field set.
   */
  getTransition(): Promise<StyleTransitionOptions | undefined>;

  /**
   * Replaces the style's transition. The fields that `options` leaves out take
   * their defaults. It throws an `Error` for a `durationMs` or `delayMs` that
   * isn't finite or is below 0.
   */
  setTransition(options: StyleTransitionOptions): Promise<boolean>;

  /**
   * The value that the style's light sets for its property `name`, such as
   * `'anchor'` or `'intensity'`, as style-spec JSON, or undefined when the
   * light doesn't set it.
   */
  getLightProperty(name: string): Promise<Object | undefined>;

  /**
   * Sets the style's light property `name`, as `getLightProperty()` names
   * them, to `value`, as the style spec writes it. `null` restores the
   * property's default. It rejects when the map rejects the value, such as one
   * of the wrong type, or a property that the light doesn't have.
   */
  setLightProperty(name: string, value: Object | null): Promise<boolean>;
}

/** How the style's properties change to a new value, for `MapStyle.setTransition()`. */
export interface StyleTransitionOptions {
  /** How long a change takes. Finite and at least 0; 300 by default. */
  durationMs?: number;
  /** How long a change waits before it starts. Finite and at least 0; 0 by default. */
  delayMs?: number;
  /** Whether symbols fade in and out as the map places them. True by default. */
  placementTransitions?: boolean;
}
