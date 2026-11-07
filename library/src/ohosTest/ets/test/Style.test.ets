import { beforeEach, describe, expect, it } from '@ohos/hypium';
import image from '@ohos.multimedia.image';
import {
  GeoJsonFeatureCollection,
  MapController,
  readPixelMap,
  RenderedFeature,
  ScreenPoint,
} from '@maplibre/arkui';
import { CommandCompletion, FeatureStateSelector, MapHandle } from '@maplibre/native-ffi';

import { backgroundStyle, testMap } from '../testability/TestMaps';
import { eventually, pixelFor, setStyle, withMap } from './helpers';

const PLACES: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', id: 1, geometry: { type: 'Point', coordinates: [20, 10] }, properties: { 'name': 'One' } },
    { type: 'Feature', id: 2, geometry: { type: 'Point', coordinates: [-40, -20] }, properties: { 'name': 'Two' } },
  ],
};

const ONE: FeatureStateSelector = { sourceId: 'places', featureId: { kind: 'doubleValue', value: 1 } };

// Adds a circle layer of `color` that draws the places, through the FFI map.
function addCircles(id: string, color: string = '#ffffff'): Promise<CommandCompletion> {
  const paint: Record<string, Object> = { 'circle-radius': 12, 'circle-color': color };
  const layer: Record<string, Object> = { 'id': id, 'type': 'circle', 'source': 'places', 'paint': paint };
  return withMap((ffi: MapHandle) => ffi.addStyleLayerJson(layer));
}

// Adds the places as a GeoJSON source from the object itself, and a circle
// layer that draws them. The map runs the commands in order.
function addPlaces(): Promise<CommandCompletion[]> {
  const source: Record<string, Object> = { 'type': 'geojson', 'data': PLACES };
  return Promise.all([withMap((ffi: MapHandle) => ffi.addStyleSourceJson('places', source)), addCircles('circles')]);
}

function bytes(pixels: Uint8Array): string {
  const values: number[] = [];
  for (let i = 0; i < pixels.length; i++) {
    values.push(pixels[i]);
  }
  return values.join(',');
}

// Queries `layers` at `point` once a frame until it finds `count` features.
function queryAt(point: ScreenPoint, layers: string[], count: number = 1): Promise<RenderedFeature[]> {
  return eventually('the query finds the features', async () => {
    const hits = await testMap.controller.queryRenderedFeatures(point, { layers: layers });
    return hits !== undefined && hits.length >= count ? hits : undefined;
  });
}

export default function styleTest(): void {
  describe('Style', () => {
    beforeEach(async () => {
      await testMap.reset();
    });

    it('reads a PixelMap into a style image', 0, () => {
      // Red at half alpha and opaque blue, not premultiplied, in each byte
      // order. Premultiplied, the red is 128.
      const bgra = image.createPixelMapSync(new Uint8Array([0, 0, 255, 128, 255, 0, 0, 255]).buffer, {
        size: { width: 2, height: 1 },
        pixelFormat: image.PixelMapFormat.BGRA_8888,
        alphaType: image.AlphaType.UNPREMUL,
      });
      const rgba = image.createPixelMapSync(new Uint8Array([255, 0, 0, 128, 0, 0, 255, 255]).buffer, {
        size: { width: 2, height: 1 },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        alphaType: image.AlphaType.UNPREMUL,
      });
      for (const pixelMap of [bgra, rgba]) {
        const read = readPixelMap(pixelMap);
        expect(read.width).assertEqual(2);
        expect(read.height).assertEqual(1);
        expect(read.stride).assertEqual(8);
        expect(bytes(read.pixels)).assertEqual('128,0,0,128,0,0,255,255');
      }
      bgra.release();
      rgba.release();
    });

    it('rejects a PixelMap that it can\'t read', 0, async () => {
      const rgb565 = image.createPixelMapSync(new Uint8Array([255, 0, 0, 255]).buffer, {
        size: { width: 1, height: 1 },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGB_565,
      });
      expect(rgb565.getImageInfoSync().pixelFormat).assertEqual(image.PixelMapFormat.RGB_565);
      expect(() => readPixelMap(rgb565)).assertThrowError('readPixelMap() reads RGBA_8888 and BGRA_8888 pixel maps, ' +
        `not format ${image.PixelMapFormat.RGB_565}`);
      rgb565.release();

      const released = image.createPixelMapSync(new Uint8Array([255, 0, 0, 255]).buffer, {
        size: { width: 1, height: 1 },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
      });
      await released.release();
      let threw = false;
      try {
        readPixelMap(released);
      } catch (error) {
        threw = true;
      }
      expect(threw).assertTrue();
    });


    it('gives a feature without state an empty state', 0, async () => {
      await addPlaces();
      const hits = await queryAt(pixelFor({ latitude: 10, longitude: 20 }), ['circles']);
      expect(JSON.stringify(hits[0].state)).assertEqual('{}');
    });

    it('finds the feature at its screen point, with its state', 0, async () => {
      await addPlaces();
      const selected: Record<string, Object> = { 'selected': true };
      await withMap((ffi: MapHandle) => ffi.setFeatureState(ONE, selected));
      const point = pixelFor({ latitude: 10, longitude: 20 });

      const hits = await queryAt(point, ['circles']);
      expect(hits.length).assertEqual(1);
      expect(hits[0].layerId).assertEqual('circles');
      expect(hits[0].sourceId).assertEqual('places');
      expect(hits[0].sourceLayer).assertUndefined();
      expect(hits[0].feature.id).assertEqual(1);
      expect(hits[0].feature.properties?.['name']).assertEqual('One');
      expect(JSON.stringify(hits[0].state)).assertEqual('{"selected":true}');

      const beside = await testMap.controller.queryRenderedFeatures({ x: point.x + 60, y: point.y },
        { layers: ['circles'] });
      expect(beside?.length).assertEqual(0);
      // Within the hit padding of the point.
      const padded = await testMap.controller.queryRenderedFeatures({ x: point.x + 60, y: point.y },
        { layers: ['circles'], hitPadding: 60 });
      expect(padded?.length).assertEqual(1);
      expect(() => testMap.controller.queryRenderedFeatures(point, { hitPadding: -1 })).assertThrowError('-1');
    });

    it('starts each style without what the app added, which it adds again', 0, async () => {
      await addPlaces();
      await setStyle(backgroundStyle('#4ad94a'));
      expect(await withMap((ffi: MapHandle) => ffi.getStyleLayer('circles'))).assertUndefined();
      expect(await withMap((ffi: MapHandle) => ffi.getStyleSource('places'))).assertUndefined();

      await addPlaces();
      expect((await withMap((ffi: MapHandle) => ffi.getStyleLayer('circles')))?.id).assertEqual('circles');
    });

    it('answers queries with undefined while no map shows the controller', 0, async () => {
      const unused = new MapController();
      expect(await unused.queryRenderedFeatures({ x: 0, y: 0 })).assertUndefined();
      expect(await unused.querySourceFeatures('places')).assertUndefined();
      expect(unused.withFfiMap((map: MapHandle) => map.id)).assertUndefined();
    });
  });
}
