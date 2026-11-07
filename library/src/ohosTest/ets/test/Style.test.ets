import { beforeEach, describe, expect, it } from '@ohos/hypium';
import application from '@ohos.app.ability.application';
import fs from '@ohos.file.fs';
import geoLocationManager from '@ohos.geoLocationManager';
import image from '@ohos.multimedia.image';
import {
  ContentError,
  GeoJsonFeatureCollection,
  GeoJsonSourceHandle,
  ImageSourceHandle,
  LayerHandle,
  MapContent,
  MapController,
  MapError,
  MapStyle,
  RenderedFeature,
  ScreenPoint,
  SourceHandle,
  StyleLayer,
} from '@maplibre/arkui';
import { readPixelMap } from '@maplibre/arkui/src/main/ets/content/internal/PixelMaps';
import { USER_LOCATION_LAYER } from '@maplibre/arkui/src/main/ets/location/internal/UserLocationLayer';
import { CommandCompletion, FeatureStateSelector, LatLng as FfiLatLng, MapHandle } from '@maplibre/native-ffi';

import { backgroundStyle, showsMap, styleDocument, testMap } from '../testability/TestMaps';
import { eventually, pixelFor, setStyle, until, withMap } from './helpers';

const PLACES: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', id: 1, geometry: { type: 'Point', coordinates: [20, 10] }, properties: { 'name': 'One' } },
    { type: 'Feature', id: 2, geometry: { type: 'Point', coordinates: [-40, -20] }, properties: { 'name': 'Two' } },
  ],
};

const ONE: FeatureStateSelector = { sourceId: 'places', featureId: { kind: 'doubleValue', value: 1 } };

const FIRST_PLACE: GeoJsonFeatureCollection = { type: 'FeatureCollection', features: PLACES.features.slice(0, 1) };

// A base style with a layer to place content under, a global state default,
// and no network requests.
const BASE = styleDocument('{"version":8,"state":{"mode":{"default":"day"}},' +
  '"sources":{"base":{"type":"geojson","data":{"type":"FeatureCollection","features":[]}}},' +
  '"layers":[{"id":"background","type":"background","paint":{"background-color":"#4a90d9"}},' +
  '{"id":"labels","type":"symbol","source":"base"}]}');

function mapStyle(): MapStyle {
  return testMap.controller.style;
}

// A GeoJSON source of `data`, as the app adds it or the content declares it.
function geoJson(data: GeoJsonFeatureCollection | string): Record<string, Object> {
  return { 'type': 'geojson', 'data': data };
}

// A circle layer of the content that draws the source `source`.
function dots(source: string, radius: number = 12): StyleLayer {
  return { id: 'dots', type: 'circle', source: source, paint: { 'circle-radius': radius, 'circle-color': '#ffffff' } };
}

// A pixel map of one opaque pixel.
function pixel(): image.PixelMap {
  return image.createPixelMapSync(new Uint8Array([255, 0, 0, 255]).buffer, {
    size: { width: 1, height: 1 },
    srcPixelFormat: image.PixelMapFormat.RGBA_8888,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
  });
}

// Fails unless `block` throws an Error whose message has `text`.
function expectThrow(text: string, block: () => Object | undefined): void {
  let message = 'nothing';
  try {
    block();
  } catch (error) {
    message = (error as Error).message;
  }
  expect(message.includes(text)).message(`threw ${message}, without ${text}`).assertTrue();
}

// The message that `promise` rejects with, or 'nothing'.
async function rejection(promise: Promise<Object | undefined>): Promise<string> {
  try {
    await promise;
    return 'nothing';
  } catch (error) {
    return (error as Error).message;
  }
}

function ids(handles: (LayerHandle | SourceHandle)[] | undefined): string {
  return (handles ?? []).map((handle: LayerHandle | SourceHandle) => handle.id).join(',');
}

