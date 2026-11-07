import { beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  ContentError,
  eq,
  fp,
  GeoJsonFeatureCollection,
  GeoJsonGeometry,
  get,
  LayerPredicate,
  LayerSummary,
  MapContent,
  MapError,
  renderSnapshot,
  StyleLayer,
} from '@maplibre/arkui';
import { ContentReconciler } from '@maplibre/arkui/src/main/ets/content/internal/ContentReconciler';
import { MapHandle, StyleLayerInfo, StyleLayerVisibility } from '@maplibre/native-ffi';
import application from '@ohos.app.ability.application';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';

import { backgroundStyle, STYLE, styleDocument, testMap } from '../testability/TestMaps';
import { eventually, expectNear, frames, pixelAt, readPixels, setStyle, until, withMap } from './helpers';

// A base style with a layer to place content under, as an app places it under
// labels.
function baseStyle(color: string): Record<string, Object> {
  return styleDocument('{"version":8,"sources":{"base":{"type":"geojson","data":{"type":"FeatureCollection",' +
    `"features":[]}}},"layers":[{"id":"background","type":"background","paint":{"background-color":"${color}"}},` +
    '{"id":"labels","type":"symbol","source":"base"}]}');
}

const BASE = baseStyle('#4a90d9');

const TWO: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', id: 1, geometry: { type: 'Point', coordinates: [20, 10] }, properties: { 'n': 1 } },
    { type: 'Feature', id: 2, geometry: { type: 'Point', coordinates: [-40, -20] }, properties: { 'n': 2 } },
  ],
};

const THREE: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: TWO.features.concat([
    { type: 'Feature', id: 3, geometry: { type: 'Point', coordinates: [60, 30] }, properties: { 'n': 3 } },
  ]),
};

const WEST: GeoJsonGeometry = {
  type: 'Polygon',
  coordinates: [[[-180, -85], [0, -85], [0, 85], [-180, 85], [-180, -85]]],
};

// How the map reads back '#00ff00'.
const GREEN = '["rgba",0,255,0,1]';

function circles(id: string, color: string, below?: string | LayerPredicate): StyleLayer {
  return { id: id, type: 'circle', source: 'places', paint: { 'circle-color': color, 'circle-radius': 6 }, below: below };
}

// The places source, with `data` as GeoJSON or a URL.
function content(data: GeoJsonFeatureCollection | string, layers: StyleLayer[]): MapContent {
  return { sources: [{ id: 'places', json: { 'type': 'geojson', 'data': data } }], layers: layers };
}

// A pixel map of one opaque pixel, in `format`.
function pixel(r: number, g: number, b: number,
  format: image.PixelMapFormat = image.PixelMapFormat.RGBA_8888): image.PixelMap {
  return image.createPixelMapSync(new Uint8Array([r, g, b, 255]).buffer, {
    size: { width: 1, height: 1 },
    srcPixelFormat: image.PixelMapFormat.RGBA_8888,
    pixelFormat: format,
  });
}

// Whether the map reported a ContentError for `id`.
function contentFailed(id: string): boolean {
  return testMap.failures.some((error: MapError) => error instanceof ContentError && error.id === id);
}

// How many features the places source has, once it has `expected`.
async function untilFeatures(expected: number): Promise<void> {
  await eventually(`the source has ${expected} features`, async () => {
    const features = await testMap.controller.querySourceFeatures('places');
    return features?.length === expected ? true : undefined;
  });
}

// The blur of layer `id`, which the content doesn't set, as JSON.
async function blur(id: string): Promise<string> {
  return JSON.stringify(await withMap((ffi: MapHandle) => ffi.getStyleLayerProperty(id, 'circle-blur')));
}

// Sets a property that the content doesn't, which a layer keeps only while
// the map changes it in place.
async function markLayer(id: string): Promise<void> {
  await withMap((ffi: MapHandle) => ffi.setStyleLayerProperty(id, 'circle-blur', 0.5));
}

async function marked(id: string): Promise<boolean> {
  return JSON.stringify(await withMap((ffi: MapHandle) => ffi.getStyleLayerProperty(id, 'circle-blur'))) === '0.5';
}

async function layerInfo(id: string): Promise<StyleLayerInfo> {
  const info = await withMap((ffi: MapHandle) => ffi.getStyleLayer(id));
  if (info === undefined) {
    throw new Error(`The style has no layer ${id}`);
  }
  return info;
}

// The circles layers, many of them, for a pass that takes a while.
function manyCircles(count: number): StyleLayer[] {
  const layers: StyleLayer[] = [];
  for (let i = 0; i < count; i++) {
    layers.push(circles(`c${i}`, '#ff0000'));
  }
  return layers;
}

