import { beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  CameraUpdateMode,
  eq,
  fp,
  GeoJsonFeatureCollection,
  GeoJsonGeometry,
  GeoJsonSourceDataHandle,
  get,
  MapContent,
  MapLayer,
  PremultipliedRgba8Image,
  snapshot,
  StyleLayerInfo,
  StyleLayerVisibility,
} from '@maplibre/arkui';
import { ContentReconciler } from '@maplibre/arkui/src/main/ets/Content';
import application from '@ohos.app.ability.application';
import fs from '@ohos.file.fs';

import { backgroundStyle, STYLE, testMap } from '../testability/TestMaps';
import { eventually, frames, pixelAt, readPixels, requireMap, setStyle, until } from './helpers';

// A base style with a layer to place content under, as an app places it under
// labels.
function baseStyle(color: string): string {
  return '{"version":8,"sources":{"base":{"type":"geojson","data":{"type":"FeatureCollection","features":[]}}},' +
    `"layers":[{"id":"background","type":"background","paint":{"background-color":"${color}"}},` +
    '{"id":"labels","type":"symbol","source":"base"}]}';
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

function circles(id: string, color: string, below?: string | ((layer: StyleLayerInfo) => boolean)): MapLayer {
  return { id: id, type: 'circle', source: 'places', paint: { 'circle-color': color, 'circle-radius': 6 }, below: below };
}

// The places source, with `data` as GeoJSON or a URL.
function content(data: GeoJsonFeatureCollection | string, layers: MapLayer[]): MapContent {
  return { sources: [{ id: 'places', json: { 'type': 'geojson', 'data': data } }], layers: layers };
}

function pixel(r: number, g: number, b: number): PremultipliedRgba8Image {
  return { width: 1, height: 1, stride: 4, pixels: new Uint8Array([r, g, b, 255]) };
}

// How many features the places source has, once it has `expected`.
async function untilFeatures(expected: number): Promise<void> {
  await eventually(`the source has ${expected} features`, async () => {
    const features = await testMap.controller.renderSession?.querySourceFeatures('places');
    return features?.length === expected ? true : undefined;
  });
}

// Sets a property that the content doesn't, which a layer keeps only while
// the map changes it in place.
async function markLayer(id: string): Promise<void> {
  await requireMap().setStyleLayerProperty(id, 'circle-blur', 0.5);
}

async function marked(id: string): Promise<boolean> {
  return JSON.stringify(await requireMap().getStyleLayerProperty(id, 'circle-blur')) === '0.5';
}

async function layerInfo(id: string): Promise<StyleLayerInfo> {
  const info = await requireMap().getStyleLayer(id);
  if (info === undefined) {
    throw new Error(`The style has no layer ${id}`);
  }
  return info;
}

// The circles layers, many of them, for a pass that takes a while.
function manyCircles(count: number): MapLayer[] {
  const layers: MapLayer[] = [];
  for (let i = 0; i < count; i++) {
    layers.push(circles(`c${i}`, '#ff0000'));
  }
  return layers;
}

async function layerIds(): Promise<string> {
  const layers = await requireMap().listStyleLayers();
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
      last = `${JSON.stringify(await requireMap().getStyleLayerProperty(layer, name))}`;
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
        images: [{ id: 'dot', image: { width: 1, height: 1, stride: 4, pixels: new Uint8Array([255, 0, 0, 255]) } }],
        layers: [
          circles('low', '#ff0000', (layer: StyleLayerInfo) => layer.type === 'symbol'),
          circles('high', '#00ff00'),
          circles('mid', '#0000ff', 'labels'),
        ],
      };
      testMap.content = dot;
      await untilLayers('background,low,mid,labels,high');
      const map = requireMap();
      expect((await map.getStyleSource('places'))?.id).assertEqual('places');
      expect((await map.getStyleImage('dot'))?.width).assertEqual(1);
      expect(testMap.errors.length).assertEqual(0);

      testMap.content = undefined;
      await untilLayers('background,labels');
      expect(await map.getStyleSource('places')).assertUndefined();
      expect(await map.getStyleImage('dot')).assertUndefined();
    });

    it('changes a property in place', 0, async () => {
      testMap.content = content(TWO, [circles('dots', '#ff0000')]);
      await untilLayers('background,labels,dots');
      // A property the content doesn't set, which stays only if the layer does.
      const map = requireMap();
      await map.setStyleLayerProperty('dots', 'circle-blur', 0.5);

      testMap.content = content(TWO, [circles('dots', '#00ff00')]);
      await untilProperty('dots', 'circle-color', GREEN);
      expect(JSON.stringify(await map.getStyleLayerProperty('dots', 'circle-blur'))).assertEqual('0.5');

      // An expression, and a property the content stops setting.
      const layer: MapLayer = {
        id: 'dots', type: 'circle', source: 'places', paint: { 'circle-color': get('color') },
      };
      testMap.content = content(TWO, [layer]);
      await untilProperty('dots', 'circle-color', '["to-color",["get","color"]]');
      await untilProperty('dots', 'circle-radius', 'undefined');
      expect(JSON.stringify(await map.getStyleLayerProperty('dots', 'circle-blur'))).assertEqual('0.5');
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

    it('sets the font scale that fp() reads on each style, and follows a change', 0, async () => {
      const context = testMap.context!;
      const scale = (): number => context.fp2px(1) / context.vp2px(1);
      const state = async (): Promise<number | undefined> => {
        const global = await requireMap().getGlobalState() as Record<string, Object>;
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
      await testMap.controller.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 0 } });
      testMap.content = content(TWO, [circles('dots', '#ff0000')]);
      await untilLayers('background,labels,dots');
      const map = requireMap();
      await map.setStyleLayerProperty('dots', 'circle-blur', 0.5);
      const count = async (expected: number): Promise<boolean | undefined> => {
        const session = testMap.controller.renderSession;
        const features = await session?.querySourceFeatures('places');
        return features?.length === expected ? true : undefined;
      };
      await eventually('the source has two features', () => count(2));

      testMap.content = content(THREE, [circles('dots', '#ff0000')]);
      await eventually('the source has three features', () => count(3));
      // A new source would have taken a new layer, without the blur.
      expect(JSON.stringify(await map.getStyleLayerProperty('dots', 'circle-blur'))).assertEqual('0.5');
    });

    it('adds the content to each style', 0, async () => {
      testMap.content = content(TWO, [circles('dots', '#ff0000', 'labels')]);
      await untilLayers('background,dots,labels');
      await setStyle(baseStyle('#4ad94a'));
      // The content is on the style by the time the app hears that it loaded.
      expect(await layerIds()).assertEqual('background,dots,labels');
      expect((await requireMap().getStyleSource('places'))?.id).assertEqual('places');
      expect(testMap.errors.length).assertEqual(0);
    });

    it('reports what the map rejects and adds the rest', 0, async () => {
      const lost: MapLayer = { id: 'lost', type: 'circle', source: 'missing' };
      const taken: MapLayer = { id: 'background', type: 'circle', source: 'places' };
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
      const found: MapLayer = { id: 'lost', type: 'circle', source: 'places' };
      testMap.content = content(TWO, [found, taken, circles('dots', '#00ff00')]);
      await untilLayers('background,labels,lost,dots');
    });

    it('adds a layer once the rejected source it waited on leaves', 0, async () => {
      // The base style already has a source called base.
      const dots: MapLayer = { id: 'dots', type: 'circle', source: 'base' };
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

    it('leaves an image that the style already had to it', 0, async () => {
      const map = requireMap();
      await map.setStyleImage('dot', { width: 2, height: 1, stride: 8, pixels: new Uint8Array(8) });
      const red: Uint8Array = new Uint8Array([255, 0, 0, 255]);
      testMap.content = { images: [{ id: 'dot', image: { width: 1, height: 1, stride: 4, pixels: red } }] };
      await until('the map reports the image', () =>
        testMap.errors.some((error: string) => error.includes('adding image dot')));
      expect((await map.getStyleImage('dot'))?.width).assertEqual(2);
      const empty: MapContent = {};
      testMap.content = empty;
      await frames(10);
      expect((await map.getStyleImage('dot'))?.width).assertEqual(2);
    });

    it('leaves an image ID alone after the map rejects the content image', 0, async () => {
      const map = requireMap();
      // Too few pixels for its size, so the map rejects it.
      const bad: Uint8Array = new Uint8Array(4);
      testMap.content = { images: [{ id: 'dot', image: { width: 2, height: 2, stride: 8, pixels: bad } }] };
      await until('the map rejects the image', () =>
        testMap.errors.some((error: string) => error.includes('setting image dot')));
      await map.setStyleImage('dot', { width: 3, height: 1, stride: 12, pixels: new Uint8Array(12) });
      const empty: MapContent = {};
      testMap.content = empty;
      await frames(10);
      expect((await map.getStyleImage('dot'))?.width).assertEqual(3);
    });

    it('removes a source on a later pass once nothing else uses it', 0, async () => {
      const map = requireMap();
      testMap.content = content(TWO, []);
      await eventually('the source goes in', async () => map.getStyleSource('places'));
      // A layer that the app adds over the content's source keeps the map
      // from removing the source.
      const extra: Record<string, Object> = { 'id': 'extra', 'type': 'circle', 'source': 'places' };
      await map.addStyleLayerJson(extra);
      testMap.content = undefined;
      await until('the map refuses to remove the source', () =>
        testMap.errors.some((error: string) => error.includes('removing source places')));
      await map.removeStyleLayer('extra');
      const empty: MapContent = {};
      testMap.content = empty;
      await eventually('the source goes', async () => (await map.getStyleSource('places')) === undefined ? true :
        undefined);
    });

    it('draws the content in a snapshot', 0, async () => {
      const west: MapContent = {
        sources: [{ id: 'west', json: { 'type': 'geojson', 'data': WEST } }],
        layers: [{ id: 'west', type: 'fill', source: 'west',
          paint: { 'fill-color': '#ff0000', 'fill-antialias': false } }],
      };
      const pixelMap = await snapshot({
        style: backgroundStyle('#0000ff'), content: west, width: 64, height: 32, scaleFactor: 2, camera: { zoom: 0 },
      });
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
        const pixelMap = await snapshot({
          style: backgroundStyle('#0000ff'), content: dot, width: 64, height: 32, scaleFactor: 2,
          camera: { center: { latitude: 0, longitude: 0 }, zoom: 0 }, fontScale: fontScale,
        });
        const pixels = await readPixels(pixelMap);
        await pixelMap.release();
        return pixelAt(pixels, 128, 2 * (32 + 12), 32).join();
      };
      expect(await edge()).assertEqual('0,0,255,255');
      expect(await edge(2)).assertEqual('255,0,0,255');
    });

    it('changes the filter, zoom range, and layout in place, and unsets them', 0, async () => {
      const plain: MapLayer = { id: 'dots', type: 'circle', source: 'places', paint: { 'circle-color': '#ff0000' } };
      testMap.content = content(TWO, [plain]);
      await untilLayers('background,labels,dots');
      await markLayer('dots');

      const set: MapLayer = {
        id: 'dots', type: 'circle', source: 'places', paint: { 'circle-color': '#ff0000' },
        filter: eq(get('n'), 1), minZoom: 2, maxZoom: 10, layout: { 'visibility': 'none' },
      };
      testMap.content = content(TWO, [set]);
      await eventually('the layer changes', async () => (await layerInfo('dots')).maxZoom === 10 ? true : undefined);
      const changed = await layerInfo('dots');
      expect(changed.minZoom).assertEqual(2);
      expect(changed.visibility).assertEqual(StyleLayerVisibility.none);
      const json = await requireMap().getStyleLayerJson('dots') as Record<string, Object>;
      expect(JSON.stringify(json['filter'])).assertEqual('["==",["get","n"],1]');
      expect(await marked('dots')).assertTrue();

      testMap.content = content(TWO, [plain]);
      await eventually('the layer goes back', async () =>
        (await layerInfo('dots')).maxZoom === Infinity ? true : undefined);
      const unset = await layerInfo('dots');
      expect(unset.minZoom).assertEqual(-Infinity);
      expect(unset.visibility).assertEqual(StyleLayerVisibility.visible);
      const plainJson = await requireMap().getStyleLayerJson('dots') as Record<string, Object>;
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
      const replace = async (layer: MapLayer, done: (info: StyleLayerInfo) => boolean): Promise<void> => {
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
        (await requireMap().getStyleSource('places'))?.geoJson?.maxZoom === 10 ? true : undefined);
      await untilLayers('background,labels,dots');
      expect(await marked('dots')).assertFalse();
      expect(testMap.errors.length).assertEqual(0);
    });

    it('loads GeoJSON data from a URL in place', 0, async () => {
      const path = `${application.getApplicationContext().cacheDir}/three-${Date.now()}.geojson`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(THREE));
      fs.closeSync(file);
      try {
        await testMap.controller.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 0 } });
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
      await testMap.controller.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 0 } });
      testMap.content = content(TWO, [circles('dots', '#ff0000')]);
      await untilFeatures(2);
      // The app replaces the data behind the content's back, which the map
      // keeps until the content's data changes.
      const map = requireMap();
      const prepared = GeoJsonSourceDataHandle.create(THREE, (await map.getStyleSource('places'))?.geoJson);
      try {
        await map.setGeoJsonSourceData('places', prepared);
      } finally {
        prepared.release();
      }
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

    it('sets an image again when its options or pixels change', 0, async () => {
      const map = requireMap();
      const red = pixel(255, 0, 0);
      testMap.content = { images: [{ id: 'dot', image: red, options: { pixelRatio: 1 } }] };
      await eventually('the image goes in', async () => map.getStyleImage('dot'));

      testMap.content = { images: [{ id: 'dot', image: red, options: { pixelRatio: 2 } }] };
      await eventually('the options change', async () =>
        (await map.getStyleImage('dot'))?.pixelRatio === 2 ? true : undefined);
      testMap.content = { images: [{ id: 'dot', image: pixel(0, 255, 0), options: { pixelRatio: 2 } }] };
      await eventually('the pixels change', async () =>
        (await map.getStyleImage('dot'))?.pixels[1] === 255 ? true : undefined);

      // The same pixels object, which the map doesn't compare, stays as the
      // style has it.
      const green = pixel(0, 255, 0);
      testMap.content = { images: [{ id: 'dot', image: green }] };
      await eventually('the image takes the default options', async () =>
        (await map.getStyleImage('dot'))?.pixelRatio === 1 ? true : undefined);
      await map.setStyleImage('dot', pixel(0, 0, 255));
      // A layer that goes in with it shows that the map has applied it.
      const shade: MapLayer = { id: 'shade', type: 'background' };
      testMap.content = { images: [{ id: 'dot', image: green }], layers: [shade] };
      await untilLayers('background,labels,shade');
      expect((await map.getStyleImage('dot'))?.pixels[2]).assertEqual(255);
      expect(testMap.errors.length).assertEqual(0);
    });

    // The map gives the reconciler each content as the app sets it, so these
    // cases drive one of their own, for the timing. It shares the test map's
    // style, whose own content is empty.
    it('applies only the latest content that comes during a pass, once it ends', 0, async () => {
      const errors: string[] = [];
      const reconciler = new ContentReconciler(requireMap(), (error: Error) => errors.push(error.message));
      reconciler.setContent(content(TWO, [circles('a', '#ff0000')]));
      const loaded = reconciler.styleLoaded();
      // The map runs commands in order, so once this one completes, the pass
      // has its base layers and applies the first content.
      await requireMap().getStyleLayer('labels');
      const lost: MapLayer = { id: 'lost', type: 'circle', source: 'missing' };
      reconciler.setContent(content(TWO, [lost, circles('b', '#ff0000')]));
      reconciler.setContent(content(TWO, [circles('c', '#ff0000'), circles('a', '#ff0000')]));
      await loaded;
      await untilLayers('background,labels,c,a');
      await frames(10);
      expect(await layerIds()).assertEqual('background,labels,c,a');
      expect(errors.length).assertEqual(0);
    });

    it('stops a pass when the style changes, and applies the content to the next style', 0, async () => {
      const map = requireMap();
      const errors: string[] = [];
      const reconciler = new ContentReconciler(map, (error: Error) => errors.push(error.message));
      reconciler.setContent(content(TWO, manyCircles(20)));
      const loaded = reconciler.styleLoaded();
      // The map runs commands in order, so once this one completes, the pass
      // has its base layers and adds its first layer.
      await map.getStyleLayer('labels');
      reconciler.styleUnloaded();
      const loading = map.setStyleJson(JSON.parse(baseStyle('#4ad94a')));
      await loaded;
      await loading;
      await reconciler.styleLoaded();
      const expected = ['background', 'labels'].concat(manyCircles(20).map((layer: MapLayer) => layer.id));
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

    it('applies the rest of the content after onMapError throws', 0, async () => {
      testMap.throwOnError = true;
      const lost: MapLayer = { id: 'lost', type: 'circle', source: 'missing' };
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
      const pixelMap = await snapshot({
        style: backgroundStyle('#0000ff'), content: west, width: 64, height: 32, scaleFactor: 2, camera: { zoom: 0 },
      });
      const pixels = await readPixels(pixelMap);
      expect(pixelAt(pixels, 128, 32, 32).join()).assertEqual('255,0,0,255');
      expect(pixelAt(pixels, 128, 96, 32).join()).assertEqual('0,0,255,255');
      await pixelMap.release();
    });
  });
}
