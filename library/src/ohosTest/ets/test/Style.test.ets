import { beforeEach, describe, expect, it } from '@ohos/hypium';
import application from '@ohos.app.ability.application';
import display from '@ohos.display';
import fs from '@ohos.file.fs';
import geoLocationManager from '@ohos.geoLocationManager';
import image from '@ohos.multimedia.image';
import {
  cases,
  ContentError,
  featureState,
  GeoJsonFeature,
  GeoJsonFeatureCollection,
  GeoJsonSourceHandle,
  has,
  image as styleImage,
  ImageSourceHandle,
  LatLng,
  LayerHandle,
  MapContent,
  MapController,
  MapError,
  MapLogRecord,
  MapRuntime,
  MapStyle,
  RenderedFeature,
  ResolvedStyleImage,
  ScreenPoint,
  SourceHandle,
  StyleImageMissingEvent,
  StyleLayer,
  toBoolean,
} from '@maplibre/arkui';
import { readPixelMap } from '@maplibre/arkui/src/main/ets/content/internal/PixelMaps';
import { USER_LOCATION_LAYER } from '@maplibre/arkui/src/main/ets/location/internal/UserLocationLayer';
import { CommandCompletion, FeatureStateSelector, LatLng as FfiLatLng, MapHandle } from '@maplibre/native-ffi';

import { backgroundStyle, showsMap, styleDocument, testMap } from '../testability/TestMaps';
import { eventually, frames, mapBounds, pixelFor, screenPixel, setStyle, until, vp2px, withMap } from './helpers';

const PLACES: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', id: 1, geometry: { type: 'Point', coordinates: [20, 10] }, properties: { 'name': 'One' } },
    { type: 'Feature', id: 2, geometry: { type: 'Point', coordinates: [-40, -20] }, properties: { 'name': 'Two' } },
  ],
};

const ONE: FeatureStateSelector = { sourceId: 'places', featureId: { kind: 'doubleValue', value: 1 } };

// Five points close together, which a clustered source draws as one cluster,
// and one far away.
const CROWD: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: [[0, 0], [0.1, 0], [0, 0.1], [0.1, 0.1], [0.05, 0.05], [-40, -20]].map(
    (position: number[], i: number): GeoJsonFeature => ({
      type: 'Feature', id: i + 1, geometry: { type: 'Point', coordinates: position }, properties: { 'n': i },
    })),
};

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

// An opaque red square, `size` px on each side.
function square(size: number): image.PixelMap {
  const pixels = new Uint8Array(size * size * 4);
  for (let i = 0; i < pixels.length; i += 4) {
    pixels[i] = 255;
    pixels[i + 3] = 255;
  }
  return image.createPixelMapSync(pixels.buffer, {
    size: { width: size, height: size },
    srcPixelFormat: image.PixelMapFormat.RGBA_8888,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
  });
}

// The places as content, in symbol layers that show the image of each ID
// alone, or the image that `icon` gives for it.
function icons(ids: string[], icon: (id: string) => Object = (id: string): Object => id): MapContent {
  const layers = ids.map((id: string): StyleLayer => ({
    id: `icons-${id}`, type: 'symbol', source: 'places',
    layout: { 'icon-image': icon(id), 'icon-allow-overlap': true },
  }));
  return { sources: [{ id: 'places', json: geoJson(PLACES) }], layers: layers };
}

