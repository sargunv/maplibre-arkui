// The style API that a MapController gives: MapStyle and its handles, which
// act on the style that the map showing the controller has loaded.

import {
  CommandCompletion,
  StyleLayerInfo,
  StyleSourceInfo,
  StyleSourceType,
  StyleTransitionOptions as FfiTransitionOptions,
} from '@maplibre/native-ffi';
import image from '@ohos.multimedia.image';

import { summaryOf } from '../../content/internal/ContentReconciler';
import { readPixelMap } from '../../content/internal/PixelMaps';
import { StyleImage } from '../../content/StyleImage';
import { StyleSource } from '../../content/StyleSource';
import { GeoJsonObject } from '../../geometry/GeoJson';
import { LatLng } from '../../geometry/Geometry';
import { checkLatLng } from '../../geometry/internal/FfiGeometry';
import { LayerHandle } from '../LayerHandle';
import { MapStyle, StyleTransitionOptions } from '../MapStyle';
import { GeoJsonSourceHandle, ImageSourceHandle, SourceHandle } from '../SourceHandle';
import { LoadedStyle } from './LoadedStyle';

// The library's IDs start with this, and its global state names with it and a
// colon.
const RESERVED = 'maplibre-arkui';
// The properties that a layer keeps for its life.
const FIXED_PROPERTIES = ['id', 'type', 'source', 'source-layer'];
// MapLibre Native's transition when the style sets none.
const DEFAULT_TRANSITION_MS = 300;

// The style spec's names of FFI's source types, and MapLibre Native's for the
// types outside the spec.
const SOURCE_TYPES: Map<number, string> = new Map<number, string>([
  [StyleSourceType.vector, 'vector'],
  [StyleSourceType.raster, 'raster'],
  [StyleSourceType.rasterDem, 'raster-dem'],
  [StyleSourceType.geoJson, 'geojson'],
  [StyleSourceType.image, 'image'],
  [StyleSourceType.video, 'video'],
  [StyleSourceType.annotations, 'annotations'],
  [StyleSourceType.customGeometry, 'custom-geometry'],
  [StyleSourceType.customVector, 'custom-vector'],
]);

function reservedId(id: string): boolean {
  return id.startsWith(RESERVED);
}

function reservedName(name: string): boolean {
  return name.startsWith(`${RESERVED}:`);
}

function checkId(kind: string, id: string): void {
  if (reservedId(id)) {
    throw new Error(`The library owns the ${kind}s whose IDs start with ${RESERVED}: ${id}`);
  }
}

function checkOwned(owned: boolean, kind: string, id: string): void {
  if (owned) {
    throw new Error(`The map's content has the ${kind} ${id}, so change it in the content instead`);
  }
}

function failed(what: string, error: Error): Error {
  return new Error(`Style: ${what} failed: ${error.message}`);
}

// Sends a write, which resolves true once the map applies it. A write that
// fails once `holds` no longer does resolves false; another failure rejects
// with what failed.
function write(holds: () => boolean, what: string, send: () => Promise<CommandCompletion>): Promise<boolean> {
  let sent: Promise<CommandCompletion>;
  try {
    sent = send();
  } catch (error) {
    return Promise.reject(failed(what, error as Error));
  }
  return sent.then((): boolean => true, (error: Error): boolean => {
    if (!holds()) {
      return false;
    }
    throw failed(what, error);
  });
}

// Sends a read, which resolves what `then` makes of the answer, or undefined
// once `holds` no longer does. A failure rejects as a write's does.
function read<T, R>(holds: () => boolean, what: string, send: () => Promise<T>,
  then: (value: T) => R | undefined): Promise<R | undefined> {
  let sent: Promise<T>;
  try {
    sent = send();
  } catch (error) {
    return Promise.reject(failed(what, error as Error));
  }
  return sent.then((value: T): R | undefined => holds() ? then(value) : undefined,
    (error: Error): R | undefined => {
      if (!holds()) {
        return undefined;
      }
      throw failed(what, error);
    });
}

export class StyleApi implements MapStyle {
  // The style that the map showing the controller has loaded, if any.
  readonly current: () => LoadedStyle | undefined;

