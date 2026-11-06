import { describe, expect, it } from '@ohos/hypium';
import {
  addRuntimeEventListener,
  CameraPosition,
  CameraTransitionOutcome,
  CameraUpdateMode,
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

import { STYLE, testMap } from '../testability/TestMaps';
import { until } from './until';

function camera(controller: MapController): CameraPosition {
  const current = controller.getCamera();
  if (current === undefined) {
    throw new Error('The controller has no camera');
  }
  return current;
}

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

function expectInSwitzerland(controller: MapController): void {
  const center = camera(controller).center;
  expect(center.latitude).assertLarger(SWITZERLAND.southwest.latitude);
  expect(center.latitude).assertLess(SWITZERLAND.northeast.latitude);
  expect(center.longitude).assertLarger(SWITZERLAND.southwest.longitude);
  expect(center.longitude).assertLess(SWITZERLAND.northeast.longitude);
}

function reports(map: MapHandle, flag: RuntimeEventFlag): boolean {
  return (map.getSnapshot().eventMask & flag) !== RuntimeEventFlag.none;
}

function requireMap(controller: MapController): MapHandle {
  const map = controller.map;
  if (map === undefined) {
    throw new Error('No map shows the controller');
  }
  return map;
}

function requireRuntime(controller: MapController): RuntimeHandle {
  const runtime = controller.runtime;
  if (runtime === undefined) {
    throw new Error('No map shows the controller');
  }
  return runtime;
}

export default function mapControllerTest(): void {
  describe('MapController', () => {
    const map = testMap.controller;

    it('shows the style and reports where the camera rests', 0, async () => {
      await until('the style loads', () => map.styleLoaded);
      expect(map.map !== undefined).assertTrue();
      expect(map.runtime !== undefined).assertTrue();
      await until('the camera rests', () => map.camera !== undefined);
      expect(map.camera?.zoom).assertClose(1, 0.001);
    });

    it('jumps the camera at once', 0, async () => {
      const outcome = await map.updateCamera({
        mode: CameraUpdateMode.jump,
        camera: { center: { latitude: 10, longitude: 20 }, zoom: 5 },
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
      expect(camera(map).zoom).assertClose(5, 0.001);
      expect(camera(map).center.latitude).assertClose(10, 0.001);
      expect(camera(map).center.longitude).assertClose(20, 0.001);
      await until('the observed camera follows', () => Math.abs((map.camera?.zoom ?? 0) - 5) < 0.001);
    });

    it('resolves an animation once it completes', 0, async () => {
      const outcome = await map.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { zoom: 6 },
        animation: { durationMs: 300 },
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
      expect(camera(map).zoom).assertClose(6, 0.001);
    });

    it('resolves an animation whose end handler throws', 0, async () => {
      let handled = false;
      const outcome = await map.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { zoom: 7 },
        animation: {
          durationMs: 100,
          endHandler: {
            callback: () => {
              handled = true;
              throw new Error('the app handler failed');
            },
          },
        },
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
      expect(handled).assertTrue();
    });

    it('resolves an animation that a later one replaces', 0, async () => {
      const first = map.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { zoom: 9 },
        animation: { durationMs: 5000 },
      });
      const second = map.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { zoom: 3 },
        animation: { durationMs: 200 },
      });
      expect(await first).assertEqual(CameraTransitionOutcome.replaced);
      expect(await second).assertEqual(CameraTransitionOutcome.completed);
      expect(camera(map).zoom).assertClose(3, 0.001);
    });

    it('cancels an animation where it is', 0, async () => {
      const animation = map.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { zoom: 12 },
        animation: { durationMs: 10000 },
      });
      await map.cancelCameraTransitions();
      expect(await animation).assertEqual(CameraTransitionOutcome.cancelled);
      expect(camera(map).zoom).assertLess(12);
    });

    it('fits bounds inside its padding', 0, async () => {
      const outcome = await map.fitCameraToLatLngBounds(SWITZERLAND, {
        mode: CameraUpdateMode.jump,
        fit: { padding: { top: 20, left: 20, bottom: 20, right: 20 }, bearing: 0, pitch: 0 },
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
      const center = camera(map).center;
      expect(center.latitude).assertLarger(SWITZERLAND.southwest.latitude);
      expect(center.latitude).assertLess(SWITZERLAND.northeast.latitude);
      expect(center.longitude).assertLarger(SWITZERLAND.southwest.longitude);
      expect(center.longitude).assertLess(SWITZERLAND.northeast.longitude);
    });

    it('fits coordinates inside its padding', 0, async () => {
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { center: { latitude: 0, longitude: 0 }, zoom: 1 } });
      const outcome = await map.fitCameraToLatLngs(SWISS_POINTS, {
        mode: CameraUpdateMode.jump,
        fit: { padding: { top: 20, left: 20, bottom: 20, right: 20 }, bearing: 0, pitch: 0 },
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
      expectInSwitzerland(map);
      expect(camera(map).zoom).assertLarger(4);
    });

    it('fits a geometry with an animation, which a later move can replace', 0, async () => {
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { center: { latitude: 0, longitude: 0 }, zoom: 1 } });
      const outcome = await map.fitCameraToGeometry(SWISS_POLYGON, {
        mode: CameraUpdateMode.ease,
        fit: { padding: { top: 20, left: 20, bottom: 20, right: 20 }, bearing: 0, pitch: 0 },
        animation: { durationMs: 300 },
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
      expectInSwitzerland(map);
      expect(camera(map).zoom).assertLarger(4);

      const fit = map.fitCameraToLatLngs([{ latitude: -33.86, longitude: 151.21 }], {
        mode: CameraUpdateMode.ease,
        animation: { durationMs: 10000 },
      });
      // It replaces the fit by setting every field that the fit animates,
      // which includes the padding that the first fit left.
      const move = map.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: {
          center: { latitude: 0, longitude: 0 },
          padding: { top: 0, left: 0, bottom: 0, right: 0 },
          zoom: 2,
          bearing: 0,
          pitch: 0,
        },
        animation: { durationMs: 200 },
      });
      expect(await fit).assertEqual(CameraTransitionOutcome.replaced);
      expect(await move).assertEqual(CameraTransitionOutcome.completed);
    });

    it('rejects a fit without a map', 0, async () => {
      const unused = new MapController();
      await expect(unused.fitCameraToLatLngs(SWISS_POINTS, {})).assertPromiseIsRejected();
      await expect(unused.fitCameraToGeometry(SWISS_POLYGON, {})).assertPromiseIsRejected();
    });

    it('reports the map events that a runtime listener asks for, while it listens', 0, async () => {
      await until('the style loads', () => map.styleLoaded);
      const runtime = requireRuntime(map);
      let handle = requireMap(map);
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
        await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 3 } });
        await until('the map goes idle', () => idles > 0);

        // A map that appears while the listener listens reports them from the
        // start.
        testMap.shown = false;
        await until('the map leaves', () => map.map === undefined);
        testMap.shown = true;
        await until('the map comes back', () => map.styleLoaded);
        handle = requireMap(map);
        expect(reports(handle, RuntimeEventFlag.mapIdle)).assertTrue();
        const before = idles;
        await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 4 } });
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
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 10 } });
      expect(camera(map).zoom).assertClose(4, 0.001);

      testMap.cameraBounds = undefined;
      await until('the bounds reset', () => (map.map?.getSnapshot().bounds.maxZoom ?? 0) > 4);
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 10 } });
      expect(camera(map).zoom).assertClose(10, 0.001);
    });

    it('starts a map that comes back where the last one left the camera', 0, async () => {
      await map.updateCamera({
        mode: CameraUpdateMode.jump,
        camera: { center: { latitude: -33.86, longitude: 151.21 }, zoom: 7, bearing: 45 },
      });
      testMap.shown = false;
      await until('the map leaves', () => map.map === undefined);
      expect(map.styleLoaded).assertFalse();
      await expect(map.updateCamera({ camera: { zoom: 1 } })).assertPromiseIsRejected();

      testMap.shown = true;
      await until('the map comes back', () => map.styleLoaded);
      expect(camera(map).center.latitude).assertClose(-33.86, 0.001);
      expect(camera(map).center.longitude).assertClose(151.21, 0.001);
      expect(camera(map).zoom).assertClose(7, 0.001);
      expect(camera(map).bearing).assertClose(45, 0.001);
    });

    it('rests where a map that leaves mid-animation left the camera', 0, async () => {
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 2 } });
      const animation = map.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { zoom: 12 },
        animation: { durationMs: 10000 },
      });
      await until('the camera moves', () => camera(map).zoom > 2.1);
      testMap.shown = false;
      expect(await animation).assertEqual(CameraTransitionOutcome.closed);
      const left = camera(map).zoom;
      expect(map.camera?.zoom).assertEqual(left);
      expect(left).assertLess(12);

      testMap.shown = true;
      await until('the map comes back', () => map.styleLoaded);
      expect(camera(map).zoom).assertClose(left, 0.001);
    });

    it('loads the style it is given, as JSON or a URL', 0, async () => {
      const loads = testMap.styleLoads;
      testMap.style = STYLE.replace('#4a90d9', '#d94a4a');
      await until('the new style loads', () => testMap.styleLoads > loads);
      expect(map.styleLoaded).assertTrue();
      expect(JSON.stringify(await map.map?.getLoadedStyleJson())).assertContain('#d94a4a');

      const errors = testMap.errors.length;
      testMap.style = 'file:///nonexistent/style.json';
      await until('the map reports the error', () => testMap.errors.length > errors);
      expect(map.styleLoaded).assertFalse();

      testMap.style = STYLE;
      await until('the style loads again', () => map.styleLoaded);
    });

    it('rejects camera changes without a map', 0, async () => {
      const unused = new MapController();
      expect(unused.getCamera()).assertUndefined();
      await expect(unused.updateCamera({ camera: { zoom: 1 } })).assertPromiseIsRejected();
      await expect(unused.cancelCameraTransitions()).assertPromiseIsRejected();
    });
  });
}