// Lays the symbols out again, in new tiles, which would ask for their images
// again, and waits a while.
async function layOutAgain(): Promise<void> {
  await testMap.controller.updateCamera({ zoom: 3 });
  await frames(30);
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

// Waits until the content's GeoJSON source `id` is in the style, and returns
// its handle.
function geoJsonNamed(id: string): Promise<GeoJsonSourceHandle> {
  return eventually(`the style has source ${id}`, () => mapStyle().getGeoJsonSource(id));
}

// Shows the places as content, in circles that are red while their feature
// state is selected, and white otherwise, and returns the source's handle.
// Until maplibre-native-ffi#1746 is fixed, an earlier case's feature state can
// carry over to the source, so it starts without any.
async function selectableDots(): Promise<GeoJsonSourceHandle> {
  const color = cases([[toBoolean(featureState('selected')), '#ff0000']], '#ffffff');
  const layer: StyleLayer = { id: 'dots', type: 'circle', source: 'places',
    paint: { 'circle-radius': 12, 'circle-color': color } };
  testMap.content = { sources: [{ id: 'places', json: geoJson(PLACES) }], layers: [layer] };
  const source = await geoJsonNamed('places');
  await source.resetFeatureStates();
  return source;
}

// Waits until the screen shows red at `coordinate` of the map, or doesn't.
async function untilRed(coordinate: LatLng, red: boolean): Promise<void> {
  await eventually(`the map draws ${red ? 'red' : 'white'} at ${coordinate.latitude}, ${coordinate.longitude}`,
    async () => {
      const bounds = await mapBounds();
      const point = pixelFor(coordinate);
      const pixel = await screenPixel({
        x: bounds.left + Math.round(vp2px(point.x)), y: bounds.top + Math.round(vp2px(point.y)),
      });
      return pixel[0] > 200 && (pixel[1] < 80) === red && (pixel[2] < 80) === red ? true : undefined;
    });
}

// A feature state as JSON, with its keys in order.
function state(value: Record<string, Object> | undefined): string {
  return value === undefined ? 'undefined' : JSON.stringify(value, Object.keys(value).sort());
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
      expect(layers?.map((layer: LayerHandle) => layer.fromContent).join(',')).assertEqual('false,true,false');
      expect(layers?.[1].type).assertEqual('circle');
      expect(layers?.[1].source).assertEqual('places');
      expect(layers?.[1].sourceLayer).assertUndefined();
      expect(layers?.[0].source).assertUndefined();
      expect(await mapStyle().getLayer(USER_LOCATION_LAYER)).assertUndefined();
      const sources = await mapStyle().getSources();
      expect(ids(sources).split(',').sort().join(',')).assertEqual('base,places');
      expect(sources?.[0].type).assertEqual('geojson');
      expect(sources?.every((source: SourceHandle) => source instanceof GeoJsonSourceHandle)).assertTrue();
      expect(sources?.find((source: SourceHandle) => source.id === 'places')?.fromContent).assertTrue();
      expect(sources?.find((source: SourceHandle) => source.id === 'base')?.fromContent).assertFalse();
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
      };
      const layer = await layerNamed('dots');
      expect(await layer.getProperty('circle-radius')).assertEqual(12);
      expectThrow('dots', () => layer.setProperty('circle-radius', 4));
      const source = await mapStyle().getGeoJsonSource('places');
      expect(source?.type).assertEqual('geojson');
      expectThrow('places', () => source?.setData(PLACES));
      expectThrow('places', () => source?.remove());
      expectThrow('places', () => mapStyle().addSource({ id: 'places', json: geoJson(PLACES) }));

      expectThrow('maplibre-arkui-places',
        () => mapStyle().addSource({ id: 'maplibre-arkui-places', json: geoJson(PLACES) }));
      expectThrow('maplibre-arkui-pin', () => mapStyle().setImage('maplibre-arkui-pin', { image: pin }));
      expectThrow('maplibre-arkui:font-scale', () => mapStyle().setGlobalStateProperty('maplibre-arkui:font-scale', 2));
      expect(await mapStyle().getGlobalStateProperty('maplibre-arkui:font-scale')).assertUndefined();
      pin.release();
    });

    it('resolves undefined and false while no map shows the controller', 0, async () => {
      const unused = new MapController().style;
      expect(await unused.getSource('places')).assertUndefined();
      expect(await unused.getSources()).assertUndefined();
      expect(await unused.getLayers()).assertUndefined();
      expect(await unused.getGlobalStateProperty('mode')).assertUndefined();
      expect(await unused.getTransition()).assertUndefined();
      expect(await unused.getLightProperty('anchor')).assertUndefined();
      expect(await unused.addSource({ id: 'places', json: geoJson(PLACES) })).assertUndefined();
      const pin = pixel();
      expect(await unused.setImage('pin', { image: pin })).assertFalse();
      pin.release();
      expect(await unused.removeImage('pin')).assertFalse();
      expect(await unused.setGlobalStateProperty('mode', 'night')).assertFalse();
      expect(await unused.setTransition({ durationMs: 0 })).assertFalse();
      expect(await unused.setLightProperty('intensity', 0.5)).assertFalse();

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
      expect(await mapStyle().getGlobalStateProperty('mode')).assertEqual('day');
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
        // Data that waits behind the data that the source prepares, and that
        // newer data replaces, resolves false instead of rejecting.
        const preparing = source.setData(PLACES);
        const waiting = source.setData(PLACES);
        expect(await source.setData(FIRST_PLACE)).assertTrue();
        expect(typeof await preparing).assertEqual('boolean');
        expect(typeof await waiting).assertEqual('boolean');
        await untilFeatures('app-places', 1);
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
      const set = mapStyle().setImage('dot', { image: pin });
      pin.release();
      expect(await set).assertTrue();
      expect((await withMap((ffi: MapHandle) => ffi.getStyleImage('dot')))?.pixelRatio)
        .assertEqual(display.getDefaultDisplaySync().densityPixels);
      expect(await mapStyle().removeImage('dot')).assertTrue();
      expect(await withMap((ffi: MapHandle) => ffi.getStyleImage('dot'))).assertUndefined();
      expect(await mapStyle().removeImage('dot')).assertFalse();
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
      expect(await mapStyle().getGlobalStateProperty('mode')).assertEqual('day');
      expect(await mapStyle().setGlobalStateProperty('mode', 'night')).assertTrue();
      expect(await mapStyle().getGlobalStateProperty('mode')).assertEqual('night');
      expect(await mapStyle().setGlobalStateProperty('mode', null)).assertTrue();
      expect(await mapStyle().getGlobalStateProperty('mode')).assertEqual('day');
      expect(await mapStyle().setGlobalStateProperty('size', 2)).assertTrue();
      expect(await mapStyle().getGlobalStateProperty('size')).assertEqual(2);
      expect(await mapStyle().setGlobalStateProperty('size', null)).assertTrue();
      expect(await mapStyle().getGlobalStateProperty('size')).assertUndefined();
    });

    it('sets, reads, removes, and resets the feature state of a content source', 0, async () => {
      const source = await selectableDots();
      const one: Record<string, Object> = { 'selected': true, 'size': 2 };
      expect(await source.setFeatureState(1, one)).assertTrue();
      expect(state(await source.getFeatureState(1))).assertEqual('{"selected":true,"size":2}');
      // The map compares IDs as text, so the string names the same feature.
      expect(state(await source.getFeatureState('1'))).assertEqual('{"selected":true,"size":2}');
      const hit = await eventually('the query finds the state', async () => {
        const hits = await queryAt(pixelFor({ latitude: 10, longitude: 20 }), ['dots']);
        return state(hits[0].state).includes('selected') ? hits[0] : undefined;
      });
      expect(state(hit.state)).assertEqual('{"selected":true,"size":2}');

      // Merges, and removes one key.
      const size: Record<string, Object> = { 'size': 3 };
      expect(await source.setFeatureState(1, size)).assertTrue();
      expect(state(await source.getFeatureState(1))).assertEqual('{"selected":true,"size":3}');
      expect(await source.removeFeatureState(1, 'size')).assertTrue();
      expect(state(await source.getFeatureState(1))).assertEqual('{"selected":true}');
      expect(await source.removeFeatureState(1)).assertTrue();
      expect(state(await source.getFeatureState(1))).assertEqual('{}');

      expect(await source.setFeatureState(1, one)).assertTrue();
      expect(await source.setFeatureState(2, one)).assertTrue();
      expect(await source.resetFeatureStates()).assertTrue();
      expect(state(await source.getFeatureState(1))).assertEqual('{}');
      expect(state(await source.getFeatureState(2))).assertEqual('{}');

      const cyclic: Record<string, Object> = {};
      cyclic['self'] = cyclic;
      expectThrow('JSON', () => source.setFeatureState(1, cyclic));
    });

    it('draws a feature state change on an idle map', 0, async () => {
      const source = await selectableDots();
      const one: LatLng = { latitude: 10, longitude: 20 };
      const two: LatLng = { latitude: -20, longitude: -40 };
      await untilRed(two, false);
      const selected: Record<string, Object> = { 'selected': true };
      expect(await source.setFeatureState(1, selected)).assertTrue();
      await untilRed(one, true);

      // A selection that moves: the map applies both in one frame.
      await Promise.all([source.removeFeatureState(1), source.setFeatureState(2, selected)]);
      await untilRed(two, true);
      await untilRed(one, false);
    });

    it('expires a source\'s handle with its style, and resets a new style\'s feature state', 0, async () => {
      const source = await selectableDots();
      const selected: Record<string, Object> = { 'selected': true };
      expect(await source.setFeatureState(1, selected)).assertTrue();

      await setStyle(backgroundStyle('#4ad94a'));
      expect(await source.setFeatureState(1, selected)).assertFalse();
      expect(await source.removeFeatureState(1)).assertFalse();
      expect(await source.resetFeatureStates()).assertFalse();
      expect(await source.getFeatureState(1)).assertUndefined();
      const again = await geoJsonNamed('places');
      expect(await again.resetFeatureStates()).assertTrue();
      expect(state(await again.getFeatureState(1))).assertEqual('{}');
    });

    it('reads a cluster\'s expansion zoom, children, and leaves', 0, async () => {
      const json = geoJson(CROWD);
      json['cluster'] = true;
      const plain: StyleLayer = dots('plain');
      plain.id = 'plain-dots';
      testMap.content = {
        sources: [{ id: 'crowd', json: json }, { id: 'plain', json: geoJson(PLACES) }],
        layers: [{ id: 'clusters', type: 'circle', source: 'crowd', filter: has('point_count'),
          paint: { 'circle-radius': 12 } }, plain],
      };
      const source = await geoJsonNamed('crowd');
      const hits = await queryAt(pixelFor({ latitude: 0.05, longitude: 0.05 }), ['clusters']);
      const cluster = hits[0].feature;
      expect(cluster.properties?.['point_count']).assertEqual(5);

      const zoom = await source.getClusterExpansionZoom(cluster);
      expect(zoom ?? 0).assertLarger(1);
      // The children hold the cluster's five points between them.
      const children = await source.getClusterChildren(cluster);
      expect(children?.features.length ?? 0).assertLarger(0);
      const points = (children?.features ?? []).reduce((sum: number, child: GeoJsonFeature): number =>
        sum + ((child.properties?.['point_count'] as number | undefined) ?? 1), 0);
      expect(points).assertEqual(5);

      expect((await source.getClusterLeaves(cluster, 10, 0))?.features.length).assertEqual(5);
      expect((await source.getClusterLeaves(cluster, 2, 0))?.features.length).assertEqual(2);
      expect((await source.getClusterLeaves(cluster, 10, 3))?.features.length).assertEqual(2);
      expect((await source.getClusterLeaves(cluster, 0, 0))?.features.length).assertEqual(0);
      const leaves = await source.getClusterLeaves(cluster, 10, 0);
      expect(leaves?.features.every((leaf: GeoJsonFeature) => leaf.properties?.['cluster'] === undefined))
        .assertTrue();
      expectThrow('-1', () => source.getClusterLeaves(cluster, -1, 0));
      expectThrow('0.5', () => source.getClusterLeaves(cluster, 1, 0.5));

      // A point, a cluster that the source doesn't have, and a source that
      // doesn't cluster.
      const point: GeoJsonFeature = { type: 'Feature', geometry: null, properties: { 'n': 0 } };
      expect(await source.getClusterExpansionZoom(point)).assertUndefined();
      const unknown: GeoJsonFeature = { type: 'Feature', geometry: null, properties: { 'cluster_id': 123456 } };
      expect(await source.getClusterExpansionZoom(unknown)).assertUndefined();
      expect(await source.getClusterChildren(unknown)).assertUndefined();
      expect(await source.getClusterLeaves(unknown, 10, 0)).assertUndefined();
      await queryAt(pixelFor({ latitude: 10, longitude: 20 }), ['plain-dots']);
      expect(await (await geoJsonNamed('plain')).getClusterExpansionZoom(cluster)).assertUndefined();
    });

    it('asks onStyleImageMissing once for an image that the style lacks, and draws the image', 0, async () => {
      const pin = square(16);
      testMap.resolveImage = (event: StyleImageMissingEvent): Promise<ResolvedStyleImage | undefined> =>
        Promise.resolve({ image: pin });
      testMap.content = icons(['pin']);
      await queryAt(pixelFor({ latitude: 10, longitude: 20 }), ['icons-pin']);
      pin.release();
      await layOutAgain();
      expect(testMap.missingImages.join()).assertEqual('pin');
      expect(testMap.errors.length).assertEqual(0);
    });

    it('asks for an image again only in the next style once the app gives none', 0, async () => {
      testMap.content = icons(['pin']);
      await until('the map asks for the image', () => testMap.missingImages.length > 0);
      await layOutAgain();
      expect(testMap.missingImages.join()).assertEqual('pin');

      await setStyle(backgroundStyle('#d94a4a'));
      await until('the next style asks for it', () => testMap.missingImages.length > 1);
      expect(testMap.missingImages.join()).assertEqual('pin,pin');
    });

    it('logs a handler that throws, and takes it as no image', 0, async () => {
      const logs: string[] = [];
      MapRuntime.setLogHandler((record: MapLogRecord) => {
        logs.push(record.message);
      });
      try {
        testMap.resolveImage = (event: StyleImageMissingEvent): Promise<ResolvedStyleImage | undefined> => {
          throw new Error('no image here');
        };
        testMap.content = icons(['pin']);
        await until('the map logs the throw', () => logs.some((message: string) => message.includes('no image here')));
        await layOutAgain();
        expect(testMap.missingImages.join()).assertEqual('pin');
        expect(testMap.errors.length).assertEqual(0);
      } finally {
        MapRuntime.setLogHandler(undefined);
      }
    });

    it('never asks for the images of expressions or the library', 0, async () => {
      const pin = square(16);
      testMap.content = icons(['pin', 'maplibre-arkui-pin', 'other'],
        (id: string): Object => id === 'pin' ? styleImage(pin) : id);
      await until('the map asks for the other image', () => testMap.missingImages.includes('other'));
      await layOutAgain();
      expect(testMap.missingImages.join()).assertEqual('other');
      testMap.content = {};
      await frames(10);
      pin.release();
    });

    it('reads back the transition and the light that it sets', 0, async () => {
      expect(JSON.stringify(await mapStyle().getTransition()))
        .assertEqual('{"durationMs":300,"delayMs":0,"placementTransitions":true}');
      expect(await mapStyle().setTransition({ durationMs: 120, delayMs: 30, placementTransitions: false }))
        .assertTrue();
      expect(JSON.stringify(await mapStyle().getTransition()))
        .assertEqual('{"durationMs":120,"delayMs":30,"placementTransitions":false}');
      expectThrow('-1', () => mapStyle().setTransition({ durationMs: -1 }));

      expect(await mapStyle().setLightProperty('anchor', 'map')).assertTrue();
      expect(await mapStyle().setLightProperty('intensity', 0.25)).assertTrue();
      expect(await mapStyle().getLightProperty('anchor')).assertEqual('map');
      expect(await mapStyle().getLightProperty('intensity')).assertEqual(0.25);
      expect(await mapStyle().setLightProperty('intensity', null)).assertTrue();
      expect(await mapStyle().getLightProperty('intensity')).assertUndefined();
      expect(await mapStyle().getLightProperty('anchor')).assertEqual('map');
      const transition: Record<string, Object> = { 'duration': 500, 'delay': 0 };
      expect(await mapStyle().setLightProperty('intensity-transition', transition)).assertTrue();
      expect(await mapStyle().setLightProperty('intensity-transition', null)).assertTrue();
      expect(await rejection(mapStyle().setLightProperty('intensity', 'bright'))).assertContain('intensity');
    });
  });
}