  constructor(current: () => LoadedStyle | undefined) {
    this.current = current;
  }

  getSource(id: string): Promise<SourceHandle | undefined> {
    return this.findSource(id);
  }

  getGeoJsonSource(id: string): Promise<GeoJsonSourceHandle | undefined> {
    return this.findSource(id).then((source: SourceRef | undefined): GeoJsonSourceHandle | undefined =>
      source instanceof GeoJsonSourceRef ? source as GeoJsonSourceRef : undefined);
  }

  getImageSource(id: string): Promise<ImageSourceHandle | undefined> {
    return this.findSource(id).then((source: SourceRef | undefined): ImageSourceHandle | undefined =>
      source instanceof ImageSourceRef ? source as ImageSourceRef : undefined);
  }

  getSources(): Promise<SourceHandle[] | undefined> {
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(undefined);
    }
    return read(() => this.current() === style, 'listing the sources', () => style.map.listStyleSources(),
      (sources: readonly StyleSourceInfo[]): SourceHandle[] => sources
        .filter((info: StyleSourceInfo) => !reservedId(info.id))
        .map((info: StyleSourceInfo): SourceHandle => this.sourceRef(style, info)));
  }

  addSource(source: StyleSource): Promise<SourceHandle | undefined> {
    checkId('source', source.id);
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(undefined);
    }
    checkOwned(style.reconciler.ownsSource(source.id), 'source', source.id);
    const holds = (): boolean => this.current() === style;
    // The content's layers that draw the source go in before the handle, and
    // the source's version changes before a read sent after the add makes a
    // handle.
    let applied: Promise<void> | undefined = undefined;
    const add = (): Promise<CommandCompletion> => style.map.addStyleSourceJson(source.id, source.json)
      .then((done: CommandCompletion): CommandCompletion => {
        if (holds()) {
          applied = style.reconciler.appSourceAdded(source.id);
        }
        return done;
      });
    return write(holds, `adding source ${source.id}`, add)
      .then(async (added: boolean): Promise<SourceHandle | undefined> => {
        if (!added || applied === undefined) {
          return undefined;
        }
        await applied;
        return holds() ? this.findSource(source.id, style) : undefined;
      });
  }

  getLayer(id: string): Promise<LayerHandle | undefined> {
    const style = this.current();
    if (style === undefined || reservedId(id)) {
      return Promise.resolve(undefined);
    }
    return read(() => this.current() === style, `reading layer ${id}`, () => style.map.getStyleLayer(id),
      (info: StyleLayerInfo | undefined): LayerHandle | undefined =>
        info === undefined ? undefined : new LayerRef(this, style, info));
  }

  getLayers(): Promise<LayerHandle[] | undefined> {
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(undefined);
    }
    return read(() => this.current() === style, 'listing the layers', () => style.map.listStyleLayers(),
      (layers: readonly StyleLayerInfo[]): LayerHandle[] => layers
        .filter((info: StyleLayerInfo) => !reservedId(info.id))
        .map((info: StyleLayerInfo): LayerHandle => new LayerRef(this, style, info)));
  }

  setImage(item: StyleImage): Promise<boolean> {
    checkId('image', item.id);
    const ratio = item.pixelRatio;
    if (ratio !== undefined && !(Number.isFinite(ratio) && ratio > 0)) {
      throw new Error(`An image's pixelRatio must be finite and greater than 0: ${ratio}`);
    }
    const pixels = readPixelMap(item.image);
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(false);
    }
    checkOwned(style.reconciler.ownsImage(item.id), 'image', item.id);
    return write(() => this.current() === style, `setting image ${item.id}`,
      () => style.map.setStyleImage(item.id, pixels,
        { pixelRatio: ratio ?? style.reconciler.pixelRatio, sdf: item.sdf ?? false, keepUnused: true }));
  }

  removeImage(id: string): Promise<boolean> {
    checkId('image', id);
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(false);
    }
    checkOwned(style.reconciler.ownsImage(id), 'image', id);
    return write(() => this.current() === style, `removing image ${id}`, () => style.map.removeStyleImage(id));
  }

  getGlobalState(): Promise<Record<string, Object> | undefined> {
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(undefined);
    }
    return read(() => this.current() === style, 'reading the global state', () => style.map.getGlobalState() as Promise<Object>,
      (value: Object): Record<string, Object> => {
        const all = value as Record<string, Object | null>;
        const state: Record<string, Object> = {};
        for (const name of Object.keys(all)) {
          const property = all[name];
          if (!reservedName(name) && property !== null) {
            state[name] = property;
          }
        }
        return state;
      });
  }

  setGlobalStateProperty(name: string, value: Object | null): Promise<boolean> {
    if (reservedName(name)) {
      throw new Error(`The library owns the global state names that start with ${RESERVED}: ${name}`);
    }
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(false);
    }
    return write(() => this.current() === style, `setting global state ${name}`,
      () => style.map.setGlobalStateProperty(name, value));
  }

  getTransition(): Promise<StyleTransitionOptions | undefined> {
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(undefined);
    }
    return read(() => this.current() === style, 'reading the transition', () => style.map.getStyleTransitionOptions(),
      (options: FfiTransitionOptions): StyleTransitionOptions => ({
        durationMs: options.durationMs ?? DEFAULT_TRANSITION_MS,
        delayMs: options.delayMs ?? 0,
        placementTransitions: options.enablePlacementTransitions ?? true,
      }));
  }

  setTransition(options: StyleTransitionOptions): Promise<boolean> {
    checkDuration('durationMs', options.durationMs);
    checkDuration('delayMs', options.delayMs);
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(false);
    }
    const transition: FfiTransitionOptions = {
      durationMs: options.durationMs,
      delayMs: options.delayMs,
      enablePlacementTransitions: options.placementTransitions,
    };
    return write(() => this.current() === style, 'setting the transition',
      () => style.map.setStyleTransitionOptions(transition));
  }

  getLightProperty(name: string): Promise<Object | undefined> {
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(undefined);
    }
    return read(() => this.current() === style, `reading ${name} of the light`,
      () => style.map.getStyleLightProperty(name) as Promise<Object | undefined>, (value: Object | undefined): Object | undefined => value);
  }

  setLight(light: Record<string, Object>): Promise<boolean> {
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(false);
    }
    return write(() => this.current() === style, 'setting the light', () => style.map.setStyleLightJson(light));
  }

  private findSource(id: string, style: LoadedStyle | undefined = this.current()): Promise<SourceRef | undefined> {
    if (style === undefined || reservedId(id)) {
      return Promise.resolve(undefined);
    }
    return read(() => this.current() === style, `reading source ${id}`, () => style.map.getStyleSource(id),
      (info: StyleSourceInfo | undefined): SourceRef | undefined =>
        info === undefined ? undefined : this.sourceRef(style, info));
  }

  private sourceRef(style: LoadedStyle, info: StyleSourceInfo): SourceRef {
    if (info.type === StyleSourceType.geoJson) {
      return new GeoJsonSourceRef(this, style, info);
    }
    if (info.type === StyleSourceType.image) {
      return new ImageSourceRef(this, style, info);
    }
    return new SourceRef(this, style, info);
  }
}

