// Map content as data: the sources, layers, and images that an app declares
// for a MaplibreMap or a snapshot, and the reconciler that applies them to a
// map's style. After MapLibre Compose's StyleReconciler, much simplified. Also
// loadStyle(), which loads the style under the content, as both take it.

import {
  CommandCompletion,
  MapHandle,
  PremultipliedRgba8Image,
  StyleLayerInfo,
} from '@maplibre/native-ffi';
import image from '@ohos.multimedia.image';

import { Expression } from './Expressions';
import { FONT_SCALE_STATE } from './fontScale';
import { GeoJsonFeature } from './GeoJson';
import { logError } from './log';
import { MapClickEvent } from './MapClickEvent';
import { ContentError, MapError } from './MapError';
import { readPixelMap } from './StyleImage';

/**
 * A layer of the base style: the style that the map loaded, without its
 * content. The map creates it; fields may be added in later releases. It's
 * never one of the layers that the library adds itself, such as the user
 * location indicator's.
 */
export interface LayerSummary {
  /** The layer's ID. */
  id: string;
  /** The layer's style-spec type, such as `'fill'` or `'symbol'`. Open identity. */
  type: string;
  /** The ID of the source that the layer draws, or undefined for a layer without one. */
  source?: string;
  /** The layer of a vector source that the layer draws, or undefined for a source without layers. */
  sourceLayer?: string;
}

/**
 * Picks a layer of the base style, for `StyleLayer.below`.
 *
 * It runs on the UI thread on each content pass, once for each base layer
 * from the bottom up until it returns `true`, so it must be fast and pure; the
 * map doesn't observe the state it reads. When it throws, the map reports the
 * exception to `MaplibreMap.onError` and the log, and the layer counts as
 * unmatched.
 */
export type LayerPredicate = (layer: LayerSummary) => boolean;

/** A click on a layer's features, which `StyleLayer.onClick` and `onLongClick` get. */
export interface FeatureClickEvent extends MapClickEvent {
  /**
   * The layer's features within its `hitPadding` of the click, front first,
   * as the layer drew them, with the geometry as it drew them. Never empty.
   */
  features: GeoJsonFeature[];
}

/**
 * Handles a click on a layer's features. It returns `true` to consume the
 * click, so the layers under it and `MaplibreMap.onUnhandledClick` don't get
 * it, or `false` to pass it on.
 *
 * It runs on the UI thread. When it throws, the map logs the exception and
 * passes the click on.
 */
export type FeatureClickHandler = (event: FeatureClickEvent) => boolean;

/**
 * What a map draws on top of its base style: sources, the layers that draw
 * them, and the images that symbol layers show. Each style the map loads gets
 * all of it, so it lasts across style changes.
 *
 * It's a value. To change what the map draws, give `MaplibreMap` a new one,
 * such as from a `@Computed` getter that reads the app's state. The map
 * compares it with the content it applied, by ID, and changes only what
 * differs.
 */
export interface MapContent {
  /** The sources that the layers draw, besides the base style's. */
  sources?: StyleSource[];
  /** The layers, from bottom to top among those that go under the same layer. */
  layers?: StyleLayer[];
  /** The images that the layers name, such as in `icon-image`. */
  images?: StyleImage[];
}

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

/**
 * A layer, as the style spec writes it, where it goes, and what a click on its
 * features does.
 *
 * ```ets
 * const park: StyleLayer = {
 *   id: 'park', type: 'fill', source: 'places', filter: eq(geometryType(), 'Polygon'),
 *   paint: { 'fill-color': '#66bb6a', 'fill-opacity': 0.6 },
 *   below: (layer: LayerSummary) => layer.type === 'symbol',
 * };
 * ```
 *
 * A change to `paint`, `layout`, `filter`, or the zoom range changes the layer
 * in place, and a change to `type`, `source`, or `sourceLayer` replaces it.
 * The map compares neither the handlers nor `hitPadding`; it uses those of
 * the latest content. An invalid expression goes to `MaplibreMap.onError`.
 */
