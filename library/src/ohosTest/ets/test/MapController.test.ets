import { beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  addRuntimeEventListener,
  CameraTransitionMode,
  GeoJsonGeometry,
  getDefaultRuntime,
  LatLng,
  LatLngBounds,
  MapController,
  removeRuntimeEventListener,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeEventType,
  StyleLoadError,
} from '@maplibre/arkui';

import { MapHandle, MapMode } from '@maplibre/native-ffi';

import { backgroundStyle, NO_INSETS, showsMap, styleDocument, testMap } from '../testability/TestMaps';
import {
  camera,
  expectNear,
  mapId,
  mapSnapshot,
  near,
  nextFrame,
  pixelFor,
  restingCamera,
  settled,
  setStyle,
  until,
  withMap,
} from './helpers';

const SWITZERLAND: LatLngBounds = {
  southwest: { latitude: 45.82, longitude: 5.96 },
  northeast: { latitude: 47.81, longitude: 10.49 },
};

// Switzerland's corners and a point inside, and the polygon they span.
const SWISS_POINTS: LatLng[] = [SWITZERLAND.southwest, { latitude: 46.8, longitude: 8.2 }, SWITZERLAND.northeast];
const SWISS_POLYGON: GeoJsonGeometry = {
  type: 'Polygon',
  coordinates: [[[5.96, 45.82], [10.49, 45.82], [10.49, 47.81], [5.96, 47.81], [5.96, 45.82]]],
};

// Whether the bounds fit the map inside `margin` vp: both corners inside, and
// one axis tight.
function expectFitted(bounds: LatLngBounds, margin: number): void {
  const extent = mapSnapshot().view.extent;
  const southwest = pixelFor(bounds.southwest);
  const northeast = pixelFor(bounds.northeast);
  expect(southwest.x).assertLarger(margin - 1);
  expect(northeast.x).assertLess(extent.width - margin + 1);
  expect(northeast.y).assertLarger(margin - 1);
  expect(southwest.y).assertLess(extent.height - margin + 1);
  const tight = near(southwest.x, margin, 1) && near(northeast.x, extent.width - margin, 1) ||
    near(northeast.y, margin, 1) && near(southwest.y, extent.height - margin, 1);
  expect(tight).assertTrue();
}

function expectInSwitzerland(): void {
  const center = camera().center;
  expect(center.latitude).assertLarger(SWITZERLAND.southwest.latitude);
  expect(center.latitude).assertLess(SWITZERLAND.northeast.latitude);
  expect(center.longitude).assertLarger(SWITZERLAND.southwest.longitude);
  expect(center.longitude).assertLess(SWITZERLAND.northeast.longitude);
}

// A side of a padding that the cases write in vp, with 0 for one left out.
function vp(side: Length | undefined): number {
  return (side ?? 0) as number;
}

// Sets the test map's viewport insets, and waits until the map's padding is
// them around `cameraPadding`.
async function setInsets(insets: Padding, cameraPadding: Padding = NO_INSETS): Promise<void> {
  testMap.viewportInsets = insets;
  await until('the map takes the insets', () => {
    const padding = mapSnapshot().view.camera.padding;
    return near(padding.top, vp(insets.top) + vp(cameraPadding.top), 0.01) &&
      near(padding.left, vp(insets.left) + vp(cameraPadding.left), 0.01) &&
      near(padding.bottom, vp(insets.bottom) + vp(cameraPadding.bottom), 0.01) &&
      near(padding.right, vp(insets.right) + vp(cameraPadding.right), 0.01);
  });
}

// A style whose hidden layers keep the map's thread parsing it for several
// frames, so the commands sent after it wait.
function busyStyle(layers: number): Record<string, Object> {
  const parts: string[] = [];
  for (let i = 0; i < layers; i++) {
    parts.push(`{"id":"busy-${i}","type":"background","layout":{"visibility":"none"}}`);
  }
  return styleDocument(`{"version":8,"sources":{},"layers":[${parts.join(',')}]}`);
}

