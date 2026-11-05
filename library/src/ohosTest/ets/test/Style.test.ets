import { afterEach, describe, expect, it } from '@ohos/hypium';
import image from '@ohos.multimedia.image';
import {
  CameraUpdateMode,
  FeatureStateSelector,
  GeoJsonFeature,
  GeoJsonFeatureCollection,
  interpolate,
  linear,
  MapHandle,
  MapProjectionHandle,
  readPixelMap,
  RenderedFeature,
  ScreenPoint,
  StyleLayerVisibility,
  StyleSourceType,
  zoom,
} from '@maplibre/arkui';

import { STYLE, testMap } from '../testability/TestMaps';
import { eventually, until } from './until';

const PLACES: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', id: 1, geometry: { type: 'Point', coordinates: [20, 10] }, properties: { 'name': 'One' } },
    { type: 'Feature', id: 2, geometry: { type: 'Point', coordinates: [-40, -20] }, properties: { 'name': 'Two' } },
  ],
};

const ONE: FeatureStateSelector = { sourceId: 'places', featureId: { kind: 'doubleValue', value: 1 } };

function requireMap(): MapHandle {
  const map = testMap.controller.map;
  if (map === undefined) {
    throw new Error('The test map is not ready');
  }
  return map;
}

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
    afterEach(async () => {
      const map = requireMap();
      await map.removeFeatureState({ sourceId: 'places' }).catch(() => {
      });
      if (await map.getStyleLayer('circles') !== undefined) {
        await map.removeStyleLayer('circles');
      }
      if (await map.getStyleSource('places') !== undefined) {
        await map.removeStyleSource('places');
      }
    });

    it('adds and removes a GeoJSON source and a layer', 0, async () => {
      await until('the style loads', () => testMap.controller.styleLoaded);
      const map = requireMap();
      await addPlaces(map);
      expect((await map.getStyleSource('places'))?.type).assertEqual(StyleSourceType.geoJson);
      const layer = await map.getStyleLayer('circles');
      expect(layer?.type).assertEqual('circle');
      expect(layer?.sourceId).assertEqual('places');

      await map.removeStyleLayer('circles');
      await map.removeStyleSource('places');
      expect(await map.getStyleLayer('circles')).assertUndefined();
      expect(await map.getStyleSource('places')).assertUndefined();
    });

    it('sets layer properties, with an expression or a plain value', 0, async () => {
      const map = requireMap();
      await addPlaces(map);
      const radius = interpolate(linear(), zoom(), [[0, 4], [10, 16]]);
      await map.setStyleLayerProperty('circles', 'circle-radius', radius);
      expect(JSON.stringify(await map.getStyleLayerProperty('circles', 'circle-radius')))
        .assertEqual(radius.toString());

      await map.setStyleLayerProperty('circles', 'visibility', 'none');
      expect((await map.getStyleLayer('circles'))?.visibility).assertEqual(StyleLayerVisibility.none);
    });

    it('reads a PixelMap into a style image', 0, async () => {
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

      const map = requireMap();
      await map.setStyleImage('dots', readPixelMap(bgra), { pixelRatio: 2 });
      const stored = await map.getStyleImage('dots');
      expect(stored?.width).assertEqual(2);
      expect(stored?.pixelRatio).assertEqual(2);
      expect(bytes(stored?.pixels ?? new Uint8Array(0))).assertEqual('128,0,0,128,0,0,255,255');
      await map.removeStyleImage('dots');
      expect(await map.getStyleImage('dots')).assertUndefined();
      bgra.release();
      rgba.release();
    });

    it('sets, reads, and removes feature state', 0, async () => {
      const map = requireMap();
      await addPlaces(map);
      const selected: Record<string, Object> = { 'selected': true };
      await map.setFeatureState(ONE, selected);
      expect(JSON.stringify(await map.getFeatureState(ONE))).assertEqual('{"selected":true}');
      // The map compares IDs as text, so a GeoJSON number and its string are
      // one ID.
      const byText: FeatureStateSelector = { sourceId: 'places', featureId: { kind: 'stringValue', value: '1' } };
      expect(JSON.stringify(await map.getFeatureState(byText))).assertEqual('{"selected":true}');

      await map.removeFeatureState(ONE);
      expect(JSON.stringify(await map.getFeatureState(ONE))).assertEqual('{}');
    });

    it('finds the feature at its screen point, with its state', 0, async () => {
      const map = requireMap();
      await testMap.controller.updateCamera({
        mode: CameraUpdateMode.jump,
        camera: { center: { latitude: 0, longitude: 0 }, zoom: 1, bearing: 0, pitch: 0 },
      });
      await addPlaces(map);
      const selected: Record<string, Object> = { 'selected': true };
      await map.setFeatureState(ONE, selected);
      const projection = MapProjectionHandle.create(map.getSnapshot().view);
      const point = projection.pixelForLatLng({ latitude: 10, longitude: 20 });
      projection.release();

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
      const loads = testMap.styleLoads;
      testMap.style = STYLE.replace('#4a90d9', '#4ad94a');
      await until('the new style loads', () => testMap.styleLoads > loads);
      expect(await map.getStyleLayer('circles')).assertUndefined();
      expect(await map.getStyleSource('places')).assertUndefined();

      await addPlaces(map);
      expect((await map.getStyleLayer('circles'))?.id).assertEqual('circles');
      testMap.style = STYLE;
      await until('the first style loads again', () => testMap.styleLoads > loads + 1);
    });
  });
}
