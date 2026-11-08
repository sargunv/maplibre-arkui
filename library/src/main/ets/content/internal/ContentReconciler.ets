// The reconciler that applies the map content that an app declares for a
// MaplibreMap or a snapshot to a map's style. After MapLibre Compose's
// StyleReconciler, much simplified.

import { CommandCompletion, MapHandle, StyleLayerInfo } from '@maplibre/native-ffi';

import { Expression } from '../../expression/Expressions';
import { resolveColor } from '../../expression/internal/Colors';
import { FONT_SCALE_STATE } from '../../expression/internal/FontScale';
import { ColorRef, ImageRef, refsOf, StyleRef } from '../../expression/internal/StyleRefs';
import { GeoJsonFeature } from '../../geometry/GeoJson';
import { MapClickEvent } from '../../map/MapClickEvent';
import { ContentError, MapError } from '../../map/MapError';
import { logError } from '../../runtime/internal/Log';
import { MapContent } from '../MapContent';
import { StyleImageSource } from '../StyleImage';
import { FeatureClickEvent, LayerPredicate, LayerSummary, StyleLayer } from '../StyleLayer';
import { StyleSource } from '../StyleSource';
import { StyleImagePixels, stylePixels } from './StyleImages';

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
 * MapView and renderSnapshot() own one for their map.
 *
 * Each pass compares the latest content with what the reconciler added to the
 * current style and awaits each command, so it knows what the style holds. A
 * source or layer that the map rejects is reported and left out until its
 * definition changes; the rest of the content still applies.
 */
export class ContentReconciler {
  private readonly map: MapHandle;
  private readonly onError: (error: Error) => void;
  // The pixel ratio of a pixel map, and the UI that draws resources, if any.
  private readonly pixelRatio: number;
  private readonly context: UIContext | undefined;
  private content: MapContent | undefined = undefined;
  // Counts the styles, so a pass stops once its style is gone.
  private generation: number = 0;
  private loaded: boolean = false;
  // The current style's own layers, bottom to top, and every layer it has.
  private base: LayerSummary[] | undefined = undefined;
  private stack: string[] = [];
  private sources: Map<string, AppliedSource> = new Map<string, AppliedSource>();
  private layers: Map<string, AppliedLayer> = new Map<string, AppliedLayer>();
  // The global state value of each resource color in the current style, the
  // images of expressions that it has, with the color mode that each was drawn
  // in, and those that the map couldn't draw or take.
  private colors: Map<string, string> = new Map<string, string>();
  private images: Map<string, number> = new Map<string, number>();
  private failedImages: Set<string> = new Set<string>();
  // The colors and images of what the app set through the style API, which the
  // current style keeps.
  private styleRefs: Map<string, StyleRef[]> = new Map<string, StyleRef[]>();
  // Counts the color modes, so an image drawn in the last one is drawn again.
  private colorMode: number = 0;
  // What the map rejected, by ID, as text, so a pass skips it until it changes.
  private rejectedSources: Map<string, string> = new Map<string, string>();
  private rejectedLayers: Map<string, string> = new Map<string, string>();
  // The invalid hitPadding of each layer that has one, as text, which a pass
  // reports once.
  private invalidPaddings: Map<string, string> = new Map<string, string>();
  // Counts the adds and removals of each source and layer ID in the current
  // style, so the style API's handles know whether theirs is still there.
  private sourceVersions: Map<string, number> = new Map<string, number>();
  private layerVersions: Map<string, number> = new Map<string, number>();
  // The sources that the app added through the style API, and those of them
  // that the content has declared since, which a pass removes before it adds
  // the content's.
  private appSources: Set<string> = new Set<string>();
  private displaced: Set<string> = new Set<string>();
  private passes: Promise<void> = Promise.resolve();
  private queued: boolean = false;
  // The font scale that fp() reads, and the one the current style has.
  private fontScale: number = 1;
  private appliedFontScale: number | undefined = undefined;

