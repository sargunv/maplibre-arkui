import { beforeEach, describe, expect, it } from '@ohos/hypium';
import image from '@ohos.multimedia.image';
import {
  ConstrainMode,
  FeatureStateSelector,
  GeoJsonFeature,
  GeoJsonFeatureCollection,
  ImageContent,
  latLngForProjectedMeters,
  MapDebugFlag,
  MapHandle,
  NorthOrientation,
  PremultipliedRgba8Image,
  projectedMetersForLatLng,
  readPixelMap,
  RenderedFeature,
  ScreenPoint,
  StyleImageTextFit,
  TileLodMode,
} from '@maplibre/arkui';

import { backgroundStyle, testMap } from '../testability/TestMaps';
import { eventually, expectNear, pixelFor, requireMap, setStyle, until } from './helpers';

const PLACES: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', id: 1, geometry: { type: 'Point', coordinates: [20, 10] }, properties: { 'name': 'One' } },
    { type: 'Feature', id: 2, geometry: { type: 'Point', coordinates: [-40, -20] }, properties: { 'name': 'Two' } },
  ],
};

const ONE: FeatureStateSelector = { sourceId: 'places', featureId: { kind: 'doubleValue', value: 1 } };

// Adds the places as a GeoJSON source from the object itself, and a circle
// layer that draws them.
async function addPlaces(map: MapHandle): Promise<void> {
  const source: Record<string, Object> = { 'type': 'geojson', 'data': PLACES };
  const paint: Record<string, Object> = { 'circle-radius': 12, 'circle-color': '#ffffff' };
  const layer: Record<string, Object> = { 'id': 'circles', 'type': 'circle', 'source': 'places', 'paint': paint };
  await map.addStyleSourceJson('places', source);
  await map.addStyleLayerJson(layer);
}

function bytes(pixels: Uint8Array): string {
  const values: number[] = [];
  for (let i = 0; i < pixels.length; i++) {
    values.push(pixels[i]);
  }
  return values.join(',');
}

// Queries the circles at `point` once a frame until it finds one.
function queryCircles(point: ScreenPoint): Promise<readonly RenderedFeature[]> {
  return eventually('the query finds a feature', async () => {
    const session = testMap.controller.renderSession;
    if (session === undefined) {
      return undefined;
    }
    const hits = await session.queryRenderedFeatures({ kind: 'point', value: point }, { layerIds: ['circles'] });
    return hits.length > 0 ? hits : undefined;
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

    it('takes the options that the re-exported FFI enums name', 0, async () => {
      const map = requireMap();
      const debug = MapDebugFlag.tileBorders | MapDebugFlag.collision;
      await map.setDebugFlags(debug);
      await until('the debug flags apply', () => map.getSnapshot().debugFlags === debug);
      await map.setDebugFlags(0);

      const lodMode = map.getSnapshot().tile.lodMode;
      await map.setTileOptions({ lodMode: TileLodMode.distance });
      await until('the tile options apply', () => map.getSnapshot().tile.lodMode === TileLodMode.distance);
      await map.setTileOptions({ lodMode: lodMode });

      const viewport = map.getSnapshot().view.viewport;
      await map.setViewportOptions({ constrainMode: ConstrainMode.screen, northOrientation: NorthOrientation.up });
      await until('the viewport options apply',
        () => map.getSnapshot().view.viewport.constrainMode === ConstrainMode.screen);
      expect(map.getSnapshot().view.viewport.northOrientation).assertEqual(NorthOrientation.up);
      await map.setViewportOptions({ constrainMode: viewport.constrainMode });

      // An opaque white pixel, whose content box text fits proportionally.
      const pixel: PremultipliedRgba8Image = {
        width: 1, height: 1, stride: 4, pixels: new Uint8Array([255, 255, 255, 255]),
      };
      const content: ImageContent = { left: 0, top: 0, right: 1, bottom: 1 };
      await map.setStyleImage('label', pixel, {
        content: content,
        textFitWidth: StyleImageTextFit.proportional,
        textFitHeight: StyleImageTextFit.stretchOnly,
      });
      const stored = await map.getStyleImage('label');
      expect(stored?.content?.right).assertEqual(1);
      expect(stored?.textFitWidth).assertEqual(StyleImageTextFit.proportional);
      expect(stored?.textFitHeight).assertEqual(StyleImageTextFit.stretchOnly);
      await map.removeStyleImage('label');

      const meters = projectedMetersForLatLng({ latitude: 10, longitude: 20 });
      expect(meters.easting).assertLarger(0);
      const back = latLngForProjectedMeters(meters);
      expectNear(back.latitude, 10, 1e-9);
      expectNear(back.longitude, 20, 1e-9);
    });

    it('finds the feature at its screen point, with its state', 0, async () => {
      const map = requireMap();
      await addPlaces(map);
      const selected: Record<string, Object> = { 'selected': true };
      await map.setFeatureState(ONE, selected);
      const point = pixelFor({ latitude: 10, longitude: 20 });

      const hits = await queryCircles(point);
      expect(hits.length).assertEqual(1);
      expect(hits[0].layerId).assertEqual('circles');
      expect(hits[0].sourceId).assertEqual('places');
      const feature = hits[0].feature as GeoJsonFeature;
      expect(feature.id).assertEqual(1);
      expect(feature.properties?.['name']).assertEqual('One');
      expect(JSON.stringify(hits[0].state)).assertEqual('{"selected":true}');

      const session = testMap.controller.renderSession;
      const beside = await session?.queryRenderedFeatures(
        { kind: 'point', value: { x: point.x + 60, y: point.y } }, { layerIds: ['circles'] });
      expect(beside?.length).assertEqual(0);
    });

    it('starts each style without what the app added, which it adds again', 0, async () => {
      const map = requireMap();
      await addPlaces(map);
      await setStyle(backgroundStyle('#4ad94a'));
      expect(await map.getStyleLayer('circles')).assertUndefined();
      expect(await map.getStyleSource('places')).assertUndefined();

      await addPlaces(map);
      expect((await map.getStyleLayer('circles'))?.id).assertEqual('circles');
    });
  });
}