function checkDuration(name: string, value: number | undefined): void {
  if (value !== undefined && !(Number.isFinite(value) && value >= 0)) {
    throw new Error(`A transition's ${name} must be finite and at least 0: ${value}`);
  }
}

// A handle holds while its style is the controller's and its source is the
// one it was made for: the add or removal that the map applied last.
class SourceRef implements SourceHandle {
  readonly id: string;
  readonly type: string;
  readonly attribution: string;
  protected readonly api: StyleApi;
  protected readonly style: LoadedStyle;
  private readonly version: number;

  constructor(api: StyleApi, style: LoadedStyle, info: StyleSourceInfo) {
    this.id = info.id;
    this.type = SOURCE_TYPES.get(info.type) ?? 'unknown';
    this.attribution = info.attribution;
    this.api = api;
    this.style = style;
    this.version = style.reconciler.sourceVersion(info.id);
  }

  // The source's version changes before a read sent after the removal makes
  // a handle.
  remove(): Promise<boolean> {
    return this.send(`removing source ${this.id}`, () => this.style.map.removeStyleSource(this.id)
      .then((done: CommandCompletion): CommandCompletion => {
        if (this.holds()) {
          this.style.reconciler.sourceRemoved(this.id);
        }
        return done;
      }));
  }

  protected holds(): boolean {
    return this.api.current() === this.style && this.style.reconciler.sourceVersion(this.id) === this.version;
  }

