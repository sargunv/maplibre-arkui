// A map's life on the page: before its FFI map is ready, beside another map,
// after it leaves, as it resizes, on a runtime of its own, and the events and
// errors it reports.

import { beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  addRuntimeEventListener,
  CameraPosition,
  CameraUpdateMode,
  getDefaultRuntime,
  MapHandle,
  MapLayer,
  removeRuntimeEventListener,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeEventType,
  RuntimeHandle,
} from '@maplibre/arkui';

import { backgroundStyle, STYLE, testMap } from '../testability/TestMaps';
import { camera, eventually, expectNear, frames, near, requireMap, setStyle, until } from './helpers';

const map = testMap.controller;

// A runtime for the map to take instead of the default one. Its cache is in
// memory. It stays for the suite's life: FFI releases a runtime only after its
// maps, and the map releases its FFI map some time after it leaves.
let ownRuntime: RuntimeHandle | undefined = undefined;

async function getOwnRuntime(): Promise<RuntimeHandle> {
  if (ownRuntime === undefined) {
    ownRuntime = await RuntimeHandle.create({});
  }
  return ownRuntime;
}

async function hideMap(): Promise<void> {
  testMap.shown = false;
  await until('the map leaves', () => map.map === undefined);
}

async function showMap(): Promise<void> {
  testMap.shown = true;
  await until('the map shows the style', () => map.styleLoaded);
}

// Whether the camera of `handle` rests at `zoom`.
function restsAtZoom(handle: MapHandle, zoom: number): boolean {
  const snapshot = handle.getSnapshot();
  return !snapshot.transitionInProgress && near(snapshot.view.camera.zoom, zoom, 0.001);
}