  constructor(map: MapHandle, onError: (error: Error) => void, pixelRatio: number,
    context: UIContext | undefined) {
    this.map = map;
    this.onError = onError;
    this.pixelRatio = pixelRatio;
    this.context = context;
  }

  /** The pixels of an image, as this reconciler's map takes them. */
  stylePixels(source: StyleImageSource, drawAsSdf: boolean): Promise<StyleImagePixels> {
    return stylePixels(source, drawAsSdf, this.pixelRatio, this.context);
  }

  /**
   * The system's color mode changed, so resource colors and the images that
   * ArkUI draws get their values again.
   */
  colorModeChanged(): void {
    this.colorMode++;
    this.failedImages.clear();
    this.schedule();
  }

  /**
   * The app set the property `owner` to a value that uses `refs` through the
   * style API, in place of what it set before.
   */
  trackRefs(owner: string, refs: StyleRef[]): void {
    if (refs.length > 0) {
      this.styleRefs.set(owner, refs);
    } else if (!this.styleRefs.delete(owner)) {
      return;
    }
    this.schedule();
  }

  /** Applies `content` to the loaded style, and to each style from now on. */
  setContent(content: MapContent | undefined): void {
    this.content = content;
    // A source of the app's that the content declares is the content's from
    // now on, and the app's handles to it expire.
    for (const source of content?.sources ?? []) {
      if (this.appSources.delete(source.id)) {
        this.displaced.add(source.id);
        bump(this.sourceVersions, source.id);
      }
    }
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

  /** Whether the latest content has a source with this ID. */
  ownsSource(id: string): boolean {
    return (this.content?.sources ?? []).some((source: StyleSource) => source.id === id);
  }

  /** Whether the latest content has a layer with this ID. */
  ownsLayer(id: string): boolean {
    return (this.content?.layers ?? []).some((layer: StyleLayer) => layer.id === id);
  }

  /** Counts the adds and removals of the source with this ID in the current style. */
  sourceVersion(id: string): number {
    return this.sourceVersions.get(id) ?? 0;
  }

  /** Counts the adds and removals of the layer with this ID in the current style. */
  layerVersion(id: string): number {
    return this.layerVersions.get(id) ?? 0;
  }

  /**
   * The app added a source through the style API. A content layer that waits
   * for a source with its ID tries again, on the pass that this settles after.
   * A source that the content declared while the app added it is the
   * content's.
   */
  appSourceAdded(id: string): Promise<void> {
    if (this.ownsSource(id)) {
      this.displaced.add(id);
    } else {
      this.appSources.add(id);
    }
    bump(this.sourceVersions, id);
    return this.schedule();
  }

  /** The app removed a source through the style API. */
  sourceRemoved(id: string): void {
    this.appSources.delete(id);
    bump(this.sourceVersions, id);
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
    this.colors.clear();
    this.images.clear();
    this.failedImages.clear();
    this.styleRefs.clear();
    this.rejectedSources.clear();
    this.rejectedLayers.clear();
    this.sourceVersions.clear();
    this.layerVersions.clear();
    this.appSources.clear();
    this.displaced.clear();
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
      const content = this.content;
      const refs = this.refsOf(content);
      await this.applyRefs(refs, generation);
      await this.apply(content, generation);
      // After the layers that used them change.
      for (const name of Array.from(this.images.keys())) {
        if (!refs.has(name)) {
          this.images.delete(name);
          await this.run(generation, undefined, `removing image ${name}`, this.map.removeStyleImage(name));
        }
      }
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
    this.checkPaddings(layers);

    // A rejected source that the content dropped no longer holds back the
    // layers over a source of that ID.
    for (const id of Array.from(this.rejectedSources.keys())) {
      if (!sources.has(id)) {
        this.rejectedSources.delete(id);
      }
    }

    // Sources that go or that change more than their data take their layers
    // with them, as do the app's sources that the content now declares.
    const replaced = new Set<string>(this.displaced);
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
        if (await this.run(generation, id, `removing layer ${id}`, map.removeStyleLayer(id))) {
          bump(this.layerVersions, id);
        }
      }
    }
    // A source that the map won't remove, such as one that a layer the app
    // added still uses, stays the content's, to remove on a later pass.
    for (const id of Array.from(replaced)) {
      if (await this.run(generation, id, `removing source ${id}`, map.removeStyleSource(id))) {
        this.sources.delete(id);
        // The content's source, which the map may have rejected while the
        // app's held the ID, goes in next.
        if (this.displaced.delete(id)) {
          this.rejectedSources.delete(id);
        }
        bump(this.sourceVersions, id);
      }
    }

