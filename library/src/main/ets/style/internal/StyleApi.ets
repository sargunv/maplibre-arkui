// The style API that a MapController gives, which acts on the style that the
// map showing the controller has loaded, and makes the handles of its layers
// and sources.

import {
  CommandCompletion,
  Status,
  StyleLayerInfo,
  StyleSourceInfo,
  StyleSourceType,
  StyleTransitionOptions as FfiTransitionOptions,
} from '@maplibre/native-ffi';

import { readPixelMap } from '../../content/internal/PixelMaps';
import { StyleImage } from '../../content/StyleImage';
import { StyleSource } from '../../content/StyleSource';
import { LayerHandle } from '../LayerHandle';
import { MapStyle, StyleTransitionOptions } from '../MapStyle';
import { GeoJsonSourceHandle, ImageSourceHandle, SourceHandle, VectorSourceHandle } from '../SourceHandle';
import { LayerKey, SourceKey } from './HandleKeys';
import { LoadedStyle } from './LoadedStyle';
import {
  checkId,
  checkOwned,
  failedWith,
  propertyValue,
  read,
  RESERVED,
  reservedId,
  reservedName,
  write,
} from './StyleCommands';

// MapLibre Native's transition when the style sets none.
const DEFAULT_TRANSITION_MS = 300;

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
    return this.findSource(id).then((source: SourceHandle | undefined): GeoJsonSourceHandle | undefined =>
      source instanceof GeoJsonSourceHandle ? source as GeoJsonSourceHandle : undefined);
  }

  getImageSource(id: string): Promise<ImageSourceHandle | undefined> {
    return this.findSource(id).then((source: SourceHandle | undefined): ImageSourceHandle | undefined =>
      source instanceof ImageSourceHandle ? source as ImageSourceHandle : undefined);
  }

  getVectorSource(id: string): Promise<VectorSourceHandle | undefined> {
    return this.findSource(id).then((source: SourceHandle | undefined): VectorSourceHandle | undefined =>
      source instanceof VectorSourceHandle ? source as VectorSourceHandle : undefined);
  }

  getSources(): Promise<SourceHandle[] | undefined> {
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(undefined);
    }
    return read(() => this.current() === style, 'listing the sources', () => style.map.listStyleSources(),
      (sources: readonly StyleSourceInfo[]): SourceHandle[] => sources
        .filter((info: StyleSourceInfo) => !reservedId(info.id))
        .map((info: StyleSourceInfo): SourceHandle => this.sourceHandle(style, info)));
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
        info === undefined ? undefined : new LayerHandle(new LayerKey(this.current, style, info)));
  }

  getLayers(): Promise<LayerHandle[] | undefined> {
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(undefined);
    }
    return read(() => this.current() === style, 'listing the layers', () => style.map.listStyleLayers(),
      (layers: readonly StyleLayerInfo[]): LayerHandle[] => layers
        .filter((info: StyleLayerInfo) => !reservedId(info.id))
        .map((info: StyleLayerInfo): LayerHandle => new LayerHandle(new LayerKey(this.current, style, info))));
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
    // The app can't know which images the sprite has, so one that the style
    // doesn't have is an answer, not a failure.
    return write(() => this.current() === style, `removing image ${id}`, () => style.map.removeStyleImage(id),
      (error: Error): boolean => failedWith(error, Status.notFound));
  }

  getGlobalStateProperty(name: string): Promise<Object | undefined> {
    const style = this.current();
    if (style === undefined || reservedName(name)) {
      return Promise.resolve(undefined);
    }
    return read(() => this.current() === style, `reading global state ${name}`,
      () => style.map.getGlobalState() as Promise<Object>,
      (value: Object): Object | undefined => Object.keys(value).includes(name) ?
        (value as Record<string, Object | null>)[name] ?? undefined : undefined);
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
      () => style.map.getStyleLightProperty(name) as Promise<Object | undefined>,
      (value: Object | undefined): Object | undefined => value);
  }

  setLightProperty(name: string, value: Object | null): Promise<boolean> {
    const style = this.current();
    if (style === undefined) {
      return Promise.resolve(false);
    }
    return write(() => this.current() === style, `setting ${name} of the light`,
      () => style.map.setStyleLightProperty(name, propertyValue(name, value)));
  }

  private findSource(id: string, style: LoadedStyle | undefined = this.current()): Promise<SourceHandle | undefined> {
    if (style === undefined || reservedId(id)) {
      return Promise.resolve(undefined);
    }
    return read(() => this.current() === style, `reading source ${id}`, () => style.map.getStyleSource(id),
      (info: StyleSourceInfo | undefined): SourceHandle | undefined =>
        info === undefined ? undefined : this.sourceHandle(style, info));
  }

  private sourceHandle(style: LoadedStyle, info: StyleSourceInfo): SourceHandle {
    const key = new SourceKey(this.current, style, info);
    if (info.type === StyleSourceType.geoJson) {
      return new GeoJsonSourceHandle(key);
    }
    if (info.type === StyleSourceType.image) {
      return new ImageSourceHandle(key);
    }
    if (info.type === StyleSourceType.vector) {
      return new VectorSourceHandle(key);
    }
    return new SourceHandle(key);
  }
}

function checkDuration(name: string, value: number | undefined): void {
  if (value !== undefined && !(Number.isFinite(value) && value >= 0)) {
    throw new Error(`A transition's ${name} must be finite and at least 0: ${value}`);
  }
}