export default function lifecycleTest(): void {
  describe('Lifecycle', () => {
    beforeEach(async () => {
      await testMap.reset();
    });

    it('reports to onCameraIdle where the camera comes to rest', 0, async () => {
      let idles = testMap.cameraIdles.length;
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 3 } });
      await until('the map reports the jump', () => testMap.cameraIdles.length > idles);
      const jumped: CameraPosition = testMap.cameraIdles[testMap.cameraIdles.length - 1];
      expectNear(jumped.zoom, 3, 0.001);
      expectNear(map.camera?.zoom ?? NaN, 3, 0.001);

      // An animation reports only where it ends.
      idles = testMap.cameraIdles.length;
      await map.updateCamera({ mode: CameraUpdateMode.ease, camera: { zoom: 5 }, animation: { durationMs: 300 } });
      await until('the map reports the animation', () => testMap.cameraIdles.length > idles);
      await frames(10);
      const reported = testMap.cameraIdles.slice(idles);
      expect(reported.every((rest: CameraPosition) => near(rest.zoom, 5, 0.001))).assertTrue();
    });

    it('rejects camera changes until the FFI map is ready, and then starts where the last map left', 0,
      async () => {
        await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 4 } });
        await hideMap();
        testMap.shown = true;
        // The component is coming, but its FFI map isn't ready.
        await expect(map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 8 } }))
          .assertPromiseIsRejected();
        expectNear(map.getCamera()?.zoom ?? NaN, 4, 0.001);
        expect(map.frameCamera).assertUndefined();

        await until('the map shows the style', () => map.styleLoaded);
        expectNear(camera().zoom, 4, 0.001);
        await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 8 } });
        expectNear(camera().zoom, 8, 0.001);
      });

    it('shows one map at a time: the one that appeared last, until it leaves', 0, async () => {
      const first = requireMap();
      testMap.secondMap = true;
      await until('the second map shows the controller', () =>
        map.map !== undefined && map.map !== first && map.styleLoaded);
      const second = requireMap();

      // The camera methods move the second map, and the first map's camera no
      // longer reaches the controller.
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 4 } });
      expect(restsAtZoom(second, 4)).assertTrue();
      expect(restsAtZoom(first, 1)).assertTrue();
      await until('the controller rests at the second map\'s camera', () => near(map.camera?.zoom ?? 0, 4, 0.001));
      await first.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 2 } });
      await frames(10);
      expectNear(map.camera?.zoom ?? NaN, 4, 0.001);
      expectNear(map.frameCamera?.zoom ?? NaN, 4, 0.001);

      // The first map leaving leaves the controller with the second.
      testMap.firstMap = false;
      await frames(10);
      expect(map.map === second).assertTrue();
      expect(map.styleLoaded).assertTrue();

      testMap.secondMap = false;
      await until('the second map leaves', () => map.map === undefined);
      expect(map.styleLoaded).assertFalse();
      expectNear(map.camera?.zoom ?? NaN, 4, 0.001);
    });

    it('forgets the frame and its projection once the map leaves', 0, async () => {
      await until('the map shows a frame', () => map.frameCamera !== undefined);
      expect(map.pixelForLatLng({ latitude: 0, longitude: 0 }) !== undefined).assertTrue();

      await hideMap();
      // Frames that the session reports as it goes don't bring it back.
      await frames(10);
      expect(map.frameCamera).assertUndefined();
      expect(map.pixelForLatLng({ latitude: 0, longitude: 0 })).assertUndefined();
      expect(map.latLngForPixel({ x: 0, y: 0 })).assertUndefined();
      expect(map.metersPerPixelAtLatitude(0)).assertUndefined();

      await showMap();
      await until('the new map shows a frame', () => map.frameCamera !== undefined);
    });

    it('follows its surface as it resizes', 0, async () => {
      await until('the map shows a frame', () => map.frameCamera !== undefined);
      const full = requireMap().getSnapshot().view.extent;
      testMap.height = 200;
      await until('the map takes the new size', () => requireMap().getSnapshot().view.extent.height === 200);
      expect(requireMap().getSnapshot().view.extent.width).assertEqual(full.width);
      // The frames on screen are of the new size, with the camera's center in
      // the middle of it.
      await until('a frame of the new size shows', () => near(map.pixelForLatLng(camera().center)?.y ?? 0, 100, 0.5));
      expectNear(map.pixelForLatLng(camera().center)?.x ?? NaN, full.width / 2, 0.5);

      testMap.height = '100%';
      await until('the map takes its full size back', () =>
        requireMap().getSnapshot().view.extent.height === full.height);
      await until('a frame of the full size shows', () =>
        near(map.pixelForLatLng(camera().center)?.y ?? 0, full.height / 2, 0.5));
    });

    it('creates the map on the runtime it is given', 0, async () => {
      const runtime = await getOwnRuntime();
      await hideMap();
      testMap.runtime = runtime;
      await showMap();
      expect(map.runtime?.id).assertEqual(runtime.id);
      expect(map.runtime?.id === (await getDefaultRuntime()).id).assertFalse();

      // Its map reports to that runtime's listeners.
      let idles = 0;
      const listener = (event: RuntimeEvent) => {
        if (event.type === RuntimeEventType.mapIdle && event.source === map.map?.id) {
          idles++;
        }
      };
      addRuntimeEventListener(runtime, listener, RuntimeEventFlag.mapIdle);
      try {
        await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 3 } });
        await until('the map goes idle', () => idles > 0);
      } finally {
        removeRuntimeEventListener(runtime, listener);
      }
    });

    it('calls the other runtime listeners when one throws or removes itself', 0, async () => {
      const runtime = await getDefaultRuntime();
      let thrown = 0;
      let once = 0;
      let counted = 0;
      const idle = (event: RuntimeEvent): boolean =>
        event.type === RuntimeEventType.mapIdle && event.source === map.map?.id;
      const throwing = (event: RuntimeEvent) => {
        if (idle(event)) {
          thrown++;
          throw new Error('the listener failed');
        }
      };
      const removing = (event: RuntimeEvent) => {
        if (idle(event)) {
          once++;
          removeRuntimeEventListener(runtime, removing);
        }
      };
      const counting = (event: RuntimeEvent) => {
        if (idle(event)) {
          counted++;
        }
      };
      addRuntimeEventListener(runtime, throwing, RuntimeEventFlag.mapIdle);
      addRuntimeEventListener(runtime, removing, RuntimeEventFlag.mapIdle);
      addRuntimeEventListener(runtime, counting, RuntimeEventFlag.mapIdle);
      try {
        await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 3 } });
        await until('the listeners after them hear the event', () => counted > 0);
        expect(once).assertEqual(1);
        const before = counted;
        await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 4 } });
        await until('the map goes idle again', () => counted > before);
        expect(once).assertEqual(1);
        expect(thrown).assertLarger(1);
      } finally {
        removeRuntimeEventListener(runtime, throwing);
        removeRuntimeEventListener(runtime, removing);
        removeRuntimeEventListener(runtime, counting);
      }
    });

    it('reports a style document that is not JSON, and loads the next style', 0, async () => {
      testMap.style = '{"version": 8, "sources": ';
      await until('the map reports the error', () => testMap.errors.length > 0);
      expect(map.styleLoaded).assertFalse();
      await setStyle(backgroundStyle('#d94a4a'));
      expect(JSON.stringify(await requireMap().getLoadedStyleJson())).assertContain('#d94a4a');
    });

    it('keeps working after onMapError throws', 0, async () => {
      testMap.throwOnError = true;
      testMap.style = '{"version": 8, "sources": ';
      await until('the map reports the document', () => testMap.errors.length > 0);
      testMap.style = 'file:///nonexistent/style.json';
      await until('the map reports the URL', () => testMap.errors.length > 1);
      await setStyle(STYLE);

      const lost: MapLayer = { id: 'lost', type: 'circle', source: 'missing' };
      const dots: MapLayer = { id: 'dots', type: 'background' };
      testMap.content = { layers: [lost, dots] };
      await until('the map reports the layer', () =>
        testMap.errors.some((error: string) => error.includes('adding layer lost')));
      await eventually('the rest of the content applies', () => requireMap().getStyleLayer('dots'));
    });
  });
}