    for (const source of Array.from(sources.values())) {
      if (!(replaced.has(source.id) && this.sources.has(source.id))) {
        await this.applySource(source, generation);
      }
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
        bump(this.sourceVersions, source.id);
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

  // The colors and images that the content's layers and the style API's values
  // use, by name.
  private refsOf(content: MapContent | undefined): Map<string, StyleRef> {
    const refs = new Map<string, StyleRef>();
    this.styleRefs.forEach((list: StyleRef[]) => list.forEach((ref: StyleRef) => refs.set(ref.name, ref)));
    const add = (value: Object | null | undefined): void => {
      refsOf(value).forEach((ref: StyleRef) => refs.set(ref.name, ref));
    };
    for (const layer of content?.layers ?? []) {
      add(layer.filter);
      Object.values(layer.paint ?? {}).forEach(add);
      Object.values(layer.layout ?? {}).forEach(add);
    }
    return refs;
  }

  // Sets each resource color's value, and adds each image that the style lacks,
  // before the layers that use them.
  private async applyRefs(refs: Map<string, StyleRef>, generation: number): Promise<void> {
    for (const ref of Array.from(refs.values())) {
      if (ref instanceof ColorRef) {
        let value: string;
        try {
          value = resolveColor(ref.color).rgba();
        } catch (error) {
          this.report(new MapError(`Content: ${(error as Error).message}`));
          continue;
        }
        if (this.colors.get(ref.name) !== value) {
          this.colors.set(ref.name, value);
          await this.run(generation, undefined, `setting the color ${ref.name}`,
            this.map.setGlobalStateProperty(ref.name, value));
        }
      } else if (ref instanceof ImageRef) {
        await this.applyImage(ref, generation);
      }
    }
  }

  private async applyImage(ref: ImageRef, generation: number): Promise<void> {
    const applied = this.images.get(ref.name);
    if ((applied !== undefined && (!ref.drawn || applied === this.colorMode)) || this.failedImages.has(ref.name)) {
      return;
    }
    const colorMode = this.colorMode;
    let pixels: StyleImagePixels;
    try {
      pixels = await this.stylePixels(ref.source, ref.drawAsSdf);
    } catch (error) {
      this.check(generation);
      this.failedImages.add(ref.name);
      this.report(new MapError(`Content: drawing an image failed: ${(error as Error).message}`));
      return;
    }
    this.check(generation);
    if (await this.run(generation, undefined, `setting the image ${ref.name}`,
      this.map.setStyleImage(ref.name, pixels.pixels,
        { pixelRatio: pixels.pixelRatio, sdf: ref.drawAsSdf, keepUnused: true }))) {
      this.images.set(ref.name, colorMode);
    } else {
      this.failedImages.add(ref.name);
    }
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
      // goes elsewhere, or its source comes, goes, or changes, such as when
      // the app adds a source that the layer draws.
      const json = layerJson(layer);
      const source = layer.source ?? '';
      const key = `${JSON.stringify(json)}@${above}@${this.sources.get(source)?.shape ?? ''}#` +
        `${this.sourceVersion(source)}`;
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
      bump(this.layerVersions, layer.id);
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

function bump(versions: Map<string, number>, id: string): void {
  versions.set(id, (versions.get(id) ?? 0) + 1);
}

export function summaryOf(info: StyleLayerInfo): LayerSummary {
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