// Waits until the style has the layer `id`, and returns its handle.
function layerNamed(id: string): Promise<LayerHandle> {
  return eventually(`the style has layer ${id}`, () => mapStyle().getLayer(id));
}

// Waits until the source `id` has `count` features in its loaded tiles.
async function untilFeatures(id: string, count: number): Promise<void> {
  await eventually(`source ${id} has ${count} features`, async () => {
    const features = await testMap.controller.querySourceFeatures(id);
    return features?.length === count ? true : undefined;
  });
}

function contentFailed(id: string): boolean {
  return testMap.failures.some((error: MapError) => error instanceof ContentError && error.id === id);
}

function fix(latitude: number, longitude: number): geoLocationManager.Location {
  return {
    latitude: latitude, longitude: longitude, altitude: 0, accuracy: 0, speed: 0, direction: 0,
    timeStamp: Date.now(), timeSinceBoot: 0,
  };
}

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
      expect(() => readPixelMap(rgb565)).assertThrowError(`Unsupported pixel format ${image.PixelMapFormat.RGB_565}: ` +
        'a pixel map must be RGBA_8888 or BGRA_8888');
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

      // The layer can draw before the state applies, so wait for both.
      const hits = await eventually('the query finds the feature with its state', async () => {
        const found = await testMap.controller.queryRenderedFeatures(point, { layers: ['circles'] });
        return found !== undefined && found.length > 0 && JSON.stringify(found[0].state) !== '{}' ? found : undefined;
      });
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

    it('lists the layers bottom to top, without the library\'s', 0, async () => {
      await testMap.reset(BASE);
      const below: StyleLayer = dots('places');
      below.below = 'labels';
      testMap.content = { sources: [{ id: 'places', json: geoJson(PLACES) }], layers: [below] };
      testMap.userLocation = fix(0, 0);
      await layerNamed('dots');
      await eventually('the indicator draws',
        async () => withMap((ffi: MapHandle) => ffi.getStyleLayer(USER_LOCATION_LAYER)));

      const layers = await mapStyle().getLayers();
      expect(ids(layers)).assertEqual('background,dots,labels');
      expect(layers?.[1].type).assertEqual('circle');
      expect(layers?.[1].source).assertEqual('places');
      expect(layers?.[1].sourceLayer).assertUndefined();
      expect(layers?.[0].source).assertUndefined();
      expect(await mapStyle().getLayer(USER_LOCATION_LAYER)).assertUndefined();
      const sources = await mapStyle().getSources();
      expect(ids(sources).split(',').sort().join(',')).assertEqual('base,places');
      expect(sources?.[0].type).assertEqual('geojson');
      expect(sources?.every((source: SourceHandle) => source instanceof GeoJsonSourceHandle)).assertTrue();
    });

    it('sets a base layer\'s property, and restores its default with null', 0, async () => {
      const background = await layerNamed('background');
      expect(await background.setProperty('background-opacity', 0.5)).assertTrue();
      expect(await background.getProperty('background-opacity')).assertEqual(0.5);
      expect(await background.setProperty('background-opacity', null)).assertTrue();
      expect(await background.getProperty('background-opacity')).assertUndefined();

      const transition: Record<string, Object> = { 'duration': 500, 'delay': 0 };
      expect(await background.setProperty('background-opacity-transition', transition)).assertTrue();
      const set = await background.getProperty('background-opacity-transition') as Record<string, Object>;
      expect(set['duration']).assertEqual(500);
      expect(await background.setProperty('background-opacity-transition', null)).assertTrue();

      expectThrow('type', () => background.setProperty('type', 'fill'));
      // A value that the map rejects rejects, and the next write goes on.
      expect(await rejection(background.setProperty('background-opacity', 'opaque')))
        .assertContain('background-opacity');
      expect(await background.setProperty('background-opacity', 0.25)).assertTrue();
      expect(await background.getProperty('background-opacity')).assertEqual(0.25);
    });

    it('reads the content\'s and the library\'s IDs, and throws for their writes', 0, async () => {
      const pin = pixel();
      testMap.content = {
        sources: [{ id: 'places', json: geoJson(PLACES) }],
        layers: [dots('places')],
        images: [{ id: 'pin', image: pin }],
      };
      const layer = await layerNamed('dots');
      expect(await layer.getProperty('circle-radius')).assertEqual(12);
      expectThrow('dots', () => layer.setProperty('circle-radius', 4));
      const source = await mapStyle().getGeoJsonSource('places');
      expect(source?.type).assertEqual('geojson');
      expectThrow('places', () => source?.setData(PLACES));
      expectThrow('places', () => source?.remove());
      expectThrow('places', () => mapStyle().addSource({ id: 'places', json: geoJson(PLACES) }));
      expectThrow('pin', () => mapStyle().setImage({ id: 'pin', image: pin }));
      expectThrow('pin', () => mapStyle().removeImage('pin'));

      expectThrow('maplibre-arkui-places',
        () => mapStyle().addSource({ id: 'maplibre-arkui-places', json: geoJson(PLACES) }));
      expectThrow('maplibre-arkui-pin', () => mapStyle().setImage({ id: 'maplibre-arkui-pin', image: pin }));
      expectThrow('maplibre-arkui:font-scale', () => mapStyle().setGlobalStateProperty('maplibre-arkui:font-scale', 2));
      const state = await mapStyle().getGlobalState();
      expect(state === undefined || Object.keys(state).some((name: string) => name.startsWith('maplibre-arkui')))
        .assertFalse();
      pin.release();
    });

    it('resolves undefined and false while no map shows the controller', 0, async () => {
      const unused = new MapController().style;
      expect(await unused.getSource('places')).assertUndefined();
      expect(await unused.getSources()).assertUndefined();
      expect(await unused.getLayers()).assertUndefined();
      expect(await unused.getGlobalState()).assertUndefined();
      expect(await unused.getTransition()).assertUndefined();
      expect(await unused.getLightProperty('anchor')).assertUndefined();
      expect(await unused.addSource({ id: 'places', json: geoJson(PLACES) })).assertUndefined();
      const pin = pixel();
      expect(await unused.setImage({ id: 'pin', image: pin })).assertFalse();
      pin.release();
      expect(await unused.removeImage('pin')).assertFalse();
      expect(await unused.setGlobalStateProperty('mode', 'night')).assertFalse();
      expect(await unused.setTransition({ durationMs: 0 })).assertFalse();
      expect(await unused.setLight({ 'intensity': 0.5 })).assertFalse();

      // The handles of a map that left.
      const background = await layerNamed('background');
      testMap.firstMap = false;
      await until('the map leaves', () => !showsMap(testMap.controller));
      expect(await mapStyle().getLayers()).assertUndefined();
      expect(await background.getProperty('background-color')).assertUndefined();
      expect(await background.setProperty('background-opacity', 0.5)).assertFalse();
    });

    it('starts each style without the app\'s changes, and expires the old handles', 0, async () => {
      await testMap.reset(BASE);
      const added = await mapStyle().addSource({ id: 'extra', json: geoJson(PLACES) });
      expect(added?.id).assertEqual('extra');
      const background = await layerNamed('background');
      expect(await background.setProperty('background-opacity', 0.5)).assertTrue();
      expect(await mapStyle().setGlobalStateProperty('mode', 'night')).assertTrue();
      expect(await mapStyle().setTransition({ durationMs: 0 })).assertTrue();

      await setStyle(BASE);
      expect(await added?.remove()).assertFalse();
      expect(await background.getProperty('background-opacity')).assertUndefined();
      expect(await background.setProperty('background-opacity', 0.5)).assertFalse();
      expect(await mapStyle().getSource('extra')).assertUndefined();
      expect((await mapStyle().getGlobalState())?.['mode']).assertEqual('day');
      expect((await mapStyle().getTransition())?.durationMs).assertEqual(300);
      expect(await (await layerNamed('background')).getProperty('background-opacity')).assertUndefined();
    });

    it('expires the handles of a source and layer that the content replaces', 0, async () => {
      testMap.content = { sources: [{ id: 'places', json: geoJson(PLACES) }], layers: [dots('places')] };
      const layer = await layerNamed('dots');
      const source = await mapStyle().getSource('places');
      expectThrow('places', () => source?.remove());

      // A new maxzoom replaces the source, and the layer that draws it.
      const json = geoJson(PLACES);
      json['maxzoom'] = 10;
      testMap.content = { sources: [{ id: 'places', json: json }], layers: [dots('places', 6)] };
      await eventually('the content replaces the layer', async () =>
        (await (await mapStyle().getLayer('dots'))?.getProperty('circle-radius')) === 6 ? true : undefined);
      expect(await layer.getProperty('circle-radius')).assertUndefined();
      expect(await source?.remove()).assertFalse();
    });

    it('draws a content layer once the app adds its source, which it keeps while the layer draws it', 0, async () => {
      testMap.content = { layers: [dots('app-places')] };
      await until('the map rejects the layer', () => contentFailed('dots'));
      const added = await mapStyle().addSource({ id: 'app-places', json: geoJson(PLACES) });
      expect(added?.type).assertEqual('geojson');
      expect((await mapStyle().getLayer('dots'))?.source).assertEqual('app-places');
      await queryAt(pixelFor({ latitude: 10, longitude: 20 }), ['dots']);

      expect(await rejection(added?.remove() ?? Promise.resolve(false))).assertContain('app-places');
      expect((await mapStyle().getSource('app-places'))?.id).assertEqual('app-places');
      testMap.content = {};
      await eventually('the layer goes',
        async () => await mapStyle().getLayer('dots') === undefined ? true : undefined);
      expect(await added?.remove()).assertTrue();
      expect(await mapStyle().getSource('app-places')).assertUndefined();
      expect(await added?.remove()).assertFalse();
    });

    it('replaces an added source\'s data with an object or a URL', 0, async () => {
      const path = `${application.getApplicationContext().cacheDir}/first-${Date.now()}.geojson`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(FIRST_PLACE));
      fs.closeSync(file);
      try {
        await testMap.controller.updateCamera({ zoom: 0 });
        testMap.content = { layers: [dots('app-places')] };
        const empty: GeoJsonFeatureCollection = { type: 'FeatureCollection', features: [] };
        const added = await mapStyle().addSource({ id: 'app-places', json: geoJson(empty) });
        expect(added instanceof GeoJsonSourceHandle).assertTrue();
        const source = added as GeoJsonSourceHandle;
        await layerNamed('dots');
        expect(await source.setData(PLACES)).assertTrue();
        await untilFeatures('app-places', 2);
        expect(await source.setData(`file://${path}`)).assertTrue();
        await untilFeatures('app-places', 1);
      } finally {
        fs.unlinkSync(path);
      }
    });

    it('replaces an added source that the content declares', 0, async () => {
      await testMap.controller.updateCamera({ zoom: 0 });
      const added = await mapStyle().addSource({ id: 'shared', json: geoJson(PLACES) });
      const content: MapContent = { sources: [{ id: 'shared', json: geoJson(FIRST_PLACE) }], layers: [dots('shared')] };
      testMap.content = content;
      await untilFeatures('shared', 1);
      expect(await added?.remove()).assertFalse();
      expect(contentFailed('shared')).assertFalse();
      expectThrow('shared', () => mapStyle().addSource({ id: 'shared', json: geoJson(PLACES) }));
    });

    it('sets and removes an image, from pixels that it copies', 0, async () => {
      const pin = pixel();
      const set = mapStyle().setImage({ id: 'dot', image: pin, pixelRatio: 2 });
      pin.release();
      expect(await set).assertTrue();
      expect((await withMap((ffi: MapHandle) => ffi.getStyleImage('dot')))?.pixelRatio).assertEqual(2);
      expect(await mapStyle().removeImage('dot')).assertTrue();
      expect(await withMap((ffi: MapHandle) => ffi.getStyleImage('dot'))).assertUndefined();
      expect(await rejection(mapStyle().removeImage('dot'))).assertContain('dot');
      const other = pixel();
      expectThrow('0', () => mapStyle().setImage({ id: 'dot', image: other, pixelRatio: 0 }));
      other.release();
    });

    it('changes an image source\'s image and corners', 0, async () => {
      const corners: number[][] = [[-20, 20], [20, 20], [20, -20], [-20, -20]];
      const json: Record<string, Object> = {
        'type': 'image', 'url': 'file:///nonexistent.png', 'coordinates': corners,
      };
      await mapStyle().addSource({ id: 'picture', json: json });
      const source = await mapStyle().getImageSource('picture');
      expect(source?.type).assertEqual('image');
      expect((await mapStyle().getSource('picture')) instanceof ImageSourceHandle).assertTrue();
      expect(await mapStyle().getGeoJsonSource('picture')).assertUndefined();
      const pin = pixel();
      const set = source?.setImage(pin);
      pin.release();
      expect(await set).assertTrue();
      expect(await source?.setCoordinates([{ latitude: 10, longitude: -10 }, { latitude: 10, longitude: 10 },
        { latitude: -10, longitude: 10 }, { latitude: -10, longitude: -10 }])).assertTrue();
      const moved = await withMap((ffi: MapHandle) => ffi.getImageSourceCoordinates('picture'));
      expect(moved.map((corner: FfiLatLng) => `${corner.latitude},${corner.longitude}`).join(' '))
        .assertEqual('10,-10 10,10 -10,10 -10,-10');
      expectThrow('3', () => source?.setCoordinates([{ latitude: 0, longitude: 0 }, { latitude: 0, longitude: 1 },
        { latitude: 1, longitude: 1 }]));
    });

    it('restores a global state property\'s default with null', 0, async () => {
      await testMap.reset(BASE);
      expect((await mapStyle().getGlobalState())?.['mode']).assertEqual('day');
      expect(await mapStyle().setGlobalStateProperty('mode', 'night')).assertTrue();
      expect((await mapStyle().getGlobalState())?.['mode']).assertEqual('night');
      expect(await mapStyle().setGlobalStateProperty('mode', null)).assertTrue();
      expect((await mapStyle().getGlobalState())?.['mode']).assertEqual('day');
      expect(await mapStyle().setGlobalStateProperty('size', 2)).assertTrue();
      expect((await mapStyle().getGlobalState())?.['size']).assertEqual(2);
      expect(await mapStyle().setGlobalStateProperty('size', null)).assertTrue();
      expect((await mapStyle().getGlobalState())?.['size']).assertUndefined();
    });

    it('reads back the transition and the light that it sets', 0, async () => {
      expect(JSON.stringify(await mapStyle().getTransition()))
        .assertEqual('{"durationMs":300,"delayMs":0,"placementTransitions":true}');
      expect(await mapStyle().setTransition({ durationMs: 120, delayMs: 30, placementTransitions: false }))
        .assertTrue();
      expect(JSON.stringify(await mapStyle().getTransition()))
        .assertEqual('{"durationMs":120,"delayMs":30,"placementTransitions":false}');
      expectThrow('-1', () => mapStyle().setTransition({ durationMs: -1 }));

      expect(await mapStyle().setLight({ 'anchor': 'map', 'intensity': 0.25 })).assertTrue();
      expect(await mapStyle().getLightProperty('anchor')).assertEqual('map');
      expect(await mapStyle().getLightProperty('intensity')).assertEqual(0.25);
    });
  });
}
