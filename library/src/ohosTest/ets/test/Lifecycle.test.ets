// A map's life on the page: before its FFI map is ready, beside another map,
// after it leaves, as it resizes, at a new density, on a runtime of its own,
// and the events and errors it reports.

import { beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  CameraPosition,
  CameraTransitionMode,
  ContentError,
  MapResourceLoadRequest,
  MapResourceResponse,
  MapRuntime,
  StyleLayer,
  StyleLoadError,
  Viewport,
} from '@maplibre/arkui';
import { CameraUpdateMode, MapHandle, MapSnapshot } from '@maplibre/native-ffi';

import util from '@ohos.util';

import { backgroundStyle, backgroundStyleJson, showsMap, STYLE, testMap } from '../testability/TestMaps';
import {
  camera,
  eventually,
  expectNear,
  frames,
  mapId,
  mapSnapshot,
  near,
  setStyle,
  until,
  vp2px,
  withMap,
} from './helpers';

const map = testMap.controller;

async function hideMap(): Promise<void> {
  testMap.shown = false;
  await until('the map leaves', () => !showsMap(map));
}

async function showMap(): Promise<void> {
  testMap.shown = true;
  await until('the map shows the style', () => map.styleLoaded);
}

// Whether the camera of the map that `snapshot` reads rests at `zoom`.
function restsAtZoom(snapshot: MapSnapshot, zoom: number): boolean {
  return !snapshot.transitionInProgress && near(snapshot.view.camera.zoom, zoom, 0.001);
}

