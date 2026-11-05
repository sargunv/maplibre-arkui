import { afterEach, beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  CameraUpdateMode,
  get,
  GeoJsonFeatureCollection,
  GeoJsonGeometry,
  MapContent,
  MapHandle,
  MapLayer,
  snapshot,
  StyleLayerInfo,
} from '@maplibre/arkui';

import { STYLE, testMap } from '../testability/TestMaps';
import { eventually, until } from './until';

// A base style with a layer to place content under, as an app places it under
// labels.
const BASE = '{"version":8,"sources":{"base":{"type":"geojson","data":{"type":"FeatureCollection",' +
  '"features":[]}}},"layers":[{"id":"background","type":"background","paint":{"background-color":"#4a90d9"}},' +
  '{"id":"labels","type":"symbol","source":"base"}]}';

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

function requireMap(): MapHandle {
  const map = testMap.controller.map;
  if (map === undefined) {
    throw new Error('The test map is not ready');
  }
  return map;
}

function circles(id: string, color: string, below?: string | ((layer: StyleLayerInfo) => boolean)): MapLayer {
  return { id: id, type: 'circle', source: 'places', paint: { 'circle-color': color, 'circle-radius': 6 }, below: below };
}

function content(data: GeoJsonFeatureCollection, layers: MapLayer[]): MapContent {
  return { sources: [{ id: 'places', json: { 'type': 'geojson', 'data': data } }], layers: layers };
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
    }, 5000);
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
    }, 5000);
  } catch (error) {
    throw new Error(`${(error as Error).message}, not ${last}`);
  }
}

function pixelAt(pixels: Uint8Array, width: number, x: number, y: number): number[] {
  const offset = (y * width + x) * 4;
  return [pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3]];
}

export default function contentTest(): void {
  describe('Content', () => {
    beforeEach(async () => {
      testMap.errors = [];
      if (testMap.style !== BASE) {
        const loads = testMap.styleLoads;
        testMap.style = BASE;
        await until('the base style loads', () => testMap.styleLoads > loads);
      }
    });

    afterEach(async () => {
      testMap.content = undefined;
      await untilLayers('background,labels');
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

    it('replaces GeoJSON data in place', 0, async () => {
      await testMap.controller.updateCamera({
        mode: CameraUpdateMode.jump,
        camera: { center: { latitude: 0, longitude: 0 }, zoom: 0, bearing: 0, pitch: 0 },
      });
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
      const loads = testMap.styleLoads;
      testMap.style = BASE.replace('#4a90d9', '#4ad94a');
      await until('the new style loads', () => testMap.styleLoads > loads);
      await untilLayers('background,dots,labels');
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

    it('draws the content in a snapshot', 0, async () => {
      const west: MapContent = {
        sources: [{ id: 'west', json: { 'type': 'geojson', 'data': WEST } }],
        layers: [{ id: 'west', type: 'fill', source: 'west',
          paint: { 'fill-color': '#ff0000', 'fill-antialias': false } }],
      };
      const blue = STYLE.replace('#4a90d9', '#0000ff');
      const pixelMap = await snapshot({
        style: blue, content: west, width: 64, height: 32, scaleFactor: 2, camera: { zoom: 0 },
      });
      const buffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
      await pixelMap.readPixelsToBuffer(buffer);
      const pixels = new Uint8Array(buffer);
      expect(pixelAt(pixels, 128, 32, 32).join()).assertEqual('255,0,0,255');
      expect(pixelAt(pixels, 128, 96, 32).join()).assertEqual('0,0,255,255');
      await pixelMap.release();
    });
  });
}