// FFI's padding, or the camera's, whose sides are numbers of vp.
interface Sides {
  top: number;
  left: number;
  bottom: number;
  right: number;
}

function expectPadding(actual: Padding | Sides, expected: Padding): void {
  const sides = actual as Padding;
  expectNear(vp(sides.top), vp(expected.top), 0.01);
  expectNear(vp(sides.left), vp(expected.left), 0.01);
  expectNear(vp(sides.bottom), vp(expected.bottom), 0.01);
  expectNear(vp(sides.right), vp(expected.right), 0.01);
}

function expectNoPadding(actual: Padding): void {
  expectPadding(actual, NO_INSETS);
}

function reports(flag: RuntimeEventFlag): boolean {
  return (mapSnapshot().eventMask & flag) !== RuntimeEventFlag.none;
}

async function hideMap(): Promise<void> {
  testMap.shown = false;
  await until('the map leaves', () => !showsMap(testMap.controller));
}

export default function mapControllerTest(): void {
  describe('MapController', () => {
    const map = testMap.controller;

    beforeEach(async () => {
      await testMap.reset();
    });

    it('shows the style and reports where the camera rests', 0, async () => {
      expect(map.styleLoaded).assertTrue();
      expect(showsMap(map)).assertTrue();
      expectNear((await restingCamera()).zoom, 1, 0.001);
    });

    it('jumps the camera at once', 0, async () => {
      expect(await map.updateCamera({ center: { latitude: 10, longitude: 20 }, zoom: 5 })).assertTrue();
      expectNear(camera().zoom, 5, 0.001);
      expectNear(camera().center.latitude, 10, 0.001);
      expectNear(camera().center.longitude, 20, 0.001);
      await until('the observed camera follows', () => Math.abs((map.camera.zoom) - 5) < 0.001);
    });

    it('jumps a move without a mode, even one with a duration', 0, async () => {
      const move = map.updateCamera({ zoom: 5 }, { durationMs: 10000 });
      map.cancelCameraTransitions();
      expect(await move).assertTrue();
      expectNear(camera().zoom, 5, 0.001);
    });

    it('eases a move, and resolves once it completes', 0, async () => {
      let done = false;
      const move = map.updateCamera({ zoom: 6 }, { mode: CameraTransitionMode.EASE }).then((completed: boolean) => {
        done = true;
        return completed;
      });
      await until('the camera moves', () => camera().zoom > 1.01);
      expect(camera().zoom).assertLess(6);
      expect(done).assertFalse();
      expect(await move).assertTrue();
      expectNear(camera().zoom, 6, 0.001);
    });

    it('reports the camera of each frame while the camera moves', 0, async () => {
      const animation = map.updateCamera({ zoom: 12 }, { mode: CameraTransitionMode.EASE, durationMs: 10000 });
      await until('the observed camera moves', () => map.camera.zoom > 1.01);
      expect(map.camera.zoom).assertLess(12);
      expectNear(map.camera.zoom, map.viewport?.camera.zoom ?? NaN, 0);
      map.cancelCameraTransitions();
      expect(await animation).assertFalse();
    });

    it('resolves an animation that a later one replaces', 0, async () => {
      const first = map.updateCamera({ zoom: 9 }, { mode: CameraTransitionMode.EASE, durationMs: 5000 });
      const second = map.updateCamera({ zoom: 3 }, { mode: CameraTransitionMode.EASE, durationMs: 200 });
      expect(await first).assertFalse();
      expect(await second).assertTrue();
      expectNear(camera().zoom, 3, 0.001);
    });

    it('cancels an animation where it is', 0, async () => {
      const animation = map.updateCamera({ zoom: 12 }, { mode: CameraTransitionMode.EASE, durationMs: 10000 });
      map.cancelCameraTransitions();
      expect(await animation).assertFalse();
      expect(camera().zoom).assertLess(12);
    });

    it('fits bounds inside its padding', 0, async () => {
      const completed = await map.fitCameraToBounds(SWITZERLAND, {
        fitPadding: { top: 20, left: 20, bottom: 20, right: 20 },
        bearing: 0,
        pitch: 0,
      });
      expect(completed).assertTrue();
      expectInSwitzerland();
    });

    it('fits coordinates inside its padding', 0, async () => {
      const completed = await map.fitCameraToCoordinates(SWISS_POINTS, {
        fitPadding: { top: 20, left: 20, bottom: 20, right: 20 },
        bearing: 0,
        pitch: 0,
      });
      expect(completed).assertTrue();
      expectInSwitzerland();
      expect(camera().zoom).assertLarger(4);
    });

    it('fits a geometry with an animation, which a later move can replace', 0, async () => {
      const completed = await map.fitCameraToGeometry(SWISS_POLYGON, {
        mode: CameraTransitionMode.EASE,
        durationMs: 300,
        fitPadding: { top: 20, left: 20, bottom: 20, right: 20 },
        bearing: 0,
        pitch: 0,
      });
      expect(completed).assertTrue();
      expectInSwitzerland();
      expect(camera().zoom).assertLarger(4);

      const fit = map.fitCameraToCoordinates([{ latitude: -33.86, longitude: 151.21 }], {
        mode: CameraTransitionMode.EASE,
        durationMs: 10000,
      });
      const move = map.updateCamera({ center: { latitude: 0, longitude: 0 }, zoom: 2, bearing: 0, pitch: 0 },
        { mode: CameraTransitionMode.EASE, durationMs: 200 });
      expect(await fit).assertFalse();
      expect(await move).assertTrue();
    });

    it('centers a move inside the viewport insets, which the camera leaves out', 0, async () => {
      // The sides left out are 0.
      await setInsets({ bottom: 200 });
      const target: LatLng = { latitude: 10, longitude: 20 };
      await map.updateCamera({ center: target, zoom: 5 });

      const extent = mapSnapshot().view.extent;
      const at = pixelFor(target);
      expectNear(at.x, extent.width / 2, 1);
      expectNear(at.y, (extent.height - 200) / 2, 1);
      expectNear(camera().center.latitude, target.latitude, 0.001);
      expectNoPadding((await restingCamera()).padding);
      await until('the camera rests', () => near(map.camera.zoom, 5, 0.001));
      expectNoPadding(map.camera.padding);
      expectNoPadding(testMap.cameraIdles[testMap.cameraIdles.length - 1].padding);
      await until('the frame shows the camera', () => near(map.viewport?.camera.zoom ?? 0, 5, 0.001));
      expectNoPadding(map.viewport!.camera.padding);
    });

    it('keeps the center when the viewport insets change', 0, async () => {
      const target: LatLng = { latitude: 10, longitude: 20 };
      await map.updateCamera({ center: target, zoom: 5 });
      await setInsets({ top: 100, left: 0, bottom: 0, right: 0 });
      const extent = mapSnapshot().view.extent;
      expectNear(pixelFor(target).y, (extent.height + 100) / 2, 1);
      expectNear(camera().center.latitude, target.latitude, 0.001);
      expectNoPadding((await restingCamera()).padding);
    });

    it('keeps the camera padding through inset changes that the map has yet to apply', 0, async () => {
      await setInsets({ top: 0, left: 0, bottom: 200, right: 0 });
      // While the map's thread parses the style, the page sends two inset
      // changes a frame apart, with a padding move between them.
      testMap.style = busyStyle(5000);
      await nextFrame();
      testMap.viewportInsets = NO_INSETS;
      await nextFrame();
      const padding: Padding = { top: 0, left: 30, bottom: 0, right: 0 };
      const move = map.updateCamera({ padding: padding });
      testMap.viewportInsets = { top: 0, left: 0, bottom: 100, right: 0 };
      await nextFrame();
      // None of them has applied yet.
      expectPadding(mapSnapshot().view.camera.padding, { top: 0, left: 0, bottom: 200, right: 0 });

      await settled('the move', move);
      // After the commands sent before it.
      await withMap((ffi: MapHandle) => ffi.getCamera());
      expectPadding(mapSnapshot().view.camera.padding, { top: 0, left: 30, bottom: 100, right: 0 });
      expectPadding((await restingCamera()).padding, padding);
    });

    it('keeps the camera padding that a move sent, though the app changes its object', 0, async () => {
      const padding: Padding = { top: 0, left: 30, bottom: 0, right: 0 };
      await map.updateCamera({ padding: padding });
      padding.left = 90;
      testMap.viewportInsets = { top: 0, left: 0, bottom: 100, right: 0 };
      await until('the map takes the insets', () => near(mapSnapshot().view.camera.padding.bottom, 100, 0.01));
      expectNear(vp((await restingCamera()).padding.left), 30, 0.01);
    });

    it('throws for an invalid move before it starts, and keeps the camera padding', 0, async () => {
      const padding: Padding = { top: 0, left: 30, bottom: 0, right: 0 };
      await map.updateCamera({ padding: padding });
      // A negative side that the insets would cover is still invalid.
      await setInsets({ left: 20 }, padding);
      expect(() => map.updateCamera({ padding: { left: -10 } })).assertThrowError('-10');
      expect(() => map.updateCamera({ padding: { left: 60 }, zoom: NaN })).assertThrowError('NaN');
      expect(() => map.updateCamera({ padding: { left: '10%' } })).assertThrowError('10%');
      expect(() => map.updateCamera({ padding: { left: NaN } })).assertThrowError('NaN');
      expect(() => map.updateCamera({ center: { latitude: NaN, longitude: 0 } })).assertThrowError('NaN');
      expect(() => map.updateCamera({ zoom: 2 }, { durationMs: -1 })).assertThrowError('-1');
      await nextFrame();
      expectPadding((await restingCamera()).padding, padding);
      expectPadding(mapSnapshot().view.camera.padding, { top: 0, left: 50, bottom: 0, right: 0 });
    });

    it('reports an invalid viewport inset to onError, and takes it as 0', 0, async () => {
      testMap.viewportInsets = { top: '10%', bottom: 40 };
      await until('the map reports the inset', () => testMap.errors.some((error: string) => error.includes('10%')));
      await until('the map takes the valid insets', () =>
        near(mapSnapshot().view.camera.padding.bottom, 40, 0.01));
      expectNear(mapSnapshot().view.camera.padding.top, 0, 0.01);
    });

    it('fits inside the viewport insets and its margin, and keeps neither in the camera', 0, async () => {
      await setInsets({ top: 0, left: 0, bottom: 100, right: 0 });
      const completed = await map.fitCameraToBounds(SWITZERLAND, {
        fitPadding: { top: 30, left: 30, bottom: 30, right: 30 },
        bearing: 0,
        pitch: 0,
      });
      expect(completed).assertTrue();
      expectNoPadding((await restingCamera()).padding);
      expectPadding(mapSnapshot().view.camera.padding, { top: 0, left: 0, bottom: 100, right: 0 });

      // The bounds fill the room inside the margin on one axis, and fit on
      // the other.
      const extent = mapSnapshot().view.extent;
      const southwest = pixelFor(SWITZERLAND.southwest);
      const northeast = pixelFor(SWITZERLAND.northeast);
      expect(southwest.x).assertLarger(29);
      expect(northeast.x).assertLess(extent.width - 29);
      expect(northeast.y).assertLarger(29);
      expect(southwest.y).assertLess(extent.height - 129);
      const tight = near(southwest.x, 30, 1) && near(northeast.x, extent.width - 30, 1) ||
        near(northeast.y, 30, 1) && near(southwest.y, extent.height - 130, 1);
      expect(tight).assertTrue();
    });

    it('holds a fit that comes before the map has its size, and fits the map\'s size', 0, async () => {
      await hideMap();
      testMap.shown = true;
      const fit = map.fitCameraToBounds(SWITZERLAND, {
        fitPadding: { top: 20, left: 20, bottom: 20, right: 20 },
        bearing: 0,
        pitch: 0,
      });
      expect(await fit).assertTrue();
      expectFitted(SWITZERLAND, 20);
    });

    it('applies the moves that wait for a map, in order', 0, async () => {
      await hideMap();
      const zoom = map.updateCamera({ zoom: 5 });
      const center = map.updateCamera({ center: { latitude: 10, longitude: 20 } });
      testMap.shown = true;
      expect(await zoom).assertTrue();
      expect(await center).assertTrue();
      expectNear(camera().zoom, 5, 0.001);
      expectNear(camera().center.latitude, 10, 0.001);
      expectNear(camera().center.longitude, 20, 0.001);
    });

    it('fits what the app passed when the fit waits for a map, though the app changes it', 0, async () => {
      await hideMap();
      const points: LatLng[] = SWISS_POINTS.map((point: LatLng): LatLng => ({
        latitude: point.latitude,
        longitude: point.longitude,
      }));
      const fit = map.fitCameraToCoordinates(points);
      points[0].latitude = -60;
      points.length = 0;
      testMap.shown = true;
      expect(await fit).assertTrue();
      expectInSwitzerland();
    });

    it('keeps the camera padding that a move or a fit sets', 0, async () => {
      const padding: Padding = { top: 0, left: 50, bottom: 0, right: 0 };
      await map.updateCamera({ padding: padding });
      expectPadding((await restingCamera()).padding, padding);

      // A move or a fit without padding keeps it.
      await map.updateCamera({ zoom: 3 });
      expectPadding((await restingCamera()).padding, padding);
      await map.fitCameraToCoordinates(SWISS_POINTS, { fitPadding: { top: 20, left: 20, bottom: 20, right: 20 } });
      expectPadding((await restingCamera()).padding, padding);

      // The insets add to it on the map, and the camera keeps it apart.
      await setInsets({ top: 0, left: 0, bottom: 100, right: 0 }, padding);
      expectPadding((await restingCamera()).padding, padding);

      // A fit keeps padding that a move sent just before it set, though the
      // move hasn't finished.
      const sent: Padding = { top: 0, left: 30, bottom: 0, right: 0 };
      const move = map.updateCamera({ padding: sent });
      await map.fitCameraToCoordinates(SWISS_POINTS);
      await move;
      expectPadding((await restingCamera()).padding, sent);

      // A fit with camera padding sets it, and fits inside it.
      const after: Padding = { top: 40, left: 0, bottom: 0, right: 0 };
      await map.fitCameraToBounds(SWITZERLAND, { cameraPadding: after, bearing: 0, pitch: 0 });
      expectPadding((await restingCamera()).padding, after);
      expect(pixelFor(SWITZERLAND.northeast).y).assertLarger(39);
      await until('the camera rests', () => near(vp(map.camera.padding.top), 40, 0.01));
    });

    it('resolves a fit that a move makes before it finds its camera', 0, async () => {
      const fit = map.fitCameraToBounds(SWITZERLAND);
      const move = map.updateCamera({ zoom: 2 });
      expect(await fit).assertFalse();
      expect(await move).assertTrue();
      expectNear(camera().zoom, 2, 0.001);
    });

    it('resolves the moves that wait for a map false when the app cancels them', 0, async () => {
      const unused = new MapController();
      const move = unused.updateCamera({ zoom: 3 });
      const fit = unused.fitCameraToGeometry(SWISS_POLYGON);
      unused.cancelCameraTransitions();
      expect(await move).assertFalse();
      expect(await fit).assertFalse();
      expectNear(unused.camera.zoom, 0, 0);
    });

    it('reports the map events that a runtime listener asks for, while it listens', 0, async () => {
      const runtime = await getDefaultRuntime();
      // The library's own events don't include idle.
      expect(reports(RuntimeEventFlag.mapIdle)).assertFalse();
      expect(reports(RuntimeEventFlag.mapCameraDidChange)).assertTrue();
      let idles = 0;
      let unaskedIdles = 0;
      const listener = (event: RuntimeEvent) => {
        if (event.type === RuntimeEventType.mapIdle && event.source === mapId()) {
          idles++;
        }
      };
      // A listener that asks for no map events gets none.
      const other = (event: RuntimeEvent) => {
        if (event.type === RuntimeEventType.mapIdle) {
          unaskedIdles++;
        }
      };
      addRuntimeEventListener(runtime, other);
      addRuntimeEventListener(runtime, listener, RuntimeEventFlag.mapIdle);
      try {
        await until('the map reports idle events', () => reports(RuntimeEventFlag.mapIdle));
        await map.updateCamera({ zoom: 3 });
        await until('the map goes idle', () => idles > 0);

        // A map that appears while the listener listens reports them from the
        // start.
        await hideMap();
        testMap.shown = true;
        await until('the map comes back', () => map.styleLoaded);
        expect(reports(RuntimeEventFlag.mapIdle)).assertTrue();
        const before = idles;
        await map.updateCamera({ zoom: 4 });
        await until('the new map goes idle', () => idles > before);
      } finally {
        removeRuntimeEventListener(runtime, listener);
      }
      await until('the map stops reporting idle events', () => !reports(RuntimeEventFlag.mapIdle));
      expect(reports(RuntimeEventFlag.mapCameraDidChange)).assertTrue();
      removeRuntimeEventListener(runtime, other);
      expect(unaskedIdles).assertEqual(0);
    });

    it('keeps the camera within the bounds the map is given', 0, async () => {
      testMap.cameraBounds = { maxZoom: 4 };
      await until('the bounds apply', () => mapSnapshot().bounds.maxZoom === 4);
      await map.updateCamera({ zoom: 10 });
      expectNear(camera().zoom, 4, 0.001);

      testMap.cameraBounds = {};
      await until('the bounds reset', () => mapSnapshot().bounds.maxZoom > 4);
      await map.updateCamera({ zoom: 10 });
      expectNear(camera().zoom, 10, 0.001);
    });

    it('reports invalid camera bounds to onError, and keeps the last limits', 0, async () => {
      testMap.cameraBounds = { minZoom: 2, maxZoom: 4 };
      await until('the bounds apply', () => mapSnapshot().bounds.maxZoom === 4);
      testMap.cameraBounds = { minZoom: 6, maxZoom: 4 };
      await until('the map reports the zoom range',
        () => testMap.errors.some((error: string) => error.includes('6 to 4')));
      testMap.cameraBounds = { maxPitch: NaN };
      await until('the map reports the pitch', () => testMap.errors.some((error: string) => error.includes('NaN')));
      // A later command shows that the map has applied what came before.
      await withMap((ffi: MapHandle) => ffi.getCamera());
      expect(mapSnapshot().bounds.minZoom).assertEqual(2);
      expect(mapSnapshot().bounds.maxZoom).assertEqual(4);
    });

    it('puts back the limits that FFI gives a new map when the app removes its own', 0, async () => {
      // A map's lowest zoom keeps the world as tall as the map, so the new
      // map takes the test map's size.
      const fresh = (await getDefaultRuntime()).createMap({
        initialExtent: mapSnapshot().view.extent,
        mapMode: MapMode.static,
      });
      await fresh.ready;
      const defaults = fresh.getSnapshot().bounds;
      await fresh.release();
      testMap.cameraBounds = { bounds: SWITZERLAND, minZoom: 2, maxZoom: 9, minPitch: 10, maxPitch: 30 };
      await until('the bounds apply', () => mapSnapshot().bounds.maxZoom === 9);
      testMap.cameraBounds = {};
      await until('the bounds reset', () => mapSnapshot().bounds.maxZoom > 9);
      const bounds = mapSnapshot().bounds;
      expect(bounds.unbounded).assertEqual(defaults.unbounded);
      expectNear(bounds.minZoom, defaults.minZoom, 1e-9);
      expect(bounds.maxZoom).assertEqual(defaults.maxZoom);
      expectNear(bounds.minPitch, defaults.minPitch, 1e-9);
      expectNear(bounds.maxPitch, defaults.maxPitch, 1e-9);
    });

    it('starts a map that comes back where the last one left the camera', 0, async () => {
      await map.updateCamera({ center: { latitude: -33.86, longitude: 151.21 }, zoom: 7, bearing: 45 });
      await hideMap();
      expect(map.styleLoaded).assertFalse();
      expect(map.viewport).assertUndefined();
      expectNear(map.camera.zoom, 7, 0.001);

      testMap.shown = true;
      await until('the map comes back', () => map.styleLoaded);
      expectNear(camera().center.latitude, -33.86, 0.001);
      expectNear(camera().center.longitude, 151.21, 0.001);
      expectNear(camera().zoom, 7, 0.001);
      expectNear(camera().bearing, 45, 0.001);
    });

    it('rests where a map that leaves mid-animation left the camera', 0, async () => {
      await map.updateCamera({ zoom: 2 });
      const animation = map.updateCamera({ zoom: 12 }, { mode: CameraTransitionMode.EASE, durationMs: 10000 });
      await until('the camera moves', () => camera().zoom > 2.1);
      testMap.shown = false;
      expect(await animation).assertFalse();
      const left = map.camera.zoom;
      expect(left).assertLarger(2.1);
      expect(left).assertLess(12);

      testMap.shown = true;
      await until('the map comes back', () => map.styleLoaded);
      expectNear(camera().zoom, left, 0.001);
    });

    it('loads the style it is given, as a document or a URL', 0, async () => {
      await setStyle(backgroundStyle('#d94a4a'));
      expect(JSON.stringify(await withMap((ffi: MapHandle) => ffi.getLoadedStyleJson()))).assertContain('#d94a4a');
      // A document with the same JSON doesn't load again.
      const loads = testMap.styleLoads;
      testMap.style = backgroundStyle('#d94a4a');
      await nextFrame();
      expect(map.styleLoaded).assertTrue();
      expect(testMap.styleLoads).assertEqual(loads);

      testMap.style = 'file:///nonexistent/style.json';
      await until('the map reports the error', () => testMap.failures.length > 0);
      expect(testMap.failures[0] instanceof StyleLoadError).assertTrue();
      expect(map.styleLoaded).assertFalse();
    });

    it('reports the start camera before any map, and checks arguments first', 0, async () => {
      const unused = new MapController({ camera: { zoom: 3, padding: { left: 10 } } });
      const start = unused.camera;
      expect(JSON.stringify(start)).assertEqual(
        '{"center":{"latitude":0,"longitude":0},"zoom":3,"bearing":0,"pitch":0,' +
          '"padding":{"top":0,"left":10,"bottom":0,"right":0}}');
      expect(new MapController().camera.zoom).assertEqual(0);
      expect(unused.viewport).assertUndefined();
      expect(() => new MapController({ camera: { padding: { left: '10lpx' } } })).assertThrowError('lpx');
      expect(() => unused.updateCamera({ zoom: NaN })).assertThrowError('NaN');
      expect(() => unused.fitCameraToCoordinates([])).assertThrowError('empty');
    });
  });
}