export interface StyleLayer {
  /** The layer's ID, unique in the content and the base style. */
  id: string;
  /** The style-spec type: `'fill'`, `'line'`, `'circle'`, `'symbol'`, `'raster'`, and so on. Open identity. */
  type: string;
  /** The ID of the source the layer draws, from the content or the base style. */
  source?: string;
  /** The layer of a vector source that the layer draws. */
  sourceLayer?: string;
  /** Which features the layer draws: those for which it's true. */
  filter?: Expression;
  /** The zoom from which the layer shows. */
  minZoom?: number;
  /** The zoom from which the layer hides. */
  maxZoom?: number;
  /** Paint properties by their style-spec names, as expressions or plain values. */
  paint?: Record<string, Object>;
  /** Layout properties by their style-spec names, as expressions or plain values. */
  layout?: Record<string, Object>;
  /**
   * Places the layer under another: the content layer or base-style layer
   * with this ID, or the lowest base-style layer that the predicate picks,
   * such as `(layer: LayerSummary) => layer.type === 'symbol'` to go below
   * the labels, or `() => true` to go below everything. Under a content
   * layer, it goes directly under that layer, wherever that layer goes.
   * Without it, when no layer matches, or when content layers name each
   * other in a cycle, the layer goes on top. Layers placed under the same
   * layer keep their order in `MapContent.layers`.
   *
   * The map compares it by the layer it picks on each pass, so a new
   * predicate that picks the same layer moves nothing.
   */
  below?: string | LayerPredicate;
  /**
   * How far from a click, in vp, the layer's features count as under it: a
   * square of this many vp on each side of the click, so small circles and
   * thin lines are easier to tap. Finite and at least 0; 0 by default. Another
   * value goes to `MaplibreMap.onError` once, when the map applies the
   * content, and counts as 0.
   */
  hitPadding?: number;
  /**
   * Handles a click on the layer's features. After `MaplibreMap.onMapClick`
   * passes a click, the layers with features under it get it from the top
   * layer down, until one consumes it.
   */
  onClick?: FeatureClickHandler;
  /**
   * Handles a long click on the layer's features, a long press or a right
   * click, as `onClick` does a click, after `MaplibreMap.onMapLongClick`.
   */
  onLongClick?: FeatureClickHandler;
}

/**
 * An image for symbol layers' `icon-image` and for patterns.
 *
 * ```ets
 * const pin: StyleImage = { id: 'pin', image: pixelMap };
 * ```
 *
 * The image replaces any image that the style has with this ID, such as one
 * from the base style's sprite, and stays while the content has it, whether a
 * layer uses it or not. Once it leaves the content, the style has no image
 * with this ID. An image that the map rejects changes neither: it goes to
 * `MaplibreMap.onError` as a `ContentError`, and stays out of the style until
 * its `image`, `pixelRatio`, or `sdf` changes.
 */
export interface StyleImage {
  /** The name that layers give the image, unique in the content. */
  id: string;
  /**
   * The pixels, in the `RGBA_8888` or `BGRA_8888` format that decoding an
   * image file gives by default. The map rejects other formats; convert them
   * first with `PixelMap.convertPixelFormat()`.
   *
   * The map reads the pixel map each time it applies the image, such as when
   * a style loads, so keep it unreleased while the content has it. It compares
   * pixel maps by identity: to change the pixels, give a new pixel map, as
   * pixels changed in place change nothing on the map.
   */
  image: image.PixelMap;
  /**
   * The image's pixels in each vp. The map's display density by default, so
   * the image draws at the size that ArkUI's `Image` draws the pixel map at;
   * in a snapshot, its `scaleFactor`. Finite and greater than 0. A change
   * replaces the image.
   */
  pixelRatio?: number;
  /**
   * Whether the image is a signed distance field, which takes its color from
   * the layer's `icon-color`. False by default. A change replaces the image.
   */
  sdf?: boolean;
}

// The features of a click on a layer, front first, as its handler takes them.
export function featureClickEvent(event: MapClickEvent, features: GeoJsonFeature[]): FeatureClickEvent {
  return { coordinate: event.coordinate, point: event.point, features: features };
}

// The layer's hitPadding, or 0 for one that the content pass reports.
export function hitPaddingOf(layer: StyleLayer): number {
  const padding = layer.hitPadding ?? 0;
  return validPadding(padding) ? padding : 0;
}

function validPadding(padding: number): boolean {
  return Number.isFinite(padding) && padding >= 0;
}

