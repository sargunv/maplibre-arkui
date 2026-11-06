import { beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  addRuntimeEventListener,
  CameraTransitionOutcome,
  CameraUpdateMode,
  EdgeInsets,
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

// Sets the test map's viewport insets, and waits until the map's padding is
// them around `cameraPadding`.
async function setInsets(insets: EdgeInsets, cameraPadding: EdgeInsets = NO_INSETS): Promise<void> {
  testMap.viewportInsets = insets;
  await until('the map takes the insets', () => {
    const padding = requireMap().getSnapshot().view.camera.padding;
    return near(padding.top, insets.top + cameraPadding.top, 0.01) &&
      near(padding.left, insets.left + cameraPadding.left, 0.01) &&
      near(padding.bottom, insets.bottom + cameraPadding.bottom, 0.01) &&
      near(padding.right, insets.right + cameraPadding.right, 0.01);
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

function expectPadding(actual: EdgeInsets, expected: EdgeInsets): void {
  expectNear(actual.top, expected.top, 0.01);
  expectNear(actual.left, expected.left, 0.01);
  expectNear(actual.bottom, expected.bottom, 0.01);
  expectNear(actual.right, expected.right, 0.01);
}

function expectNoPadding(actual: EdgeInsets): void {
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
      const outcome = await map.updateCamera({
        mode: CameraUpdateMode.jump,
        camera: { center: { latitude: 10, longitude: 20 }, zoom: 5 },
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
      expectNear(camera().zoom, 5, 0.001);
      expectNear(camera().center.latitude, 10, 0.001);
      expectNear(camera().center.longitude, 20, 0.001);
      await until('the observed camera follows', () => Math.abs((map.camera?.zoom ?? 0) - 5) < 0.001);
    });

    it('resolves an animation once it completes', 0, async () => {
      const outcome = await map.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { zoom: 6 },
        animation: { durationMs: 300 },
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
      expectNear(camera().zoom, 6, 0.001);
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
      expectNear(camera().zoom, 3, 0.001);
    });

    it('cancels an animation where it is', 0, async () => {
      const animation = map.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { zoom: 12 },
        animation: { durationMs: 10000 },
      });
      await map.cancelCameraTransitions();
      expect(await animation).assertEqual(CameraTransitionOutcome.cancelled);
      expect(camera().zoom).assertLess(12);
    });

    it('fits bounds inside its padding', 0, async () => {
      const outcome = await map.fitCameraToLatLngBounds(SWITZERLAND, {
        mode: CameraUpdateMode.jump,
        fitPadding: { top: 20, left: 20, bottom: 20, right: 20 },
        bearing: 0,
        pitch: 0,
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
      expectInSwitzerland();
    });

    it('fits coordinates inside its padding', 0, async () => {
      const outcome = await map.fitCameraToLatLngs(SWISS_POINTS, {
        mode: CameraUpdateMode.jump,
        fitPadding: { top: 20, left: 20, bottom: 20, right: 20 },
        bearing: 0,
        pitch: 0,
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
      expectInSwitzerland();
      expect(camera().zoom).assertLarger(4);
    });

    it('fits a geometry with an animation, which a later move can replace', 0, async () => {
      const outcome = await map.fitCameraToGeometry(SWISS_POLYGON, {
        mode: CameraUpdateMode.ease,
        fitPadding: { top: 20, left: 20, bottom: 20, right: 20 },
        bearing: 0,
        pitch: 0,
        animation: { durationMs: 300 },
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
      expectInSwitzerland();
      expect(camera().zoom).assertLarger(4);

      const fit = map.fitCameraToLatLngs([{ latitude: -33.86, longitude: 151.21 }], {
        mode: CameraUpdateMode.ease,
        animation: { durationMs: 10000 },
      });
      const move = map.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { center: { latitude: 0, longitude: 0 }, zoom: 2, bearing: 0, pitch: 0 },
        animation: { durationMs: 200 },
      });
      expect(await fit).assertEqual(CameraTransitionOutcome.replaced);
      expect(await move).assertEqual(CameraTransitionOutcome.completed);
    });

    it('centers a move inside the viewport insets, which the camera leaves out', 0, async () => {
      await setInsets({ top: 0, left: 0, bottom: 200, right: 0 });
      const target: LatLng = { latitude: 10, longitude: 20 };
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { center: target, zoom: 5 } });

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
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { center: target, zoom: 5 } });
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
      const padding: EdgeInsets = { top: 0, left: 30, bottom: 0, right: 0 };
      const move = map.updateCamera({ mode: CameraUpdateMode.jump, camera: { padding: padding } });
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
      const padding: EdgeInsets = { top: 0, left: 30, bottom: 0, right: 0 };
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { padding: padding } });
      padding.left = 90;
      testMap.viewportInsets = { top: 0, left: 0, bottom: 100, right: 0 };
      await until('the map takes the insets', () => near(requireMap().getSnapshot().view.camera.padding.bottom, 100, 0.01));
      expectNear(camera().padding.left, 30, 0.01);
    });

    it('keeps the camera padding when the map rejects moves', 0, async () => {
      const padding: EdgeInsets = { top: 0, left: 30, bottom: 0, right: 0 };
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { padding: padding } });
      // Two in a row, one for its padding and one for its zoom.
      const negative = map.updateCamera({
        mode: CameraUpdateMode.jump,
        camera: { padding: { top: 0, left: -10, bottom: 0, right: 0 } },
      });
      const notANumber = map.updateCamera({
        mode: CameraUpdateMode.jump,
        camera: { padding: { top: 0, left: 60, bottom: 0, right: 0 }, zoom: NaN },
      });
      await expect(negative).assertPromiseIsRejected();
      await expect(notANumber).assertPromiseIsRejected();
      testMap.viewportInsets = { top: 0, left: 0, bottom: 100, right: 0 };
      await until('the map takes the insets', () => near(requireMap().getSnapshot().view.camera.padding.bottom, 100, 0.01));
      expectPadding(camera().padding, padding);
    });

    it('rejects negative camera padding that the viewport insets would cover', 0, async () => {
      await setInsets({ top: 0, left: 20, bottom: 0, right: 0 });
      await expect(map.updateCamera({
        mode: CameraUpdateMode.jump,
        camera: { padding: { top: 0, left: -10, bottom: 0, right: 0 } },
      })).assertPromiseIsRejected();
      expectNoPadding(camera().padding);
    });

    it('fits inside the viewport insets and its margin, and keeps neither in the camera', 0, async () => {
      await setInsets({ top: 0, left: 0, bottom: 100, right: 0 });
      const outcome = await map.fitCameraToLatLngBounds(SWITZERLAND, {
        fitPadding: { top: 30, left: 30, bottom: 30, right: 30 },
        bearing: 0,
        pitch: 0,
      });
      expect(outcome).assertEqual(CameraTransitionOutcome.completed);
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
      const padding: EdgeInsets = { top: 0, left: 50, bottom: 0, right: 0 };
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { padding: padding } });
      expectPadding(camera().padding, padding);

      // A move or a fit without padding keeps it.
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 3 } });
      expectPadding(camera().padding, padding);
      await map.fitCameraToLatLngs(SWISS_POINTS, { fitPadding: { top: 20, left: 20, bottom: 20, right: 20 } });
      expectPadding(camera().padding, padding);

      // The insets add to it on the map, and the camera keeps it apart.
      await setInsets({ top: 0, left: 0, bottom: 100, right: 0 }, padding);
      expectPadding(camera().padding, padding);

      // A fit keeps padding that a move sent just before it set, though the
      // move hasn't finished.
      const sent: EdgeInsets = { top: 0, left: 30, bottom: 0, right: 0 };
      const move = map.updateCamera({ mode: CameraUpdateMode.jump, camera: { padding: sent } });
      await map.fitCameraToLatLngs(SWISS_POINTS);
      await move;
      expectPadding(camera().padding, sent);

      // A fit with camera padding sets it, and fits inside it.
      const after: EdgeInsets = { top: 40, left: 0, bottom: 0, right: 0 };
      await map.fitCameraToLatLngBounds(SWITZERLAND, { cameraPadding: after, bearing: 0, pitch: 0 });
      expectPadding(camera().padding, after);
      expect(pixelFor(SWITZERLAND.northeast).y).assertLarger(39);
      await until('the camera rests', () => near(map.camera?.padding.top ?? 0, 40, 0.01));
    });

    it('resolves a fit that a move makes before it finds its camera', 0, async () => {
      const fit = map.fitCameraToLatLngBounds(SWITZERLAND);
      const move = map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 2 } });
      expect(await fit).assertEqual(CameraTransitionOutcome.replaced);
      expect(await move).assertEqual(CameraTransitionOutcome.completed);
      expectNear(camera().zoom, 2, 0.001);
    });

    it('rejects a fit without a map', 0, async () => {
      const unused = new MapController();
      await expect(unused.fitCameraToLatLngs(SWISS_POINTS, {})).assertPromiseIsRejected();
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
        await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 3 } });
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
      expectNear(camera().zoom, 4, 0.001);

      testMap.cameraBounds = undefined;
      await until('the bounds reset', () => (map.map?.getSnapshot().bounds.maxZoom ?? 0) > 4);
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 10 } });
      expectNear(camera().zoom, 10, 0.001);
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
      expectNear(camera().center.latitude, -33.86, 0.001);
      expectNear(camera().center.longitude, 151.21, 0.001);
      expectNear(camera().zoom, 7, 0.001);
      expectNear(camera().bearing, 45, 0.001);
    });

    it('rests where a map that leaves mid-animation left the camera', 0, async () => {
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 2 } });
      const animation = map.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { zoom: 12 },
        animation: { durationMs: 10000 },
      });
      await until('the camera moves', () => camera().zoom > 2.1);
      testMap.shown = false;
      expect(await animation).assertEqual(CameraTransitionOutcome.closed);
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
      await expect(unused.updateCamera({ camera: { zoom: 1 } })).assertPromiseIsRejected();
      await expect(unused.cancelCameraTransitions()).assertPromiseIsRejected();
    });
  });
}