export default function lifecycleTest(): void {
  describe('Lifecycle', () => {
    beforeEach(async () => {
      await testMap.reset();
    });

    it('reports to onCameraIdle where the camera comes to rest', 0, async () => {
      let idles = testMap.cameraIdles.length;
      await map.updateCamera({ zoom: 3 });
      await until('the map reports the jump', () => testMap.cameraIdles.length > idles);
      const jumped: CameraPosition = testMap.cameraIdles[testMap.cameraIdles.length - 1];
      expectNear(jumped.zoom, 3, 0.001);

      // An animation reports only where it ends.
      idles = testMap.cameraIdles.length;
      await map.updateCamera({ zoom: 5 }, { mode: CameraTransitionMode.EASE, durationMs: 300 });
      await until('the map reports the animation', () => testMap.cameraIdles.length > idles);
      await frames(10);
      const reported = testMap.cameraIdles.slice(idles);
      expect(reported.every((rest: CameraPosition) => near(rest.zoom, 5, 0.001))).assertTrue();
    });

    it('holds a camera move until the map shows a frame, after the camera where the last map left it', 0,
      async () => {
        await map.updateCamera({ zoom: 4 });
        await hideMap();
        testMap.shown = true;
        // The component is coming, but its FFI map isn't ready.
        const move = map.updateCamera({ zoom: 8 });
        expectNear(map.camera.zoom, 4, 0.001);
        expect(map.viewport).assertUndefined();

        expect(await move).assertTrue();
        expect(map.viewport !== undefined).assertTrue();
        expectNear(camera().zoom, 8, 0.001);
        await until('the camera rests', () => near(map.camera.zoom, 8, 0.001));
        expect(testMap.cameraIdles.some((rest: CameraPosition) => near(rest.zoom, 4, 0.001))).assertTrue();
      });

    it('shows one map at a time: the one that appeared last, until it leaves', 0, async () => {
      const first = mapId();
      // The case keeps the first FFI map past the lend, which apps mustn't, to
      // move it behind the controller's back while it still shows.
      const firstMap = withMap((ffi: MapHandle) => ffi);
      testMap.secondMap = true;
      await until('the second map shows the controller', () =>
        mapId() !== undefined && mapId() !== first && map.styleLoaded);
      const second = mapId();

      // The camera methods move the second map, and the first map's camera no
      // longer reaches the controller.
      await map.updateCamera({ zoom: 4 });
      expect(restsAtZoom(mapSnapshot(), 4)).assertTrue();
      expect(restsAtZoom(firstMap.getSnapshot(), 1)).assertTrue();
      await until('the controller rests at the second map\'s camera', () => near(map.camera.zoom, 4, 0.001));
      await firstMap.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 2 } });
      await frames(10);
      expectNear(map.camera.zoom, 4, 0.001);
      expectNear(map.viewport?.camera.zoom ?? NaN, 4, 0.001);

      // The first map leaving leaves the controller with the second.
      testMap.firstMap = false;
      await frames(10);
      expect(mapId() === second).assertTrue();
      expect(map.styleLoaded).assertTrue();

      testMap.secondMap = false;
      await until('the second map leaves', () => !showsMap(map));
      expect(map.styleLoaded).assertFalse();
      expectNear(map.camera.zoom, 4, 0.001);
    });

    it('forgets the viewport once the map leaves, and an old viewport still answers for its frame', 0,
      async () => {
        await until('the map shows a frame', () => map.viewport !== undefined);
        const old: Viewport = map.viewport!;
        const origin = old.project({ latitude: 0, longitude: 0 });

        await hideMap();
        // Frames that the session reports as it goes don't bring it back.
        await frames(10);
        expect(map.viewport).assertUndefined();
        const again = old.project({ latitude: 0, longitude: 0 });
        expectNear(again.x, origin.x, 1e-6);
        expectNear(again.y, origin.y, 1e-6);
        expectNear(old.unproject(origin).longitude, 0, 1e-6);

        await showMap();
        await until('the new map shows a frame', () => map.viewport !== undefined);
      });

    it('follows its surface as it resizes', 0, async () => {
      await until('the map shows a frame', () => map.viewport !== undefined);
      const full = mapSnapshot().view.extent;
      testMap.height = 200;
      await until('the map takes the new size', () => mapSnapshot().view.extent.height === 200);
      expect(mapSnapshot().view.extent.width).assertEqual(full.width);
      // The frames on screen are of the new size, with the camera's center in
      // the middle of it.
      await until('a frame of the new size shows', () => near(map.viewport?.project(camera().center).y ?? 0, 100, 0.5));
      expectNear(map.viewport?.project(camera().center).x ?? NaN, full.width / 2, 0.5);
      expect(map.viewport?.size.height).assertEqual(200);

      testMap.height = '100%';
      await until('the map takes its full size back', () =>
        mapSnapshot().view.extent.height === full.height);
      await until('a frame of the full size shows', () =>
        near(map.viewport?.project(camera().center).y ?? 0, full.height / 2, 0.5));
    });

    it('makes a new map at a new density, which keeps the camera and the content', 0, async () => {
      const stage = testMap.windowStage;
      if (stage === undefined) {
        throw new Error('The test ability has no window stage');
      }
      const dots: StyleLayer = { id: 'dots', type: 'background' };
      testMap.content = { layers: [dots] };
      await eventually('the content applies', () => withMap((ffi: MapHandle) => ffi.getStyleLayer('dots')));
      await map.updateCamera({ center: { latitude: 10, longitude: 20 }, zoom: 4 });
      const density = vp2px(1);
      // A custom density is at most 4.
      const changed = density > 2 ? density - 1 : density + 1;
      const old = mapId();
      stage.setCustomDensity(changed);
      try {
        await until('a new map shows the style', () => mapId() !== undefined && mapId() !== old && map.styleLoaded);
        expectNear(vp2px(1), changed, 0.001);
        const view = mapSnapshot().view;
        expectNear(view.extent.scaleFactor, changed, 0.001);
        expectNear(view.camera.center.latitude, 10, 0.001);
        expectNear(view.camera.center.longitude, 20, 0.001);
        expectNear(view.camera.zoom, 4, 0.001);
        await eventually('the content applies again', () => withMap((ffi: MapHandle) => ffi.getStyleLayer('dots')));
        await until('the new map shows a frame', () => map.viewport !== undefined);
      } finally {
        stage.setCustomDensity(density);
        await until('the map takes the density back', () => showsMap(map) && map.styleLoaded &&
          near(mapSnapshot().view.extent.scaleFactor, density, 0.001));
      }
    });

    it('creates the map on the runtime it is given, and reports the runtime\'s release', 0, async () => {
      // Only this runtime serves the style, in red.
      const runtime = new MapRuntime({
        resourceProvider: {
          urlPatterns: ['app://styles/red.json'],
          load: async (request: MapResourceLoadRequest): Promise<MapResourceResponse | undefined> => {
            const response: MapResourceResponse = {
              data: new util.TextEncoder().encodeInto(backgroundStyleJson('#ff0000')),
            };
            return response;
          },
        },
      });
      await hideMap();
      testMap.runtime = runtime;
      testMap.style = 'app://styles/red.json';
      await showMap();
      expect(testMap.errors.length).assertEqual(0);

      await runtime.release();
      expect(showsMap(map)).assertFalse();
      expect(testMap.errors.indexOf('The map\'s runtime was released')).assertLarger(-1);
      // The map shows nothing from now on, so the page drops it before the
      // next case shows a map on the default runtime.
      testMap.shown = false;
      await frames(2);
    });

    it('reports a style that fails to load, and loads the next style', 0, async () => {
      testMap.style = 'file:///nonexistent/style.json';
      await until('the map reports the error', () => testMap.failures.length > 0);
      expect(testMap.failures[0] instanceof StyleLoadError).assertTrue();
      expect(map.styleLoaded).assertFalse();
      await setStyle(backgroundStyle('#d94a4a'));
      expect(JSON.stringify(await withMap((ffi: MapHandle) => ffi.getLoadedStyleJson()))).assertContain('#d94a4a');
    });

    it('keeps working after onError throws', 0, async () => {
      testMap.throwOnError = true;
      testMap.style = 'file:///nonexistent/style.json';
      await until('the map reports the URL', () => testMap.errors.length > 0);
      await setStyle(STYLE);

      const lost: StyleLayer = { id: 'lost', type: 'circle', source: 'missing' };
      const dots: StyleLayer = { id: 'dots', type: 'background' };
      testMap.content = { layers: [lost, dots] };
      await until('the map reports the layer', () =>
        testMap.errors.some((error: string) => error.includes('adding layer lost')));
      const failure = testMap.failures.find((error: Error) => error.message.includes('adding layer lost'));
      expect(failure instanceof ContentError && failure.id === 'lost').assertTrue();
      await eventually('the rest of the content applies', () => withMap((ffi: MapHandle) => ffi.getStyleLayer('dots')));
    });

    it('calls onStyleLoaded after onCameraIdle throws', 0, async () => {
      testMap.throwOnCameraIdle = true;
      const idles = testMap.cameraIdles.length;
      await map.updateCamera({ zoom: 3 });
      await until('the map reports the rest', () => testMap.cameraIdles.length > idles);
      await setStyle(backgroundStyle('#d94a4a'));
      expect(map.styleLoaded).assertTrue();
    });
  });
}
