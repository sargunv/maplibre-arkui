// Map content as data: the sources, layers, and images that an app declares
// for a MapLibreMap or a snapshot, and the reconciler that applies them to a
// map's style. After MapLibre Compose's StyleReconciler, much simplified.

import {
  CommandCompletion,
  GeoJsonSourceDataHandle,
  MapHandle,
  PremultipliedRgba8Image,
  StyleImageOptions,
  StyleLayerInfo,
} from '@maplibre/native-ffi';

import { Expression } from './Expressions';

/** Picks a layer of the base style, for `MapLayer.below`. */
export type LayerPredicate = (layer: StyleLayerInfo) => boolean;

/**
 * What a map draws on top of its base style: sources, the layers that draw
 * them, and the images that symbol layers show. Each style the map loads gets
 * all of it, so it lasts across style changes.
 *
 * It's a value. To change what the map draws, give `MapLibreMap` a new one,
 * such as from a `@Computed` getter that reads the app's state. The map
 * compares it with the content it applied, by ID, and changes only what
 * differs.
 */
export interface MapContent {
  sources?: MapSource[];
  /** The layers, from bottom to top among those with the same `below`. */
  layers?: MapLayer[];
  images?: MapImage[];
}

/**
 * A source, as the style spec writes it.
 *
 * ```ets
 * const places: MapSource = { id: 'places', json: { 'type': 'geojson', 'data': PLACES } };
 * const tiles: MapSource = { id: 'osm', json: {
 *   'type': 'raster', 'tiles': ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'], 'tileSize': 256 } };
 * ```
 *
 * A GeoJSON source's `data` is a URL or a GeoJSON object, such as a
 * `GeoJsonFeatureCollection`. When only its `data` changes, the source keeps
 * its tiles and loads the new data. Give changed data as a new object: the map
 * takes the object it applied last as unchanged. Any other change replaces the
 * source and the layers that draw it.
 */
export interface MapSource {
  id: string;
  /** The source's style-spec JSON without its ID: its `type` and what that type takes. */
  json: Record<string, Object>;
}

/**
 * A layer, as the style spec writes it, and where it goes.
 *
 * ```ets
 * const park: MapLayer = {
 *   id: 'park', type: 'fill', source: 'places', filter: eq(geometryType(), 'Polygon'),
 *   paint: { 'fill-color': '#66bb6a', 'fill-opacity': 0.6 },
 *   below: (layer: StyleLayerInfo) => layer.type === 'symbol',
 * };
 * ```
 *
 * A change to `paint`, `layout`, `filter`, or the zoom range changes the layer
 * in place, and a change to `type`, `source`, or `sourceLayer` replaces it.
 */
export interface MapLayer {
  id: string;
  /** `'fill'`, `'line'`, `'circle'`, `'symbol'`, `'fill-extrusion'`, `'raster'`, and so on. */
  type: string;
  /** The ID of the source the layer draws, from the content or the base style. */
  source?: string;
  /** The layer of a vector source that the layer draws. */
  sourceLayer?: string;
  filter?: Expression;
  minZoom?: number;
  maxZoom?: number;
  /** Paint properties by their style-spec names, as expressions or plain values. */
  paint?: Record<string, Object>;
  /** Layout properties by their style-spec names, as expressions or plain values. */
  layout?: Record<string, Object>;
  /**
   * Places the layer under a layer of the base style: the one with this ID,
   * or the lowest one that the predicate picks, such as
   * `(layer: StyleLayerInfo) => layer.type === 'symbol'` to go below the
   * labels, or `() => true` to go below everything. Without it, or when the
   * base style has no such layer, the layer goes on top. Layers placed under
   * the same layer keep their order in `MapContent.layers`.
   */
  below?: string | LayerPredicate;
}

/** An image for symbol layers' `icon-image` and patterns, such as from `readPixelMap()`. */
export interface MapImage {
  id: string;
  /** The pixels. A new object replaces the image; the map doesn't compare pixels. */
  image: PremultipliedRgba8Image;
  options?: StyleImageOptions;
}

