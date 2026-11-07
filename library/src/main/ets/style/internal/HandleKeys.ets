// What a style handle acts on. The handles' constructors take it, and only the
// library can make one, so apps can't construct handles.

import {
  CommandCompletion,
  MapHandle,
  StyleLayerInfo,
  StyleSourceInfo,
  StyleSourceType,
} from '@maplibre/native-ffi';

import { summaryOf } from '../../content/internal/ContentReconciler';
import { LayerSummary } from '../../content/StyleLayer';
import { LoadedStyle } from './LoadedStyle';
import { checkOwned, write } from './StyleCommands';

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

// A source handle holds while its style is the controller's and its source is
// the one it was made for: the add or removal that the map applied last.
export class SourceKey {
  readonly id: string;
  readonly type: string;
  readonly attribution: string;
  readonly style: LoadedStyle;
  private readonly current: () => LoadedStyle | undefined;
  private readonly version: number;

  constructor(current: () => LoadedStyle | undefined, style: LoadedStyle, info: StyleSourceInfo) {
    this.id = info.id;
    this.type = SOURCE_TYPES.get(info.type) ?? 'unknown';
    this.attribution = info.attribution;
    this.style = style;
    this.current = current;
    this.version = style.reconciler.sourceVersion(info.id);
  }

  holds(): boolean {
    return this.current() === this.style && this.style.reconciler.sourceVersion(this.id) === this.version;
  }

  // Sends a write to the source while the handle holds, and throws for a
  // source of the content.
  send(what: string, command: (map: MapHandle) => Promise<CommandCompletion>): Promise<boolean> {
    if (!this.holds()) {
      return Promise.resolve(false);
    }
    checkOwned(this.style.reconciler.ownsSource(this.id), 'source', this.id);
    return write(() => this.holds(), what, () => command(this.style.map));
  }
}

// The key of each source handle, which its subclasses' methods read.
const sourceKeys: WeakMap<Object, SourceKey> = new WeakMap<Object, SourceKey>();

export function registerSourceKey(handle: Object, key: SourceKey): void {
  sourceKeys.set(handle, key);
}

export function sourceKeyOf(handle: Object): SourceKey {
  return sourceKeys.get(handle)!;
}

// A layer handle holds while its style is the controller's and its layer is
// the one it was made for.
export class LayerKey {
  readonly summary: LayerSummary;
  readonly style: LoadedStyle;
  private readonly current: () => LoadedStyle | undefined;
  private readonly version: number;

  constructor(current: () => LoadedStyle | undefined, style: LoadedStyle, info: StyleLayerInfo) {
    this.summary = summaryOf(info);
    this.style = style;
    this.current = current;
    this.version = style.reconciler.layerVersion(info.id);
  }

  holds(): boolean {
    return this.current() === this.style && this.style.reconciler.layerVersion(this.summary.id) === this.version;
  }
}
