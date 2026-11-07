import { beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  addRuntimeEventListener,
  CameraTransitionMode,
  GeoJsonGeometry,
  LatLng,
  LatLngBounds,
  MapController,
  MapHandle,
  removeRuntimeEventListener,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeEventType,
  RuntimeHandle,
} from '@maplibre/arkui';

import { MapMode } from '@maplibre/native-ffi';

import { backgroundStyle, NO_INSETS, testMap } from '../testability/TestMaps';
import { camera, expectNear, near, nextFrame, pixelFor, requireMap, settled, setStyle, until } from './helpers';

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
    const padding = requireMap().getSnapshot().view.camera.padding;
    return near(padding.top, vp(insets.top) + vp(cameraPadding.top), 0.01) &&
      near(padding.left, vp(insets.left) + vp(cameraPadding.left), 0.01) &&
      near(padding.bottom, vp(insets.bottom) + vp(cameraPadding.bottom), 0.01) &&
      near(padding.right, vp(insets.right) + vp(cameraPadding.right), 0.01);
  });
}

// A style whose hidden layers keep the map's thread parsing it for several
// frames, so the commands sent after it wait.
function busyStyle(layers: number): string {
  const parts: string[] = [];
  for (let i = 0; i < layers; i++) {
    parts.push(`{"id":"busy-${i}","type":"background","layout":{"visibility":"none"}}`);
  }
  return `{"version":8,"sources":{},"layers":[${parts.join(',')}]}`;
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

function reports(map: MapHandle, flag: RuntimeEventFlag): boolean {
  return (map.getSnapshot().eventMask & flag) !== RuntimeEventFlag.none;
}

function requireRuntime(): RuntimeHandle {
  const runtime = testMap.controller.runtime;
  if (runtime === undefined) {
    throw new Error('No map shows the controller');
  }
  return runtime;
}

export default function mapControllerTest(): void {
  describe('MapController', () => {
    const map = testMap.controller;

    beforeEach(async () => {
      await testMap.reset();
    });

    it('shows the style and reports where the camera rests', 0, async () => {
      expect(map.styleLoaded).assertTrue();
      expect(map.map !== undefined).assertTrue();
      expect(map.runtime !== undefined).assertTrue();
      await until('the camera rests', () => map.camera !== undefined);
      expectNear(map.camera?.zoom ?? NaN, 1, 0.001);
    });

    it('jumps the camera at once', 0, async () => {
      expect(await map.updateCamera({ center: { latitude: 10, longitude: 20 }, zoom: 5 })).assertTrue();
      expectNear(camera().zoom, 5, 0.001);
      expectNear(camera().center.latitude, 10, 0.001);
      expectNear(camera().center.longitude, 20, 0.001);
      await until('the observed camera follows', () => Math.abs((map.camera?.zoom ?? 0) - 5) < 0.001);
    });

    it('eases a move that has a duration, and resolves once it completes', 0, async () => {
      let done = false;
      const move = map.updateCamera({ zoom: 6 }, { durationMs: 300 }).then((completed: boolean) => {
        done = true;
        return completed;
      });
      await until('the camera moves', () => camera().zoom > 1.01);
      expect(camera().zoom).assertLess(6);
      expect(done).assertFalse();
      expect(await move).assertTrue();
      expectNear(camera().zoom, 6, 0.001);
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
      await map.cancelCameraTransitions();
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

      const extent = requireMap().getSnapshot().view.extent;
      const at = pixelFor(target);
      expectNear(at.x, extent.width / 2, 1);
      expectNear(at.y, (extent.height - 200) / 2, 1);
      expectNear(camera().center.latitude, target.latitude, 0.001);
      expectNoPadding(camera().padding);
      await until('the camera rests', () => near(map.camera?.zoom ?? 0, 5, 0.001));
      expectNoPadding(map.camera!.padding);
      expectNoPadding(testMap.cameraIdles[testMap.cameraIdles.length - 1].padding);
      await until('the frame shows the camera', () => near(map.frameCamera?.zoom ?? 0, 5, 0.001));
      expectNoPadding(map.frameCamera!.padding);
    });

    it('keeps the center when the viewport insets change', 0, async () => {
      const target: LatLng = { latitude: 10, longitude: 20 };
      await map.updateCamera({ center: target, zoom: 5 });
      await setInsets({ top: 100, left: 0, bottom: 0, right: 0 });
      const extent = requireMap().getSnapshot().view.extent;
      expectNear(pixelFor(target).y, (extent.height + 100) / 2, 1);
      expectNear(camera().center.latitude, target.latitude, 0.001);
      expectNoPadding(camera().padding);
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
      expectPadding(requireMap().getSnapshot().view.camera.padding, { top: 0, left: 0, bottom: 200, right: 0 });

      await settled('the move', move);
      // After the commands sent before it.
      await requireMap().getCamera();
      expectPadding(requireMap().getSnapshot().view.camera.padding, { top: 0, left: 30, bottom: 100, right: 0 });
      expectPadding(camera().padding, padding);
    });

    it('keeps the camera padding that a move sent, though the app changes its object', 0, async () => {
      const padding: Padding = { top: 0, left: 30, bottom: 0, right: 0 };
      await map.updateCamera({ padding: padding });
      padding.left = 90;
      testMap.viewportInsets = { top: 0, left: 0, bottom: 100, right: 0 };
      await until('the map takes the insets', () => near(requireMap().getSnapshot().view.camera.padding.bottom, 100, 0.01));
      expectNear(vp(camera().padding.left), 30, 0.01);
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
      expectPadding(camera().padding, padding);
      expectPadding(requireMap().getSnapshot().view.camera.padding, { top: 0, left: 50, bottom: 0, right: 0 });
    });

    it('reports an invalid viewport inset to onMapError, and takes it as 0', 0, async () => {
      testMap.viewportInsets = { top: '10%', bottom: 40 };
      await until('the map reports the inset', () => testMap.errors.some((error: string) => error.includes('10%')));
      await until('the map takes the valid insets', () =>
        near(requireMap().getSnapshot().view.camera.padding.bottom, 40, 0.01));
      expectNear(requireMap().getSnapshot().view.camera.padding.top, 0, 0.01);
    });

    it('fits inside the viewport insets and its margin, and keeps neither in the camera', 0, async () => {
      await setInsets({ top: 0, left: 0, bottom: 100, right: 0 });
      const completed = await map.fitCameraToBounds(SWITZERLAND, {
        fitPadding: { top: 30, left: 30, bottom: 30, right: 30 },
        bearing: 0,
        pitch: 0,
      });
      expect(completed).assertTrue();
      expectNoPadding(camera().padding);
      expectPadding(requireMap().getSnapshot().view.camera.padding, { top: 0, left: 0, bottom: 100, right: 0 });

      // The bounds fill the room inside the margin on one axis, and fit on
      // the other.
      const extent = requireMap().getSnapshot().view.extent;
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

    it('keeps the camera padding that a move or a fit sets', 0, async () => {
      const padding: Padding = { top: 0, left: 50, bottom: 0, right: 0 };
      await map.updateCamera({ padding: padding });
      expectPadding(camera().padding, padding);

      // A move or a fit without padding keeps it.
      await map.updateCamera({ zoom: 3 });
      expectPadding(camera().padding, padding);
      await map.fitCameraToCoordinates(SWISS_POINTS, { fitPadding: { top: 20, left: 20, bottom: 20, right: 20 } });
      expectPadding(camera().padding, padding);

      // The insets add to it on the map, and the camera keeps it apart.
      await setInsets({ top: 0, left: 0, bottom: 100, right: 0 }, padding);
      expectPadding(camera().padding, padding);

      // A fit keeps padding that a move sent just before it set, though the
      // move hasn't finished.
      const sent: Padding = { top: 0, left: 30, bottom: 0, right: 0 };
      const move = map.updateCamera({ padding: sent });
      await map.fitCameraToCoordinates(SWISS_POINTS);
      await move;
      expectPadding(camera().padding, sent);

      // A fit with camera padding sets it, and fits inside it.
      const after: Padding = { top: 40, left: 0, bottom: 0, right: 0 };
      await map.fitCameraToBounds(SWITZERLAND, { cameraPadding: after, bearing: 0, pitch: 0 });
      expectPadding(camera().padding, after);
      expect(pixelFor(SWITZERLAND.northeast).y).assertLarger(39);
      await until('the camera rests', () => near(vp(map.camera?.padding.top), 40, 0.01));
    });

    it('resolves a fit that a move makes before it finds its camera', 0, async () => {
      const fit = map.fitCameraToBounds(SWITZERLAND);
      const move = map.updateCamera({ zoom: 2 });
      expect(await fit).assertFalse();
      expect(await move).assertTrue();
      expectNear(camera().zoom, 2, 0.001);
    });

    it('rejects a fit without a map', 0, async () => {
      const unused = new MapController();
      await expect(unused.fitCameraToCoordinates(SWISS_POINTS, {})).assertPromiseIsRejected();
      await expect(unused.fitCameraToGeometry(SWISS_POLYGON, {})).assertPromiseIsRejected();
    });

    it('reports the map events that a runtime listener asks for, while it listens', 0, async () => {
      const runtime = requireRuntime();
      let handle = requireMap();
      // The library's own events don't include idle.
      expect(reports(handle, RuntimeEventFlag.mapIdle)).assertFalse();
      expect(reports(handle, RuntimeEventFlag.mapCameraDidChange)).assertTrue();
      let idles = 0;
      let unaskedIdles = 0;
      const listener = (event: RuntimeEvent) => {
        if (event.type === RuntimeEventType.mapIdle && event.source === map.map?.id) {
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
        await until('the map reports idle events', () => reports(handle, RuntimeEventFlag.mapIdle));
        await map.updateCamera({ zoom: 3 });
        await until('the map goes idle', () => idles > 0);

        // A map that appears while the listener listens reports them from the
        // start.
        testMap.shown = false;
        await until('the map leaves', () => map.map === undefined);
        testMap.shown = true;
        await until('the map comes back', () => map.styleLoaded);
        handle = requireMap();
        expect(reports(handle, RuntimeEventFlag.mapIdle)).assertTrue();
        const before = idles;
        await map.updateCamera({ zoom: 4 });
        await until('the new map goes idle', () => idles > before);
      } finally {
        removeRuntimeEventListener(runtime, listener);
      }
      await until('the map stops reporting idle events', () => !reports(handle, RuntimeEventFlag.mapIdle));
      expect(reports(handle, RuntimeEventFlag.mapCameraDidChange)).assertTrue();
      removeRuntimeEventListener(runtime, other);
      expect(unaskedIdles).assertEqual(0);
    });

    it('keeps the camera within the bounds the map is given', 0, async () => {
      testMap.cameraBounds = { maxZoom: 4 };
      await until('the bounds apply', () => map.map?.getSnapshot().bounds.maxZoom === 4);
      await map.updateCamera({ zoom: 10 });
      expectNear(camera().zoom, 4, 0.001);

      testMap.cameraBounds = undefined;
      await until('the bounds reset', () => (map.map?.getSnapshot().bounds.maxZoom ?? 0) > 4);
      await map.updateCamera({ zoom: 10 });
      expectNear(camera().zoom, 10, 0.001);
    });

    it('puts back the limits that FFI gives a new map when the app removes its own', 0, async () => {
      // A map's lowest zoom keeps the world as tall as the map, so the new
      // map takes the test map's size.
      const fresh = requireRuntime().createMap({
        initialExtent: requireMap().getSnapshot().view.extent,
        mapMode: MapMode.static,
      });
      await fresh.ready;
      const defaults = fresh.getSnapshot().bounds;
      await fresh.release();
      testMap.cameraBounds = { bounds: SWITZERLAND, minZoom: 2, maxZoom: 9, minPitch: 10, maxPitch: 30 };
      await until('the bounds apply', () => map.map?.getSnapshot().bounds.maxZoom === 9);
      testMap.cameraBounds = undefined;
      await until('the bounds reset', () => (map.map?.getSnapshot().bounds.maxZoom ?? 0) > 9);
      const bounds = requireMap().getSnapshot().bounds;
      expect(bounds.unbounded).assertEqual(defaults.unbounded);
      expectNear(bounds.minZoom, defaults.minZoom, 1e-9);
      expect(bounds.maxZoom).assertEqual(defaults.maxZoom);
      expectNear(bounds.minPitch, defaults.minPitch, 1e-9);
      expectNear(bounds.maxPitch, defaults.maxPitch, 1e-9);
    });

    it('starts a map that comes back where the last one left the camera', 0, async () => {
      await map.updateCamera({ center: { latitude: -33.86, longitude: 151.21 }, zoom: 7, bearing: 45 });
      testMap.shown = false;
      await until('the map leaves', () => map.map === undefined);
      expect(map.styleLoaded).assertFalse();
      await expect(map.updateCamera({ zoom: 1 })).assertPromiseIsRejected();

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
      const left = camera().zoom;
      expect(map.camera?.zoom).assertEqual(left);
      expect(left).assertLess(12);

      testMap.shown = true;
      await until('the map comes back', () => map.styleLoaded);
      expectNear(camera().zoom, left, 0.001);
    });

    it('loads the style it is given, as JSON or a URL', 0, async () => {
      await setStyle(backgroundStyle('#d94a4a'));
      expect(JSON.stringify(await requireMap().getLoadedStyleJson())).assertContain('#d94a4a');

      testMap.style = 'file:///nonexistent/style.json';
      await until('the map reports the error', () => testMap.errors.length > 0);
      expect(map.styleLoaded).assertFalse();
    });

    it('rejects camera changes without a map', 0, async () => {
      const unused = new MapController();
      expect(unused.getCamera()).assertUndefined();
      await expect(unused.updateCamera({ zoom: 1 })).assertPromiseIsRejected();
      // Its arguments are checked first.
      expect(() => unused.updateCamera({ zoom: NaN })).assertThrowError('NaN');
      expect(() => unused.fitCameraToCoordinates([])).assertThrowError('empty');
      await expect(unused.cancelCameraTransitions()).assertPromiseIsRejected();
    });
  });
}