// A source the reconciler added: its JSON without data, its data, its data as
// text.
interface AppliedSource {
  shape: string;
  value: Object | undefined;
  data: string;
}

// A layer the reconciler added: what replaces it when it changes, and the text
// of each property it set.
interface AppliedLayer {
  shape: string;
  properties: Map<string, string>;
}

// Thrown out of a pass when the style it applies to is gone.
class Stale extends Error {
}

/**
 * Applies a `MapContent` to the styles that a map loads, one pass at a time.
 * Internal: MapView and snapshot() own one for their map.
 *
 * Each pass compares the latest content with what the reconciler added to the
 * current style and awaits each command, so it knows what the style holds. A
 * source or layer that the map rejects is reported and left out until its
 * definition changes; the rest of the content still applies.
 */
export class ContentReconciler {
  private readonly map: MapHandle;
  private readonly onError: (error: Error) => void;
  // The pixel ratio of an image that doesn't give one.
  private readonly pixelRatio: number;
  private content: MapContent | undefined = undefined;
  // Counts the styles, so a pass stops once its style is gone.
  private generation: number = 0;
  private loaded: boolean = false;
  // The current style's own layers, bottom to top, and every layer it has.
  private base: LayerSummary[] | undefined = undefined;
  private stack: string[] = [];
  private sources: Map<string, AppliedSource> = new Map<string, AppliedSource>();
  private layers: Map<string, AppliedLayer> = new Map<string, AppliedLayer>();
  private images: Map<string, StyleImage> = new Map<string, StyleImage>();
  // What the map rejected, by ID, as text, so a pass skips it until it changes.
  private rejectedSources: Map<string, string> = new Map<string, string>();
  private rejectedImages: Map<string, StyleImage> = new Map<string, StyleImage>();
  private rejectedLayers: Map<string, string> = new Map<string, string>();
  // The invalid hitPadding of each layer that has one, as text, which a pass
  // reports once.
  private invalidPaddings: Map<string, string> = new Map<string, string>();
  private passes: Promise<void> = Promise.resolve();
  private queued: boolean = false;
  // The font scale that fp() reads, and the one the current style has.
  private fontScale: number = 1;
  private appliedFontScale: number | undefined = undefined;

  constructor(map: MapHandle, onError: (error: Error) => void, pixelRatio: number) {
    this.map = map;
    this.onError = onError;
    this.pixelRatio = pixelRatio;
  }

  /** Applies `content` to the loaded style, and to each style from now on. */
  setContent(content: MapContent | undefined): void {
    this.content = content;
    this.schedule();
  }

  /** Sets the font scale that `fp()` reads, in the loaded style and each style from now on. */
  setFontScale(scale: number): void {
    this.fontScale = scale;
    this.schedule();
  }

  /** Settles once the passes that are running or waiting end. */
  get applied(): Promise<void> {
    return this.passes;
  }

  /**
   * Whether the style has a layer with this ID of the base style or the
   * content, as the last pass left it. Layers that the app added itself don't
   * count.
   */
  hasLayer(id: string): boolean {
    return this.stack.includes(id);
  }

  /** A style has loaded, without any content. */
  styleLoaded(): Promise<void> {
    this.reset();
    this.loaded = true;
    return this.schedule();
  }

  /** The map is loading another style, or going away. */
  styleUnloaded(): void {
    this.reset();
  }

  /** Counts the styles that the map has loaded or started to. */
  get styleGeneration(): number {
    return this.generation;
  }

  /**
   * The content's layers in the style that handle a click, or a long click
   * if `long`, from the top layer down, as the style orders them.
   */
  clickableLayers(long: boolean): StyleLayer[] {
    const handlers = new Map<string, StyleLayer>();
    for (const layer of this.content?.layers ?? []) {
      if ((long ? layer.onLongClick : layer.onClick) !== undefined && this.layers.has(layer.id)) {
        handlers.set(layer.id, layer);
      }
    }
    const clickable: StyleLayer[] = [];
    for (let i = this.stack.length - 1; i >= 0; i--) {
      const layer = handlers.get(this.stack[i]);
      if (layer !== undefined) {
        clickable.push(layer);
      }
    }
    return clickable;
  }