async function layerIds(): Promise<string> {
  const layers = await withMap((ffi: MapHandle) => ffi.listStyleLayers());
  return layers.map((layer: StyleLayerInfo) => layer.id).join(',');
}

// Waits until the style's layers are `expected`, bottom to top.
async function untilLayers(expected: string): Promise<void> {
  let last = '';
  try {
    await eventually(`the layers are ${expected}`, async () => {
      last = await layerIds();
      return last === expected ? true : undefined;
    });
  } catch (error) {
    throw new Error(`${(error as Error).message}, not ${last}`);
  }
}

async function untilProperty(layer: string, name: string, expected: string): Promise<void> {
  let last = '';
  try {
    await eventually(`${name} of ${layer} is ${expected}`, async () => {
      // An unset property reads as undefined.
      last = `${JSON.stringify(await withMap((ffi: MapHandle) => ffi.getStyleLayerProperty(layer, name)))}`;
      return last === expected ? true : undefined;
    });
  } catch (error) {
    throw new Error(`${(error as Error).message}, not ${last}`);
  }
}

export default function contentTest(): void {
  describe('Content', () => {
    beforeEach(async () => {
      await testMap.reset(BASE);
    });

    it('adds sources, layers, and images, in order, under base layers', 0, async () => {
      const dot: MapContent = {
        sources: [{ id: 'places', json: { 'type': 'geojson', 'data': TWO } }],
        images: [{ id: 'dot', image: pixel(255, 0, 0) }],
        layers: [
          circles('low', '#ff0000', (layer: LayerSummary) => layer.type === 'symbol'),
          circles('high', '#00ff00'),
          circles('mid', '#0000ff', 'labels'),
        ],
      };
      testMap.content = dot;
      await untilLayers('background,low,mid,labels,high');
      expect((await withMap((ffi: MapHandle) => ffi.getStyleSource('places')))?.id).assertEqual('places');
      const dotImage = await withMap((ffi: MapHandle) => ffi.getStyleImage('dot'));
      expect(dotImage?.width).assertEqual(1);
      expect(dotImage?.pixels[0]).assertEqual(255);
      // At the display's density, and kept while no layer uses it.
      expectNear(dotImage?.pixelRatio ?? 0, testMap.context!.vp2px(1), 0.001);
      expect(dotImage?.keepUnused).assertTrue();
      expect(testMap.errors.length).assertEqual(0);

      testMap.content = {};
      await untilLayers('background,labels');
      expect(await withMap((ffi: MapHandle) => ffi.getStyleSource('places'))).assertUndefined();
      expect(await withMap((ffi: MapHandle) => ffi.getStyleImage('dot'))).assertUndefined();
    });

    it('changes a property in place', 0, async () => {
      testMap.content = content(TWO, [circles('dots', '#ff0000')]);
      await untilLayers('background,labels,dots');
      // A property the content doesn't set, which stays only if the layer does.
      await withMap((ffi: MapHandle) => ffi.setStyleLayerProperty('dots', 'circle-blur', 0.5));

      testMap.content = content(TWO, [circles('dots', '#00ff00')]);
      await untilProperty('dots', 'circle-color', GREEN);
      expect(await blur('dots')).assertEqual('0.5');

      // An expression, and a property the content stops setting.
      const layer: StyleLayer = {
        id: 'dots', type: 'circle', source: 'places', paint: { 'circle-color': get('color') },
      };
      testMap.content = content(TWO, [layer]);
      await untilProperty('dots', 'circle-color', '["to-color",["get","color"]]');
      await untilProperty('dots', 'circle-radius', 'undefined');
      expect(await blur('dots')).assertEqual('0.5');
    });

    it('reorders layers and removes one', 0, async () => {
      testMap.content = content(TWO, [circles('a', '#ff0000'), circles('b', '#00ff00'), circles('c', '#0000ff')]);
      await untilLayers('background,labels,a,b,c');
      testMap.content = content(TWO, [circles('c', '#0000ff'), circles('a', '#ff0000')]);
      await untilLayers('background,labels,c,a');
      testMap.content = content(TWO, [circles('a', '#ff0000'), circles('c', '#0000ff', 'labels')]);
      await untilLayers('background,c,labels,a');
      expect(testMap.errors.length).assertEqual(0);
    });

    it('places layers under content layers, wherever those go', 0, async () => {
      // e under b under a on top, and d under c under labels.
      testMap.content = content(TWO, [
        circles('a', '#ff0000'), circles('b', '#ff0000', 'a'), circles('c', '#ff0000', 'labels'),
        circles('d', '#ff0000', 'c'), circles('e', '#ff0000', 'b'),
      ]);
      await untilLayers('background,d,c,labels,e,b,a');
      await markLayer('e');
      // b and the layer under it follow it under c, after d in the content.
      testMap.content = content(TWO, [
        circles('a', '#ff0000'), circles('b', '#ff0000', 'c'), circles('c', '#ff0000', 'labels'),
        circles('d', '#ff0000', 'c'), circles('e', '#ff0000', 'b'),
      ]);
      await untilLayers('background,e,b,d,c,labels,a');
      expect(await marked('e')).assertTrue();
      // Without c, its layers go on top, as under a missing base layer.
      testMap.content = content(TWO, [
        circles('a', '#ff0000'), circles('b', '#ff0000', 'c'), circles('d', '#ff0000', 'c'),
        circles('e', '#ff0000', 'b'),
      ]);
      await untilLayers('background,labels,a,e,b,d');
      expect(testMap.errors.length).assertEqual(0);
    });

    it('puts layers that name each other in a cycle on top', 0, async () => {
      testMap.content = content(TWO, [
        circles('x', '#ff0000', 'y'), circles('y', '#ff0000', 'x'), circles('z', '#ff0000', 'x'),
        circles('self', '#ff0000', 'self'),
      ]);
      await untilLayers('background,labels,z,x,y,self');
      expect(testMap.errors.length).assertEqual(0);
    });

    it('gives a predicate the base layers, and puts a layer whose predicate throws on top', 0, async () => {
      const seen: LayerSummary[] = [];
      const recordAll: LayerPredicate = (layer: LayerSummary): boolean => {
        seen.push(layer);
        return false;
      };
      const broken: LayerPredicate = (layer: LayerSummary): boolean => {
        throw new Error('broken predicate');
      };
      testMap.content = content(TWO, [circles('low', '#ff0000', recordAll), circles('bad', '#ff0000', broken)]);
      await untilLayers('background,labels,low,bad');
      await until('the map reports the throw', () => testMap.errors.some((error: string) =>
        error.includes('the below predicate of layer bad threw: broken predicate')));
      expect(JSON.stringify(seen.slice(0, 2)))
        .assertEqual('[{"id":"background","type":"background"},{"id":"labels","type":"symbol","source":"base"}]');
    });

    it('reports a negative hitPadding once', 0, async () => {
      const padded = (color: string): StyleLayer => ({
        id: 'dots', type: 'circle', source: 'places', paint: { 'circle-color': color }, hitPadding: -1,
      });
      testMap.content = content(TWO, [padded('#ff0000')]);
      await untilLayers('background,labels,dots');
      testMap.content = content(TWO, [padded('#00ff00')]);
      await untilProperty('dots', 'circle-color', GREEN);
      expect(testMap.errors.filter((error: string) => error.includes('hitPadding of layer dots')).length)
        .assertEqual(1);
    });

    it('sets the font scale that fp() reads on each style, and follows a change', 0, async () => {
      const context = testMap.context!;
      const scale = (): number => context.fp2px(1) / context.vp2px(1);
      const state = async (): Promise<number | undefined> => {
        const global = await withMap((ffi: MapHandle) => ffi.getGlobalState()) as Record<string, Object>;
        return global['maplibre-arkui:font-scale'] as number | undefined;
      };
      await eventually('the map has the font scale', async () => await state() === scale() ? true : undefined);
      await setStyle(baseStyle('#4ad94a'));
      expect(await state()).assertEqual(scale());

      const app = application.getApplicationContext();
      const before = scale();
      app.setFontSizeScale(2);
      try {
        await until('the font scale changes', () => scale() !== before);
        await eventually('the map follows the font scale', async () => await state() === scale() ? true : undefined);
      } finally {
        app.setFontSizeScale(before);
      }
      await eventually('the map follows it back', async () => await state() === before ? true : undefined);
      expect(testMap.errors.length).assertEqual(0);
    });

    it('replaces GeoJSON data in place', 0, async () => {
      await testMap.controller.updateCamera({ zoom: 0 });
      testMap.content = content(TWO, [circles('dots', '#ff0000')]);
      await untilLayers('background,labels,dots');
      await withMap((ffi: MapHandle) => ffi.setStyleLayerProperty('dots', 'circle-blur', 0.5));
      const count = async (expected: number): Promise<boolean | undefined> => {
        const features = await testMap.controller.querySourceFeatures('places');
        return features?.length === expected ? true : undefined;
      };
      await eventually('the source has two features', () => count(2));

      testMap.content = content(THREE, [circles('dots', '#ff0000')]);
      await eventually('the source has three features', () => count(3));
      // A new source would have taken a new layer, without the blur.
      expect(await blur('dots')).assertEqual('0.5');
    });

    it('adds the content to each style', 0, async () => {
      testMap.content = content(TWO, [circles('dots', '#ff0000', 'labels')]);
      await untilLayers('background,dots,labels');
      await setStyle(baseStyle('#4ad94a'));
      // The content is on the style by the time the app hears that it loaded.
      expect(await layerIds()).assertEqual('background,dots,labels');
      expect((await withMap((ffi: MapHandle) => ffi.getStyleSource('places')))?.id).assertEqual('places');
      expect(testMap.errors.length).assertEqual(0);
    });

    it('reports what the map rejects and adds the rest', 0, async () => {
      const lost: StyleLayer = { id: 'lost', type: 'circle', source: 'missing' };
      const taken: StyleLayer = { id: 'background', type: 'circle', source: 'places' };
      testMap.content = content(TWO, [lost, taken, circles('dots', '#ff0000')]);
      await untilLayers('background,labels,dots');
      await until('the map reports both', () => testMap.errors.length >= 2);
      expect(testMap.errors.some((error: string) => error.includes('adding layer lost'))).assertTrue();
      expect(testMap.errors.some((error: string) => error.includes('adding layer background'))).assertTrue();

      // Rejected layers stay out until they change, and then go in.
      const errors = testMap.errors.length;
      testMap.content = content(TWO, [lost, taken, circles('dots', '#00ff00')]);
      await untilProperty('dots', 'circle-color', GREEN);
      expect(testMap.errors.length).assertEqual(errors);
      const found: StyleLayer = { id: 'lost', type: 'circle', source: 'places' };
      testMap.content = content(TWO, [found, taken, circles('dots', '#00ff00')]);
      await untilLayers('background,labels,lost,dots');
    });

    it('adds a layer once the rejected source it waited on leaves', 0, async () => {
      // The base style already has a source called base.
      const dots: StyleLayer = { id: 'dots', type: 'circle', source: 'base' };
      testMap.content = { sources: [{ id: 'base', json: { 'type': 'geojson', 'data': TWO } }], layers: [dots] };
      await until('the map rejects the source', () =>
        testMap.errors.some((error: string) => error.includes('adding source base')));
      testMap.content = { layers: [dots] };
      await untilLayers('background,labels,dots');
    });

    it('retries a rejected layer when its source changes type', 0, async () => {
      const raster: Record<string, Object> = {
        'type': 'raster', 'tiles': ['file:///nonexistent/{z}/{x}/{y}.png'], 'tileSize': 256,
      };
      testMap.content = { sources: [{ id: 'places', json: raster }], layers: [circles('dots', '#ff0000')] };
      await until('the map rejects the layer', () =>
        testMap.errors.some((error: string) => error.includes('adding layer dots')));
      testMap.content = content(TWO, [circles('dots', '#ff0000')]);
      await untilLayers('background,labels,dots');
    });

    it('replaces an image that the style already had, and removes it when it leaves', 0, async () => {
      await withMap((ffi: MapHandle) =>
        ffi.setStyleImage('dot', { width: 2, height: 1, stride: 8, pixels: new Uint8Array(8) }));
      testMap.content = { images: [{ id: 'dot', image: pixel(255, 0, 0) }] };
      await eventually('the content image replaces it', async () =>
        (await withMap((ffi: MapHandle) => ffi.getStyleImage('dot')))?.width === 1 ? true : undefined);
      const empty: MapContent = {};
      testMap.content = empty;
      await eventually('the image goes', async () =>
        (await withMap((ffi: MapHandle) => ffi.getStyleImage('dot')).catch(() => undefined)) === undefined ? true :
          undefined);
      expect(testMap.errors.length).assertEqual(0);
    });

    it('reports a pixel map it can\'t read, draws the rest, and leaves the image ID alone', 0, async () => {
      await withMap((ffi: MapHandle) =>
        ffi.setStyleImage('dot', { width: 3, height: 1, stride: 12, pixels: new Uint8Array(12) }));
      const rgb565 = pixel(255, 0, 0, image.PixelMapFormat.RGB_565);
      const withImage = (color: string): MapContent => ({
        sources: [{ id: 'places', json: { 'type': 'geojson', 'data': TWO } }],
        layers: [circles('dots', color)],
        images: [{ id: 'dot', image: rgb565 }],
      });
      testMap.content = withImage('#ff0000');
      await until('the map reports the image', () => contentFailed('dot'));
      await untilLayers('background,labels,dots');
      // Not again while the pixel map stays the same.
      testMap.content = withImage('#00ff00');
      await untilProperty('dots', 'circle-color', GREEN);
      expect(testMap.failures.filter((error: MapError) => error instanceof ContentError && error.id === 'dot').length)
        .assertEqual(1);
      const empty: MapContent = {};
      testMap.content = empty;
      await untilLayers('background,labels');
      expect((await withMap((ffi: MapHandle) => ffi.getStyleImage('dot')))?.width).assertEqual(3);
      rgb565.release();
    });

    it('removes a source on a later pass once nothing else uses it', 0, async () => {
      testMap.content = content(TWO, []);
      await eventually('the source goes in', async () => withMap((ffi: MapHandle) => ffi.getStyleSource('places')));
      // A layer that the app adds over the content's source keeps the map
      // from removing the source.
      const extra: Record<string, Object> = { 'id': 'extra', 'type': 'circle', 'source': 'places' };
      await withMap((ffi: MapHandle) => ffi.addStyleLayerJson(extra));
      testMap.content = {};
      await until('the map refuses to remove the source', () =>
        testMap.errors.some((error: string) => error.includes('removing source places')));
      await withMap((ffi: MapHandle) => ffi.removeStyleLayer('extra'));
      const empty: MapContent = {};
      testMap.content = empty;
      await eventually('the source goes', async () =>
        (await withMap((ffi: MapHandle) => ffi.getStyleSource('places'))) === undefined ? true :
        undefined);
    });

    it('draws the content in a snapshot', 0, async () => {
      const west: MapContent = {
        sources: [{ id: 'west', json: { 'type': 'geojson', 'data': WEST } }],
        layers: [{ id: 'west', type: 'fill', source: 'west',
          paint: { 'fill-color': '#ff0000', 'fill-antialias': false } }],
      };
      const pixelMap = (await renderSnapshot({
        style: backgroundStyle('#0000ff'), content: west, width: 64, height: 32, pixelRatio: 2,
        camera: { zoom: 0 },
      })).image;
      const pixels = await readPixels(pixelMap);
      // The PixelMap's channels are in RGBA order.
      expect(pixelAt(pixels, 128, 32, 32).join()).assertEqual('255,0,0,255');
      expect(pixelAt(pixels, 128, 96, 32).join()).assertEqual('0,0,255,255');
      await pixelMap.release();
    });
    it('scales fp() sizes by a snapshot\'s font scale', 0, async () => {
      const center: GeoJsonGeometry = { type: 'Point', coordinates: [0, 0] };
      const dot: MapContent = {
        sources: [{ id: 'dot', json: { 'type': 'geojson', 'data': center } }],
        layers: [{ id: 'dot', type: 'circle', source: 'dot', paint: { 'circle-color': '#ff0000', 'circle-radius': fp(8) } }],
      };
      // 12 vp from the dot's center: outside it at 8 vp, inside at 16.
      const edge = async (fontScale?: number): Promise<string> => {
        const pixelMap = (await renderSnapshot({
          style: backgroundStyle('#0000ff'), content: dot, width: 64, height: 32, pixelRatio: 2,
          camera: { center: { latitude: 0, longitude: 0 }, zoom: 0 }, fontScale: fontScale,
        })).image;
        const pixels = await readPixels(pixelMap);
        await pixelMap.release();
        return pixelAt(pixels, 128, 2 * (32 + 12), 32).join();
      };
      expect(await edge()).assertEqual('0,0,255,255');
      expect(await edge(2)).assertEqual('255,0,0,255');
    });

    it('changes the filter, zoom range, and layout in place, and unsets them', 0, async () => {
      const plain: StyleLayer = { id: 'dots', type: 'circle', source: 'places', paint: { 'circle-color': '#ff0000' } };
      testMap.content = content(TWO, [plain]);
      await untilLayers('background,labels,dots');
      await markLayer('dots');

      const set: StyleLayer = {
        id: 'dots', type: 'circle', source: 'places', paint: { 'circle-color': '#ff0000' },
        filter: eq(get('n'), 1), minZoom: 2, maxZoom: 10, layout: { 'visibility': 'none' },
      };
      testMap.content = content(TWO, [set]);
      await eventually('the layer changes', async () => (await layerInfo('dots')).maxZoom === 10 ? true : undefined);
      const changed = await layerInfo('dots');
      expect(changed.minZoom).assertEqual(2);
      expect(changed.visibility).assertEqual(StyleLayerVisibility.none);
      const json = await withMap((ffi: MapHandle) => ffi.getStyleLayerJson('dots')) as Record<string, Object>;
      expect(JSON.stringify(json['filter'])).assertEqual('["==",["get","n"],1]');
      expect(await marked('dots')).assertTrue();

      testMap.content = content(TWO, [plain]);
      await eventually('the layer goes back', async () =>
        (await layerInfo('dots')).maxZoom === Infinity ? true : undefined);
      const unset = await layerInfo('dots');
      expect(unset.minZoom).assertEqual(-Infinity);
      expect(unset.visibility).assertEqual(StyleLayerVisibility.visible);
      const plainJson = await withMap((ffi: MapHandle) => ffi.getStyleLayerJson('dots')) as Record<string, Object>;
      expect(plainJson['filter']).assertUndefined();
      expect(await marked('dots')).assertTrue();
      expect(testMap.errors.length).assertEqual(0);
    });

    it('replaces a layer whose type, source, or source layer changes, where it was', 0, async () => {
      const both: MapContent = {
        sources: [
          { id: 'places', json: { 'type': 'geojson', 'data': TWO } },
          { id: 'others', json: { 'type': 'geojson', 'data': THREE } },
          { id: 'tiles', json: { 'type': 'vector', 'tiles': ['file:///nonexistent/{z}/{x}/{y}.pbf'] } },
        ],
        layers: [circles('a', '#ff0000'), circles('dots', '#ff0000'), circles('c', '#ff0000')],
      };
      testMap.content = both;
      await untilLayers('background,labels,a,dots,c');
      const replace = async (layer: StyleLayer, done: (info: StyleLayerInfo) => boolean): Promise<void> => {
        const layers = [circles('a', '#ff0000'), layer, circles('c', '#ff0000')];
        testMap.content = { sources: both.sources, layers: layers };
        await eventually(`the layer is replaced by ${JSON.stringify(layer)}`, async () =>
          done(await layerInfo('dots')) ? true : undefined);
        expect(await layerIds()).assertEqual('background,labels,a,dots,c');
      };

      await markLayer('dots');
      await replace({ id: 'dots', type: 'circle', source: 'others' },
        (info: StyleLayerInfo) => info.sourceId === 'others');
      expect(await marked('dots')).assertFalse();
      await replace({ id: 'dots', type: 'heatmap', source: 'others' },
        (info: StyleLayerInfo) => info.type === 'heatmap');
      await replace({ id: 'dots', type: 'circle', source: 'tiles', sourceLayer: 'one' },
        (info: StyleLayerInfo) => info.sourceLayer === 'one');
      await markLayer('dots');
      await replace({ id: 'dots', type: 'circle', source: 'tiles', sourceLayer: 'two' },
        (info: StyleLayerInfo) => info.sourceLayer === 'two');
      expect(await marked('dots')).assertFalse();
      expect(testMap.errors.filter((error: string) => error.startsWith('Content')).length).assertEqual(0);
    });

    it('replaces a source whose options change, with its layers', 0, async () => {
      testMap.content = content(TWO, [circles('dots', '#ff0000')]);
      await untilLayers('background,labels,dots');
      await markLayer('dots');
      const clipped: MapContent = {
        sources: [{ id: 'places', json: { 'type': 'geojson', 'data': TWO, 'maxzoom': 10 } }],
        layers: [circles('dots', '#ff0000')],
      };
      testMap.content = clipped;
      await eventually('the source is replaced', async () =>
        (await withMap((ffi: MapHandle) => ffi.getStyleSource('places')))?.geoJson?.maxZoom === 10 ? true : undefined);
      await untilLayers('background,labels,dots');
      expect(await marked('dots')).assertFalse();
      expect(testMap.errors.length).assertEqual(0);
    });

    it('replaces the data of a source with options in place', 0, async () => {
      await testMap.controller.updateCamera({ zoom: 0 });
      // The options differ from their defaults, a zoom that the map takes as
      // an integer among them, and too few points cluster to change the count.
      const clustered = (data: GeoJsonFeatureCollection): MapContent => ({
        sources: [{ id: 'places', json: {
          'type': 'geojson', 'data': data, 'maxzoom': 12.5, 'buffer': 64, 'tolerance': 0.5, 'lineMetrics': true,
          'cluster': true, 'clusterRadius': 40, 'clusterMaxZoom': 10, 'clusterMinPoints': 10,
          'clusterProperties': JSON.parse('{"total":["+",["get","n"]]}') as Object,
        } }],
        layers: [circles('dots', '#ff0000')],
      });
      testMap.content = clustered(TWO);
      await untilFeatures(2);
      await markLayer('dots');
      testMap.content = clustered(THREE);
      await untilFeatures(3);
      expect(await marked('dots')).assertTrue();
      expect(testMap.errors.length).assertEqual(0);
    });

    it('loads GeoJSON data from a URL in place', 0, async () => {
      const path = `${application.getApplicationContext().cacheDir}/three-${Date.now()}.geojson`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(THREE));
      fs.closeSync(file);
      try {
        await testMap.controller.updateCamera({ zoom: 0 });
        testMap.content = content(TWO, [circles('dots', '#ff0000')]);
        await untilFeatures(2);
        await markLayer('dots');
        testMap.content = content(`file://${path}`, [circles('dots', '#ff0000')]);
        await untilFeatures(3);
        expect(await marked('dots')).assertTrue();
        testMap.content = content(TWO, [circles('dots', '#ff0000')]);
        await untilFeatures(2);
        expect(await marked('dots')).assertTrue();
        expect(testMap.errors.length).assertEqual(0);
      } finally {
        fs.unlinkSync(path);
      }
    });

    it('takes the same data object, or an equal copy, as unchanged', 0, async () => {
      await testMap.controller.updateCamera({ zoom: 0 });
      testMap.content = content(TWO, [circles('dots', '#ff0000')]);
      await untilFeatures(2);
      // The app replaces the data behind the content's back, which the map
      // keeps until the content's data changes.
      await withMap((ffi: MapHandle) => ffi.setGeoJsonSourceData('places', THREE));
      await untilFeatures(3);

      testMap.content = content(TWO, [circles('dots', '#00ff00')]);
      await untilProperty('dots', 'circle-color', GREEN);
      const copy = JSON.parse(JSON.stringify(TWO)) as GeoJsonFeatureCollection;
      testMap.content = content(copy, [circles('dots', '#0000ff')]);
      await untilProperty('dots', 'circle-color', '["rgba",0,0,255,1]');
      await frames(10);
      await untilFeatures(3);

      const one: GeoJsonFeatureCollection = { type: 'FeatureCollection', features: TWO.features.slice(0, 1) };
      testMap.content = content(one, [circles('dots', '#0000ff')]);
      await untilFeatures(1);
    });

    it('sets an image again when its pixel map, pixel ratio, or sdf changes', 0, async () => {
      const red = pixel(255, 0, 0);
      testMap.content = { images: [{ id: 'dot', image: red, pixelRatio: 1 }] };
      await eventually('the image goes in', async () => withMap((ffi: MapHandle) => ffi.getStyleImage('dot')));

      testMap.content = { images: [{ id: 'dot', image: red, pixelRatio: 7 }] };
      await eventually('the pixel ratio changes', async () =>
        (await withMap((ffi: MapHandle) => ffi.getStyleImage('dot')))?.pixelRatio === 7 ? true : undefined);
      testMap.content = { images: [{ id: 'dot', image: red, pixelRatio: 7, sdf: true }] };
      await eventually('the image becomes an SDF', async () =>
        (await withMap((ffi: MapHandle) => ffi.getStyleImage('dot')))?.sdf ? true : undefined);
      const green = pixel(0, 255, 0);
      testMap.content = { images: [{ id: 'dot', image: green, pixelRatio: 7, sdf: true }] };
      await eventually('the pixels change', async () =>
        (await withMap((ffi: MapHandle) => ffi.getStyleImage('dot')))?.pixels[1] === 255 ? true : undefined);
      testMap.content = { images: [{ id: 'dot', image: green }] };
      await eventually('the image takes the defaults', async () => {
        const info = await withMap((ffi: MapHandle) => ffi.getStyleImage('dot'));
        return info !== undefined && !info.sdf && info.pixelRatio !== 7 ? true : undefined;
      });

      // The same pixel map, which the map doesn't compare by its pixels, stays
      // as the style has it.
      await withMap((ffi: MapHandle) =>
        ffi.setStyleImage('dot', { width: 1, height: 1, stride: 4, pixels: new Uint8Array([0, 0, 255, 255]) }));
      // A layer that goes in with it shows that the map has applied it.
      const shade: StyleLayer = { id: 'shade', type: 'background' };
      testMap.content = { images: [{ id: 'dot', image: green }], layers: [shade] };
      await untilLayers('background,labels,shade');
      expect((await withMap((ffi: MapHandle) => ffi.getStyleImage('dot')))?.pixels[2]).assertEqual(255);
      expect(testMap.errors.length).assertEqual(0);
    });

    // The map gives the reconciler each content as the app sets it, so these
    // cases drive one of their own, for the timing. It shares the test map's
    // style, whose own content is empty, and keeps the FFI map past the lend,
    // as the library's own does, while the map stays for the case.
    it('applies only the latest content that comes during a pass, once it ends', 0, async () => {
      const errors: string[] = [];
      const reconciler = withMap((ffi: MapHandle) =>
        new ContentReconciler(ffi, (error: Error) => errors.push(error.message), 1));
      reconciler.setContent(content(TWO, [circles('a', '#ff0000')]));
      const loaded = reconciler.styleLoaded();
      // The map runs commands in order, so once this one completes, the pass
      // has its base layers and applies the first content.
      await withMap((ffi: MapHandle) => ffi.getStyleLayer('labels'));
      const lost: StyleLayer = { id: 'lost', type: 'circle', source: 'missing' };
      reconciler.setContent(content(TWO, [lost, circles('b', '#ff0000')]));
      reconciler.setContent(content(TWO, [circles('c', '#ff0000'), circles('a', '#ff0000')]));
      await loaded;
      await untilLayers('background,labels,c,a');
      await frames(10);
      expect(await layerIds()).assertEqual('background,labels,c,a');
      expect(errors.length).assertEqual(0);
    });

    it('stops a pass when the style changes, and applies the content to the next style', 0, async () => {
      const errors: string[] = [];
      const reconciler = withMap((ffi: MapHandle) =>
        new ContentReconciler(ffi, (error: Error) => errors.push(error.message), 1));
      reconciler.setContent(content(TWO, manyCircles(20)));
      const loaded = reconciler.styleLoaded();
      // The map runs commands in order, so once this one completes, the pass
      // has its base layers and adds its first layer.
      await withMap((ffi: MapHandle) => ffi.getStyleLayer('labels'));
      reconciler.styleUnloaded();
      const loading = withMap((ffi: MapHandle) => ffi.setStyleJson(baseStyle('#4ad94a')));
      await loaded;
      await loading;
      await reconciler.styleLoaded();
      const expected = ['background', 'labels'].concat(manyCircles(20).map((layer: StyleLayer) => layer.id));
      expect(await layerIds()).assertEqual(expected.join());
      expect(errors.length).assertEqual(0);
    });

    it('puts a layer on top in a style without the layer it goes below', 0, async () => {
      testMap.content = content(TWO, [circles('dots', '#ff0000', 'labels')]);
      await untilLayers('background,dots,labels');
      await setStyle(STYLE);
      expect(await layerIds()).assertEqual('background,dots');
      await setStyle(baseStyle('#4ad94a'));
      expect(await layerIds()).assertEqual('background,dots,labels');
      expect(testMap.errors.length).assertEqual(0);
    });

    it('applies the rest of the content after onError throws', 0, async () => {
      testMap.throwOnError = true;
      const lost: StyleLayer = { id: 'lost', type: 'circle', source: 'missing' };
      testMap.content = content(TWO, [lost, circles('dots', '#ff0000')]);
      await until('the map reports the layer', () =>
        testMap.errors.some((error: string) => error.includes('adding layer lost')));
      await untilLayers('background,labels,dots');
      testMap.content = content(TWO, [lost, circles('dots', '#00ff00')]);
      await untilProperty('dots', 'circle-color', GREEN);
    });

    it('draws a snapshot without the content the map rejects', 0, async () => {
      const west: MapContent = {
        sources: [{ id: 'west', json: { 'type': 'geojson', 'data': WEST } }],
        layers: [
          { id: 'lost', type: 'fill', source: 'missing', paint: { 'fill-color': '#00ff00' } },
          { id: 'west', type: 'fill', source: 'west', paint: { 'fill-color': '#ff0000', 'fill-antialias': false } },
        ],
      };
      const pixelMap = (await renderSnapshot({
        style: backgroundStyle('#0000ff'), content: west, width: 64, height: 32, pixelRatio: 2,
        camera: { zoom: 0 },
      })).image;
      const pixels = await readPixels(pixelMap);
      expect(pixelAt(pixels, 128, 32, 32).join()).assertEqual('255,0,0,255');
      expect(pixelAt(pixels, 128, 96, 32).join()).assertEqual('0,0,255,255');
      await pixelMap.release();
    });
  });
}