// A source the reconciler added: its JSON without data, its data, and its
// data as text.
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
  private content: MapContent | undefined = undefined;
  // Counts the styles, so a pass stops once its style is gone.
  private generation: number = 0;
  private loaded: boolean = false;
  // The current style's own layers, bottom to top, and every layer it has.
  private base: readonly StyleLayerInfo[] | undefined = undefined;
  private stack: string[] = [];
  private sources: Map<string, AppliedSource> = new Map<string, AppliedSource>();
  private layers: Map<string, AppliedLayer> = new Map<string, AppliedLayer>();
  private images: Map<string, MapImage> = new Map<string, MapImage>();
  // What the map rejected, by ID, as text, so a pass skips it until it changes.
  private rejectedSources: Map<string, string> = new Map<string, string>();
  // Images of the content whose ID the style already had, which it leaves to
  // the style.
  private rejectedImages: Set<string> = new Set<string>();
  private rejectedLayers: Map<string, string> = new Map<string, string>();
  private passes: Promise<void> = Promise.resolve();
  private queued: boolean = false;

  constructor(map: MapHandle, onError: (error: Error) => void) {
    this.map = map;
    this.onError = onError;
  }

  /** Applies `content` to the loaded style, and to each style from now on. */
  setContent(content: MapContent | undefined): void {
    this.content = content;
    this.schedule();
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

  private reset(): void {
    this.generation++;
    this.loaded = false;
    this.base = undefined;
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
        this.base = base;
        this.stack = base.map((layer: StyleLayerInfo) => layer.id);
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
      console.error(`MapLibre: onMapError threw: ${(thrown as Error).message}`);
    }
  }

  private check(generation: number): void {
    if (generation !== this.generation) {
      throw new Stale();
    }
  }

  // Runs a command, reports its failure, and returns whether it succeeded.
  private async run(generation: number, what: string, command: Promise<CommandCompletion>): Promise<boolean> {
    let succeeded = true;
    try {
      await command;
    } catch (error) {
      succeeded = false;
      this.check(generation);
      this.report(new Error(`Content: ${what} failed: ${(error as Error).message}`));
    }
    this.check(generation);
    return succeeded;
  }

  private async apply(content: MapContent | undefined, generation: number): Promise<void> {
    const map = this.map;
    const sources = new Map<string, MapSource>();
    for (const source of content?.sources ?? []) {
      sources.set(source.id, source);
    }
    const layers = new Map<string, MapLayer>();
    for (const layer of content?.layers ?? []) {
      layers.set(layer.id, layer);
    }
    const images = new Map<string, MapImage>();
    for (const image of content?.images ?? []) {
      images.set(image.id, image);
    }

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
        await this.run(generation, `removing layer ${id}`, map.removeStyleLayer(id));
      }
    }
    // A source that the map won't remove, such as one that a layer the app
    // added still uses, stays the content's, to remove on a later pass.
    for (const id of Array.from(replaced)) {
      if (await this.run(generation, `removing source ${id}`, map.removeStyleSource(id))) {
        this.sources.delete(id);
      }
    }

    for (const source of Array.from(sources.values())) {
      if (!(replaced.has(source.id) && this.sources.has(source.id))) {
        await this.applySource(source, generation);
      }
    }

    for (const id of Array.from(this.rejectedImages)) {
      if (!images.has(id)) {
        this.rejectedImages.delete(id);
      }
    }
    for (const id of Array.from(this.images.keys())) {
      if (!images.has(id)) {
        this.images.delete(id);
        await this.run(generation, `removing image ${id}`, map.removeStyleImage(id));
      }
    }
    for (const image of Array.from(images.values())) {
      const applied = this.images.get(image.id);
      if (applied === undefined && !this.rejectedImages.has(image.id)) {
        // An image that the base style or the app has stays theirs.
        const existing = await map.getStyleImage(image.id).catch(() => undefined);
        this.check(generation);
        if (existing !== undefined) {
          this.rejectedImages.add(image.id);
          this.report(new Error(`Content: adding image ${image.id} failed: the style already has it`));
        }
      }
      if (this.rejectedImages.has(image.id)) {
        continue;
      }
      if (applied === undefined || applied.image !== image.image ||
        JSON.stringify(applied.options) !== JSON.stringify(image.options)) {
        this.images.set(image.id, image);
        await this.run(generation, `setting image ${image.id}`,
          map.setStyleImage(image.id, image.image, image.options));
      }
    }

    // Each group of layers under the same base layer, from its top down: each
    // layer goes directly under the one above it.
    const groups = new Map<string, MapLayer[]>();
    for (const layer of Array.from(layers.values())) {
      const before = this.resolve(layer.below);
      const group = groups.get(before) ?? [];
      group.push(layer);
      groups.set(before, group);
    }
    for (const before of Array.from(groups.keys())) {
      const group = groups.get(before) ?? [];
      let above = before;
      for (let i = group.length - 1; i >= 0; i--) {
        if (await this.applyLayer(group[i], above, generation)) {
          above = group[i].id;
        }
      }
    }
  }

  private async applySource(source: MapSource, generation: number): Promise<void> {
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
      if (await this.run(generation, `adding source ${source.id}`, map.addStyleSourceJson(source.id, source.json))) {
        this.sources.set(source.id, { shape: shape, value: value, data: data });
        this.rejectedSources.delete(source.id);
      } else {
        this.rejectedSources.set(source.id, key);
      }
    } else if (applied.data !== data) {
      // Only a GeoJSON source's data changed. New data takes the options the
      // source has.
      this.sources.set(source.id, { shape: shape, value: value, data: data });
      if (typeof value === 'string') {
        await this.run(generation, `setting the URL of source ${source.id}`,
          map.setGeoJsonSourceUrl(source.id, value));
        return;
      }
      await this.run(generation, `setting the data of source ${source.id}`,
        setGeoJsonData(map, source.id, value, () => this.check(generation)));
    } else {
      applied.value = value;
    }
  }

  // Adds the layer under `above`, or changes it and moves it there, and returns
  // whether the style has it.
  private async applyLayer(layer: MapLayer, above: string, generation: number): Promise<boolean> {
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
      const added = await this.run(generation, `adding layer ${layer.id}`,
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
        await this.run(generation, `setting ${name} of layer ${layer.id}`,
          map.setStyleLayerProperty(layer.id, name, value));
      }
    }
    const index = this.stack.indexOf(layer.id);
    const current = index + 1 < this.stack.length ? this.stack[index + 1] : '';
    if (current !== above) {
      this.stack.splice(index, 1);
      this.insert(layer.id, above);
      await this.run(generation, `moving layer ${layer.id}`,
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

  // The base layer that a layer goes under, or '' for the top.
  private resolve(below: string | LayerPredicate | undefined): string {
    const base: readonly StyleLayerInfo[] = this.base ?? [];
    let found: StyleLayerInfo | undefined = undefined;
    if (typeof below === 'string') {
      found = base.find((layer: StyleLayerInfo) => layer.id === below);
    } else if (below !== undefined) {
      found = base.find(below);
    }
    return found?.id ?? '';
  }
}

// Replaces a GeoJSON source's data with data prepared with the source's own
// options, which FFI requires. `check` throws if the pass ended while it read
// them.
async function setGeoJsonData(map: MapHandle, id: string, data: Object,
  check: () => void): Promise<CommandCompletion> {
  const info = await map.getStyleSource(id);
  check();
  const prepared = GeoJsonSourceDataHandle.create(data, info?.geoJson);
  try {
    return await map.setGeoJsonSourceData(id, prepared);
  } finally {
    prepared.release();
  }
}

function textOf(value: Object | null | undefined): string {
  if (value instanceof Expression) {
    return value.toString();
  }
  return value === undefined ? '' : JSON.stringify(value);
}

// A source's JSON without its data, as text.
function shapeOf(source: MapSource): string {
  const shape: Record<string, Object> = {};
  for (const key of Object.keys(source.json)) {
    if (key !== 'data') {
      shape[key] = source.json[key];
    }
  }
  return JSON.stringify(shape);
}

function layerShape(layer: MapLayer): string {
  return JSON.stringify([layer.type, layer.source ?? '', layer.sourceLayer ?? '']);
}

// The properties that setStyleLayerProperty() sets, by name.
function propertiesOf(layer: MapLayer): Map<string, Object | null> {
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

function layerJson(layer: MapLayer): Record<string, Object> {
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