  private reset(): void {
    this.generation++;
    this.loaded = false;
    this.base = undefined;
    this.appliedFontScale = undefined;
    this.stack = [];
    this.sources.clear();
    this.layers.clear();
    this.images.clear();
    this.rejectedSources.clear();
    this.rejectedImages.clear();
    this.rejectedLayers.clear();
  }

  // Runs a pass after the one in progress, or joins the one that waits.
  private schedule(): Promise<void> {
    if (!this.queued) {
      this.queued = true;
      this.passes = this.passes.then(() => {
        this.queued = false;
        return this.pass();
      });
    }
    return this.passes;
  }

  private async pass(): Promise<void> {
    if (!this.loaded) {
      return;
    }
    const generation = this.generation;
    try {
      if (this.base === undefined) {
        const base = await this.map.listStyleLayers();
        this.check(generation);
        this.base = base.map(summaryOf);
        this.stack = base.map((layer: StyleLayerInfo) => layer.id);
      }
      // Before the content, so its labels start at their size.
      const scale = this.fontScale;
      if (this.appliedFontScale !== scale) {
        this.appliedFontScale = scale;
        await this.run(generation, undefined, 'setting the font scale',
          this.map.setGlobalStateProperty(FONT_SCALE_STATE, scale));
      }
      await this.apply(this.content, generation);
    } catch (error) {
      if (!(error instanceof Stale)) {
        this.report(error as Error);
      }
    }
  }

  // An error handler that throws doesn't stop the passes.
  private report(error: Error): void {
    try {
      this.onError(error);
    } catch (thrown) {
      logError(`onError threw: ${(thrown as Error).message}`);
    }
  }

  private check(generation: number): void {
    if (generation !== this.generation) {
      throw new Stale();
    }
  }

  // Runs a command, reports its failure, as a ContentError for the content
  // with `id` if any, and returns whether it succeeded.
  private async run(generation: number, id: string | undefined, what: string,
    command: Promise<CommandCompletion>): Promise<boolean> {
    let succeeded = true;
    try {
      await command;
    } catch (error) {
      succeeded = false;
      this.check(generation);
      const message = `Content: ${what} failed: ${(error as Error).message}`;
      this.report(id === undefined ? new MapError(message) : new ContentError(id, message));
    }
    this.check(generation);
    return succeeded;
  }

  private async apply(content: MapContent | undefined, generation: number): Promise<void> {
    const map = this.map;
    const sources = new Map<string, StyleSource>();
    for (const source of content?.sources ?? []) {
      sources.set(source.id, source);
    }
    const layers = new Map<string, StyleLayer>();
    for (const layer of content?.layers ?? []) {
      layers.set(layer.id, layer);
    }
    const images = new Map<string, StyleImage>();
    for (const item of content?.images ?? []) {
      images.set(item.id, item);
    }
    this.checkPaddings(layers);

    // A rejected source that the content dropped no longer holds back the
    // layers over a source of that ID.
    for (const id of Array.from(this.rejectedSources.keys())) {
      if (!sources.has(id)) {
        this.rejectedSources.delete(id);
      }
    }

    // Sources that go or that change more than their data take their layers
    // with them.
    const replaced = new Set<string>();
    for (const id of Array.from(this.sources.keys())) {
      const desired = sources.get(id);
      if (desired === undefined || shapeOf(desired) !== this.sources.get(id)?.shape) {
        replaced.add(id);
      }
    }
    for (const id of Array.from(this.layers.keys())) {
      const desired = layers.get(id);
      if (desired === undefined || layerShape(desired) !== this.layers.get(id)?.shape ||
        replaced.has(desired.source ?? '')) {
        this.layers.delete(id);
        this.stack = this.stack.filter((other: string) => other !== id);
        await this.run(generation, id, `removing layer ${id}`, map.removeStyleLayer(id));
      }
    }
    // A source that the map won't remove, such as one that a layer the app
    // added still uses, stays the content's, to remove on a later pass.
    for (const id of Array.from(replaced)) {
      if (await this.run(generation, id, `removing source ${id}`, map.removeStyleSource(id))) {
        this.sources.delete(id);
      }
    }

    for (const source of Array.from(sources.values())) {
      if (!(replaced.has(source.id) && this.sources.has(source.id))) {
        await this.applySource(source, generation);
      }
    }

    for (const id of Array.from(this.rejectedImages.keys())) {
      if (!images.has(id)) {
        this.rejectedImages.delete(id);
      }
    }
    for (const id of Array.from(this.images.keys())) {
      if (!images.has(id)) {
        this.images.delete(id);
        await this.run(generation, id, `removing image ${id}`, map.removeStyleImage(id));
      }
    }
    for (const item of Array.from(images.values())) {
      await this.applyImage(item, generation);
    }

    // The layers under each content layer, and the rest by the base layer
    // they go under.
    const under = new Map<string, StyleLayer[]>();
    const groups = new Map<string, StyleLayer[]>();
    for (const layer of Array.from(layers.values())) {
      const below = layer.below;
      const parent = typeof below === 'string' && layers.has(below) && !inCycle(layer, layers) ? below : undefined;
      const into = parent !== undefined ? under : groups;
      const key = parent ?? this.resolve(layer);
      const siblings = into.get(key) ?? [];
      siblings.push(layer);
      into.set(key, siblings);
    }
    // Each group, from its top down: each layer goes directly under the one
    // above it, and a layer that the map rejected leaves its place to the
    // layers under it.
    for (const before of Array.from(groups.keys())) {
      const group: StyleLayer[] = [];
      stackUp(groups.get(before) ?? [], under, group);
      let above = before;
      for (let i = group.length - 1; i >= 0; i--) {
        if (await this.applyLayer(group[i], above, generation)) {
          above = group[i].id;
        }
      }
    }
  }