  // Sends a write to the source while the handle holds, and throws for a
  // source of the content.
  protected send(what: string, command: () => Promise<CommandCompletion>): Promise<boolean> {
    if (!this.holds()) {
      return Promise.resolve(false);
    }
    checkOwned(this.style.reconciler.ownsSource(this.id), 'source', this.id);
    return write(() => this.holds(), what, command);
  }
}

class GeoJsonSourceRef extends SourceRef implements GeoJsonSourceHandle {
  setData(data: GeoJsonObject | string): Promise<boolean> {
    const map = this.style.map;
    return this.send(`setting the data of source ${this.id}`, () => typeof data === 'string' ?
      map.setGeoJsonSourceUrl(this.id, data) : map.setGeoJsonSourceData(this.id, data));
  }
}

class ImageSourceRef extends SourceRef implements ImageSourceHandle {
  setImage(pixelMap: image.PixelMap): Promise<boolean> {
    const pixels = readPixelMap(pixelMap);
    return this.send(`setting the image of source ${this.id}`,
      () => this.style.map.setImageSourceImage(this.id, pixels));
  }

  setUrl(url: string): Promise<boolean> {
    return this.send(`setting the URL of source ${this.id}`, () => this.style.map.setImageSourceUrl(this.id, url));
  }

  setCoordinates(coordinates: LatLng[]): Promise<boolean> {
    if (coordinates.length !== 4) {
      throw new Error(`An image source needs its four corners, not ${coordinates.length}`);
    }
    coordinates.forEach((coordinate: LatLng) => checkLatLng(coordinate, 'Each corner of an image source'));
    return this.send(`setting the coordinates of source ${this.id}`,
      () => this.style.map.setImageSourceCoordinates(this.id, coordinates));
  }
}

// A handle holds while its style is the controller's and its layer is the one
// it was made for.
class LayerRef implements LayerHandle {
  id: string;
  type: string;
  source?: string;
  sourceLayer?: string;
  private readonly api: StyleApi;
  private readonly style: LoadedStyle;
  private readonly version: number;

  constructor(api: StyleApi, style: LoadedStyle, info: StyleLayerInfo) {
    const summary = summaryOf(info);
    this.id = summary.id;
    this.type = summary.type;
    this.source = summary.source;
    this.sourceLayer = summary.sourceLayer;
    this.api = api;
    this.style = style;
    this.version = style.reconciler.layerVersion(info.id);
  }

  getProperty(name: string): Promise<Object | undefined> {
    if (!this.holds()) {
      return Promise.resolve(undefined);
    }
    return read(() => this.holds(), `reading ${name} of layer ${this.id}`,
      () => this.style.map.getStyleLayerProperty(this.id, name) as Promise<Object | undefined>,
      (value: Object | undefined): Object | undefined => value);
  }

  setProperty(name: string, value: Object | null): Promise<boolean> {
    if (FIXED_PROPERTIES.includes(name)) {
      throw new Error(`A layer keeps its ${name}, which setProperty() can't change: ${name}`);
    }
    if (!this.holds()) {
      return Promise.resolve(false);
    }
    checkOwned(this.style.reconciler.ownsLayer(this.id), 'layer', this.id);
    // MapLibre Native takes no null for a transition, but an empty one is its
    // default.
    const empty: Record<string, Object> = {};
    const sent: Object | null = value === null && name.endsWith('-transition') ? empty : value;
    return write(() => this.holds(), `setting ${name} of layer ${this.id}`,
      () => this.style.map.setStyleLayerProperty(this.id, name, sent));
  }

  private holds(): boolean {
    return this.api.current() === this.style && this.style.reconciler.layerVersion(this.id) === this.version;
  }
}
