import { describe, expect, it } from '@ohos/hypium';
import {
  CameraPosition,
  CameraTransitionOutcome,
  CameraUpdateMode,
  LatLngBounds,
  MapController,
} from '@maplibre/arkui';

import { FrameCallback } from '@ohos.arkui.UIContext';

import { STYLE, testMap } from '../testability/TestMaps';

class Poll extends FrameCallback {
  private readonly check: () => void;

  constructor(check: () => void) {
    super();
    this.check = check;
  }

  onFrame(frameTimeInNano: number): void {
    this.check();
  }
}

// Waits for `condition`, checking it each frame, and fails after `timeoutMs`.
// It doesn't poll with timers: OpenHarmony's main thread can lose a timer's
// wakeup while nothing else wakes its event loop.
function until(what: string, condition: () => boolean, timeoutMs: number = 15000): Promise<void> {
  const context = testMap.context;
  if (context === undefined) {
    return Promise.reject(new Error('The test page has not appeared'));
  }
  const start = Date.now();
  return new Promise<void>((resolve, reject) => {
    const check = (): void => {
      if (condition()) {
        resolve();
      } else if (Date.now() - start > timeoutMs) {
        reject(new Error(`Timed out waiting until ${what}`));
      } else {
        context.postFrameCallback(new Poll(check));
      }
    };
    check();
  });
}

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