  // Reports each layer's invalid hitPadding once, until it changes.
  private checkPaddings(layers: Map<string, StyleLayer>): void {
    for (const id of Array.from(this.invalidPaddings.keys())) {
      if (!layers.has(id)) {
        this.invalidPaddings.delete(id);
      }
    }
    for (const layer of Array.from(layers.values())) {
      const padding = layer.hitPadding ?? 0;
      if (validPadding(padding)) {
        this.invalidPaddings.delete(layer.id);
      } else if (this.invalidPaddings.get(layer.id) !== `${padding}`) {
        this.invalidPaddings.set(layer.id, `${padding}`);
        this.report(new MapError(
          `Content: the hitPadding of layer ${layer.id} must be finite and at least 0, so ${padding} counts as 0`));
      }
    }
  }

  private async applySource(source: StyleSource, generation: number): Promise<void> {
    const map = this.map;
    const value = source.json['data'];
    const applied = this.sources.get(source.id);
    if (applied !== undefined && applied.value === value) {
      return;
    }
    const shape = shapeOf(source);
    const data = textOf(value);
    if (applied === undefined) {
      const key = `${shape}${data}`;
      if (this.rejectedSources.get(source.id) === key) {
        return;
      }
      if (await this.run(generation, source.id, `adding source ${source.id}`,
        map.addStyleSourceJson(source.id, source.json))) {
        this.sources.set(source.id, { shape: shape, value: value, data: data });
        this.rejectedSources.delete(source.id);
      } else {
        this.rejectedSources.set(source.id, key);
      }
      return;
    }
    applied.value = value;
    if (applied.data === data) {
      return;
    }
    // Only a GeoJSON source's data changed.
    applied.data = data;
    if (typeof value === 'string') {
      await this.run(generation, source.id, `setting the URL of source ${source.id}`,
        map.setGeoJsonSourceUrl(source.id, value));
    } else {
      await this.run(generation, source.id, `setting the data of source ${source.id}`,
        map.setGeoJsonSourceData(source.id, value));
    }
  }

  // Sets the image unless the style has it or rejected it as it is. The
  // content owns an image's ID once the map has taken an image for it.
  private async applyImage(wanted: StyleImage, generation: number): Promise<void> {
    const applied = this.images.get(wanted.id);
    const rejected = this.rejectedImages.get(wanted.id);
    if ((applied !== undefined && this.sameImage(applied, wanted)) ||
      (rejected !== undefined && this.sameImage(rejected, wanted))) {
      return;
    }
    let pixels: PremultipliedRgba8Image;
    try {
      pixels = readPixelMap(wanted.image);
    } catch (error) {
      this.rejectedImages.set(wanted.id, wanted);
      this.report(new ContentError(wanted.id,
        `Content: reading image ${wanted.id} failed: ${(error as Error).message}`));
      return;
    }
    const set = await this.run(generation, wanted.id, `setting image ${wanted.id}`,
      this.map.setStyleImage(wanted.id, pixels,
        { pixelRatio: wanted.pixelRatio ?? this.pixelRatio, sdf: wanted.sdf ?? false, keepUnused: true }));
    if (set) {
      this.images.set(wanted.id, wanted);
      this.rejectedImages.delete(wanted.id);
    } else {
      this.rejectedImages.set(wanted.id, wanted);
    }
  }

