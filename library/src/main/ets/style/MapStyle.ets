import { StyleImage } from '../content/StyleImage';
import { StyleSource } from '../content/StyleSource';
import { LayerHandle } from './LayerHandle';
import { GeoJsonSourceHandle, ImageSourceHandle, SourceHandle, VectorSourceHandle } from './SourceHandle';

/**
 * Reads and changes the map's loaded style. Get it from
 * `MapController.style`.
 *
 * It works from `onStyleLoaded` until the map loads another style or leaves
 * the screen. At other times, reads and `addSource()` resolve undefined, and
 * other writes resolve `false`. Changes last only for the current style: make
 * them again in each `onStyleLoaded`.
 *
 * The map's content owns the IDs of its sources, layers, and images, and the
 * library reserves IDs and global state names that start with
 * `maplibre-arkui`. Writes to those throw an `Error`.
 *
 * Call its methods on the UI thread. They apply in call order. Writes resolve
 * `true` once applied. Methods throw an `Error` for an invalid argument, and
 * reject when the map rejects a command. Members may be added in later
 * releases.
 */
export interface MapStyle {
  /** The source with `id`, or undefined when the style has none. */
  getSource(id: string): Promise<SourceHandle | undefined>;

  /** The GeoJSON source with `id`, or undefined when the style has none. */
  getGeoJsonSource(id: string): Promise<GeoJsonSourceHandle | undefined>;

  /** The image source with `id`, or undefined when the style has none. */
  getImageSource(id: string): Promise<ImageSourceHandle | undefined>;

  /** The vector tile source with `id`, or undefined when the style has none. */
  getVectorSource(id: string): Promise<VectorSourceHandle | undefined>;

  /** The style's sources. */
  getSources(): Promise<SourceHandle[] | undefined>;

  /**
   * Adds a source to the style, and resolves its handle. Rejects for an ID
   * that the style already has.
   */
  addSource(source: StyleSource): Promise<SourceHandle | undefined>;

  /** The layer with `id`, or undefined when the style has none. */
  getLayer(id: string): Promise<LayerHandle | undefined>;

  /** The style's layers, from bottom to top, including the content's. */
  getLayers(): Promise<LayerHandle[] | undefined>;

  /**
   * Adds an image to the style, or replaces the style's image with the same
   * ID. The app can release the pixel map once the call returns.
   */
  setImage(image: StyleImage): Promise<boolean>;

  /** Removes the style's image with `id`. Resolves `false` when the style has none. */
  removeImage(id: string): Promise<boolean>;

  /** The value of a global state property, or undefined when it has none. */
  getGlobalStateProperty(name: string): Promise<Object | undefined>;

  /** Sets a global state property. `null` restores the style's default. */
  setGlobalStateProperty(name: string, value: Object | null): Promise<boolean>;

  /** How long the style's properties take to change, with every field set. */
  getTransition(): Promise<StyleTransitionOptions | undefined>;

  /** Replaces the style's transition. Fields left out take their defaults. */
  setTransition(options: StyleTransitionOptions): Promise<boolean>;

  /** The value of a property of the style's light, or undefined when the light doesn't set it. */
  getLightProperty(name: string): Promise<Object | undefined>;

  /** Sets a property of the style's light. `null` restores the default. */
  setLightProperty(name: string, value: Object | null): Promise<boolean>;
}

/** How the style's properties change to a new value. */
export interface StyleTransitionOptions {
  /** How long a change takes. Finite and at least 0; 300 by default. */
  durationMs?: number;
  /** How long a change waits before it starts. Finite and at least 0; 0 by default. */
  delayMs?: number;
  /** Whether symbols fade in and out as the map places them. True by default. */
  placementTransitions?: boolean;
}