  private sameImage(a: StyleImage, b: StyleImage): boolean {
    // As text, so NaN equals itself.
    return a.image === b.image && `${a.pixelRatio ?? this.pixelRatio}` === `${b.pixelRatio ?? this.pixelRatio}` &&
      (a.sdf ?? false) === (b.sdf ?? false);
  }

  // Adds the layer under `above`, or changes it and moves it there, and returns
  // whether the style has it.
  private async applyLayer(layer: StyleLayer, above: string, generation: number): Promise<boolean> {
    const map = this.map;
    const properties = propertiesOf(layer);
    const applied = this.layers.get(layer.id);
    if (applied === undefined) {
      // A layer over a source that the map rejected waits for the source.
      if (layer.source !== undefined && this.rejectedSources.has(layer.source)) {
        return false;
      }
      // The key changes when the map might take the layer: when it changes,
      // goes elsewhere, or its source comes, goes, or changes.
      const json = layerJson(layer);
      const key = `${JSON.stringify(json)}@${above}@${this.sources.get(layer.source ?? '')?.shape ?? ''}`;
      if (this.rejectedLayers.get(layer.id) === key) {
        return false;
      }
      const added = await this.run(generation, layer.id, `adding layer ${layer.id}`,
        map.addStyleLayerJson(json, above === '' ? undefined : above));
      if (!added) {
        this.rejectedLayers.set(layer.id, key);
        return false;
      }
      this.rejectedLayers.delete(layer.id);
      const texts = new Map<string, string>();
      properties.forEach((value: Object | null, name: string) => texts.set(name, textOf(value)));
      this.layers.set(layer.id, { shape: layerShape(layer), properties: texts });
      this.insert(layer.id, above);
      return true;
    }

    // Properties the layer no longer sets go back to their defaults.
    applied.properties.forEach((value: string, name: string) => {
      if (!properties.has(name)) {
        properties.set(name, null);
      }
    });
    for (const name of Array.from(properties.keys())) {
      const value = properties.get(name) ?? null;
      const text = textOf(value);
      if (applied.properties.get(name) !== text) {
        // Recorded either way, so a value the map rejects isn't set again
        // until it changes.
        if (value === null) {
          applied.properties.delete(name);
        } else {
          applied.properties.set(name, text);
        }
        await this.run(generation, layer.id, `setting ${name} of layer ${layer.id}`,
          map.setStyleLayerProperty(layer.id, name, value));
      }
    }
    const index = this.stack.indexOf(layer.id);
    const current = index + 1 < this.stack.length ? this.stack[index + 1] : '';
    if (current !== above) {
      this.stack.splice(index, 1);
      this.insert(layer.id, above);
      await this.run(generation, layer.id, `moving layer ${layer.id}`,
        map.moveStyleLayer(layer.id, above === '' ? undefined : above));
    }
    return true;
  }

  private insert(id: string, above: string): void {
    const index = above === '' ? -1 : this.stack.indexOf(above);
    if (index < 0) {
      this.stack.push(id);
    } else {
      this.stack.splice(index, 0, id);
    }
  }

  /**
   * The layer that `below` places a layer of the library's under, as the
   * last pass left the style: the base-style or content layer with this ID,
   * or the base layer that the predicate picks. '' when there's none. A
   * predicate that throws is reported as `what`'s, and picks none.
   */
  layerBelow(below: string | LayerPredicate, what: string): string {
    if (typeof below === 'string') {
      return this.hasLayer(below) ? below : '';
    }
    return this.pick(below, what);
  }

  // The base layer that a layer goes under, or '' for the top.
  private resolve(layer: StyleLayer): string {
    const below = layer.below;
    if (typeof below === 'string') {
      return (this.base ?? []).find((other: LayerSummary) => other.id === below)?.id ?? '';
    }
    return below === undefined ? '' : this.pick(below, `Content: the below predicate of layer ${layer.id}`);
  }

  // The base layer that `predicate` picks, or '' for none. One that throws is
  // reported as `what`'s, and picks none.
  private pick(predicate: LayerPredicate, what: string): string {
    try {
      return (this.base ?? []).find(predicate)?.id ?? '';
    } catch (error) {
      this.report(new MapError(`${what} threw: ${(error as Error).message}`));
      return '';
    }
  }
}

function summaryOf(info: StyleLayerInfo): LayerSummary {
  return {
    id: info.id,
    type: info.type,
    source: info.sourceId === '' ? undefined : info.sourceId,
    sourceLayer: info.sourceLayer === '' ? undefined : info.sourceLayer,
  };
}

// Whether following `below` from `layer` through content layers comes back to
// it.
function inCycle(layer: StyleLayer, layers: Map<string, StyleLayer>): boolean {
  let next = layers.get(typeof layer.below === 'string' ? layer.below : '');
  for (let steps = 0; next !== undefined && steps < layers.size; steps++) {
    if (next.id === layer.id) {
      return true;
    }
    next = layers.get(typeof next.below === 'string' ? next.below : '');
  }
  return false;
}

// Appends `layers` to `stack`, bottom to top, each above the layers under it.
function stackUp(layers: StyleLayer[], under: Map<string, StyleLayer[]>, stack: StyleLayer[]): void {
  for (const layer of layers) {
    stackUp(under.get(layer.id) ?? [], under, stack);
    stack.push(layer);
  }
}

function textOf(value: Object | null | undefined): string {
  if (value instanceof Expression) {
    return value.toString();
  }
  return value === undefined ? '' : JSON.stringify(value);
}

// A source's JSON without its data, as text.
function shapeOf(source: StyleSource): string {
  const shape: Record<string, Object> = {};
  for (const key of Object.keys(source.json)) {
    if (key !== 'data') {
      shape[key] = source.json[key];
    }
  }
  return JSON.stringify(shape);
}

function layerShape(layer: StyleLayer): string {
  return JSON.stringify([layer.type, layer.source ?? '', layer.sourceLayer ?? '']);
}

// The properties that setStyleLayerProperty() sets, by name.
function propertiesOf(layer: StyleLayer): Map<string, Object | null> {
  const properties = new Map<string, Object | null>();
  if (layer.filter !== undefined) {
    properties.set('filter', layer.filter);
  }
  if (layer.minZoom !== undefined) {
    properties.set('minzoom', layer.minZoom);
  }
  if (layer.maxZoom !== undefined) {
    properties.set('maxzoom', layer.maxZoom);
  }
  const groups: (Record<string, Object> | undefined)[] = [layer.paint, layer.layout];
  for (const group of groups) {
    if (group !== undefined) {
      for (const name of Object.keys(group)) {
        properties.set(name, group[name]);
      }
    }
  }
  return properties;
}

function layerJson(layer: StyleLayer): Record<string, Object> {
  const json: Record<string, Object> = { 'id': layer.id, 'type': layer.type };
  if (layer.source !== undefined) {
    json['source'] = layer.source;
  }
  if (layer.sourceLayer !== undefined) {
    json['source-layer'] = layer.sourceLayer;
  }
  if (layer.filter !== undefined) {
    json['filter'] = layer.filter;
  }
  if (layer.minZoom !== undefined) {
    json['minzoom'] = layer.minZoom;
  }
  if (layer.maxZoom !== undefined) {
    json['maxzoom'] = layer.maxZoom;
  }
  if (layer.paint !== undefined) {
    json['paint'] = layer.paint;
  }
  if (layer.layout !== undefined) {
    json['layout'] = layer.layout;
  }
  return json;
}

// A string is the style's URL, and a record its document. The command
// completes once the style is loaded.
export function loadStyle(map: MapHandle, style: string | Record<string, Object>): Promise<CommandCompletion> {
  return typeof style === 'string' ? map.setStyleUrl(style) : map.setStyleJson(style);
}
