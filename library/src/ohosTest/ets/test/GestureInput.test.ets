// Real input on the test page's map, injected through the system with
// UiTest's Driver, and read back from the camera.

import { describe, expect, it } from '@ohos/hypium';
import { CameraPosition, CameraUpdateMode, MapController } from '@maplibre/arkui';

import { Driver, ON, Point, PointerMatrix, Rect as Bounds } from '@ohos.UiTest';
import { KeyCode } from '@ohos.multimodalInput.keyCode';

import { testMap } from '../testability/TestMaps';
import { until } from './until';

const ZOOM = 3;

function camera(): CameraPosition {
  const current = testMap.controller.getCamera();
  if (current === undefined) {
    throw new Error('The controller has no camera');
  }
  return current;
}

function vp2px(vp: number): number {
  return testMap.context?.vp2px(vp) ?? vp;
}

// Degrees of longitude at the equator that one vp of the map spans.
function degreesPerVp(zoom: number): number {
  return 360 / (512 * Math.pow(2, zoom));
}

// The map's bounds on the display, in px.
async function mapBounds(): Promise<Bounds> {
  const map = await Driver.create().findComponent(ON.type('XComponent'));
  return map.getBounds();
}

function center(bounds: Bounds): Point {
  return { x: Math.round((bounds.left + bounds.right) / 2), y: Math.round((bounds.top + bounds.bottom) / 2) };
}

// Shows the map alone or in a Scroll, puts the camera at a known place, and
// waits until the map shows the style.
async function reset(inScroll: boolean = false): Promise<void> {
  if (testMap.inScroll !== inScroll) {
    const loads = testMap.styleLoads;
    testMap.inScroll = inScroll;
    await until('the map moves', () => testMap.styleLoads > loads);
  }
  testMap.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  const map: MapController = testMap.controller;
  await until('the style loads', () => map.styleLoaded);
  await map.updateCamera({
    mode: CameraUpdateMode.jump,
    camera: { center: { latitude: 0, longitude: 0 }, zoom: ZOOM, bearing: 0, pitch: 0 },
  });
}

// Waits until the input that `act` makes has moved the camera and stopped,
// with its momentum and any animation.
async function gesture(act: () => Promise<void>): Promise<void> {
  const starts = testMap.gestureStarts;
  await act();
  await until('a gesture starts', () => testMap.gestureStarts > starts);
  await until('the camera rests', () => {
    const snapshot = testMap.controller.map?.getSnapshot();
    return testMap.gestureEnds === testMap.gestureStarts && snapshot !== undefined &&
      !snapshot.transitionInProgress && !snapshot.gestureInProgress;
  });
}

// Two fingers that move from `from` to `to` together, in px.
function twoFingers(from: Point[], to: Point[], steps: number): PointerMatrix {
  const pointers = PointerMatrix.create(2, steps);
  for (let step = 0; step < steps; step++) {
    const t = steps === 1 ? 0 : step / (steps - 1);
    for (let finger = 0; finger < 2; finger++) {
      pointers.setPoint(finger, step, {
        x: Math.round(from[finger].x + (to[finger].x - from[finger].x) * t),
        y: Math.round(from[finger].y + (to[finger].y - from[finger].y) * t),
      });
    }
  }
  return pointers;
}

// Two fingers on a circle about `c`, `degrees` around it, in px. Then they
// stay at that angle for `hold` steps, which take time only if the fingers
// move, so they move 1 px in and out.
function twist(c: Point, radius: number, degrees: number, steps: number, hold: number = 0): PointerMatrix {
  const pointers = PointerMatrix.create(2, steps + hold);
  for (let step = 0; step < steps + hold; step++) {
    const r = degrees * Math.min(1, step / (steps - 1)) * Math.PI / 180;
    const length = radius + (step >= steps ? (step - steps) % 2 : 0);
    const dx = Math.round(length * Math.cos(r));
    const dy = Math.round(length * Math.sin(r));
    pointers.setPoint(0, step, { x: c.x - dx, y: c.y - dy });
    pointers.setPoint(1, step, { x: c.x + dx, y: c.y + dy });
  }
  return pointers;
}

function wrap(degrees: number): number {
  return (((degrees + 180) % 360) + 360) % 360 - 180;
}

// hypium's assertClose compares the difference to the actual value, not to a
// tolerance.
function near(actual: number, expected: number, tolerance: number): void {
  expect(Math.abs(actual - expected)).assertLessOrEqual(tolerance);
}

export default function gestureInputTest(): void {
  describe('GestureInput', () => {
    const driver = Driver.create();

    it('pans with a slow drag, without momentum', 0, async () => {
      await reset();
      const c = center(await mapBounds());
      // 200 px/s, under the speed that flings.
      await gesture(() => driver.swipe(c.x + vp2px(100), c.y, c.x - vp2px(100), c.y, vp2px(200)));
      // The drag less the claim's few vp moves the center east.
      const moved = camera().center.longitude / degreesPerVp(ZOOM);
      expect(moved).assertLarger(170);
      expect(moved).assertLessOrEqual(200);
      near(camera().center.latitude, 0, 0.5);
      // The observable camera rests there too.
      await until('the controller\'s camera rests', () =>
        testMap.controller.camera?.center.longitude === camera().center.longitude);
    });

    it('keeps one gesture when the app moves the camera as it starts', 0, async () => {
      await reset();
      const c = center(await mapBounds());
      const starts = testMap.gestureStarts;
      const ends = testMap.gestureEnds;
      // As an app that stops following a location does.
      testMap.onGestureStart = () => {
        testMap.controller.cancelCameraTransitions();
      };
      try {
        await gesture(() => driver.swipe(c.x + vp2px(100), c.y, c.x - vp2px(100), c.y, vp2px(200)));
      } finally {
        testMap.onGestureStart = () => {
        };
      }
      expect(testMap.gestureStarts - starts).assertEqual(1);
      expect(testMap.gestureEnds - ends).assertEqual(1);
      expect(camera().center.longitude / degreesPerVp(ZOOM)).assertLarger(170);
    });

    it('coasts past the end of a fast drag', 0, async () => {
      await reset();
      const c = center(await mapBounds());
      await gesture(() => driver.fling({ x: c.x + vp2px(100), y: c.y }, { x: c.x - vp2px(100), y: c.y },
        vp2px(20), vp2px(2000)));
      // Without momentum, the camera would move less than the 200 vp drag.
      expect(camera().center.longitude / degreesPerVp(ZOOM)).assertLarger(220);
    });

    it('zooms with a pinch, without rotating', 0, async () => {
      await reset();
      const c = center(await mapBounds());
      const from: Point[] = [{ x: c.x - vp2px(50), y: c.y }, { x: c.x + vp2px(50), y: c.y }];
      const to: Point[] = [{ x: c.x - vp2px(150), y: c.y }, { x: c.x + vp2px(150), y: c.y }];
      await gesture(async () => {
        await driver.injectMultiPointerAction(twoFingers(from, to, 20), vp2px(400));
      });
      // The span tripled, less the slop, and momentum adds a little.
      expect(camera().zoom - ZOOM).assertLarger(1.2);
      expect(camera().zoom - ZOOM).assertLess(3);
      near(camera().bearing, 0, 0.01);
      near(camera().center.longitude, 0, 1);
    });

    it('rotates with a twist, and snaps to north from near it', 0, async () => {
      await reset();
      const c = center(await mapBounds());
      await gesture(async () => {
        await driver.injectMultiPointerAction(twist(c, vp2px(100), 60, 20), vp2px(300));
      });
      expect(Math.abs(wrap(camera().bearing))).assertLarger(40);
      near(camera().zoom, ZOOM, 0.1);

      // Fingers that stop before they lift leave no momentum.
      await reset();
      await gesture(async () => {
        await driver.injectMultiPointerAction(twist(c, vp2px(100), 10, 10, 20), vp2px(200));
      });
      // The snap starts after the gesture ends, once the map reports the
      // bearing.
      await until('the bearing snaps to north', () => Math.abs(wrap(camera().bearing)) < 0.001);
    });

    it('pitches when two fingers move up together', 0, async () => {
      await reset();
      const c = center(await mapBounds());
      const from: Point[] = [{ x: c.x - vp2px(50), y: c.y + vp2px(100) }, { x: c.x + vp2px(50), y: c.y + vp2px(100) }];
      const to: Point[] = [{ x: c.x - vp2px(50), y: c.y - vp2px(50) }, { x: c.x + vp2px(50), y: c.y - vp2px(50) }];
      await gesture(async () => {
        await driver.injectMultiPointerAction(twoFingers(from, to, 20), vp2px(300));
      });
      expect(camera().pitch).assertLarger(20);
      near(camera().zoom, ZOOM, 0.01);
    });

    it('zooms in one level with a double tap, and out with a two-finger tap', 0, async () => {
      await reset();
      const c = center(await mapBounds());
      await gesture(() => driver.doubleClick(c.x, c.y));
      near(camera().zoom, ZOOM + 1, 0.001);

      const fingers: Point[] = [{ x: c.x - vp2px(40), y: c.y }, { x: c.x + vp2px(40), y: c.y }];
      await gesture(async () => {
        await driver.injectMultiPointerAction(twoFingers(fingers, fingers, 2));
      });
      near(camera().zoom, ZOOM, 0.001);
    });

    it('zooms out at the pointer with the mouse wheel', 0, async () => {
      await reset();
      const c = center(await mapBounds());
      await gesture(() => driver.mouseScroll(c, true, 3));
      expect(camera().zoom).assertLess(ZOOM);
      near(camera().center.longitude, 0, 0.001);
    });

    it('pans and zooms with keys once a touch focuses it', 0, async () => {
      await reset();
      const c = center(await mapBounds());
      await driver.click(c.x, c.y);
      await gesture(() => driver.triggerKey(KeyCode.KEYCODE_DPAD_LEFT));
      near(camera().center.longitude / degreesPerVp(ZOOM), -100, 0.5);
      await gesture(() => driver.triggerKey(KeyCode.KEYCODE_EQUALS));
      near(camera().zoom, ZOOM + 1, 0.001);
    });

    it('takes the drags that start on it from a parent Scroll', 0, async () => {
      await reset(true);
      const bounds = await mapBounds();
      const c = center(bounds);
      await gesture(() => driver.swipe(c.x, c.y + vp2px(80), c.x, c.y - vp2px(80), vp2px(200)));
      expect(testMap.scroller.currentOffset().yOffset).assertEqual(0);
      expect(camera().center.latitude).assertLess(-5);

      // A drag below the map scrolls the page.
      const below = bounds.bottom + vp2px(250);
      await driver.swipe(c.x, below, c.x, below - vp2px(150), vp2px(400));
      await until('the page scrolls', () => testMap.scroller.currentOffset().yOffset > 50);
    });

    it('leaves one-finger drags to a parent Scroll in cooperative mode', 0, async () => {
      testMap.gestures = { cooperative: true };
      try {
        await reset(true);
        const c = center(await mapBounds());
        const starts = testMap.gestureStarts;
        await driver.swipe(c.x, c.y + vp2px(80), c.x, c.y - vp2px(40), vp2px(400));
        await until('the page scrolls', () => testMap.scroller.currentOffset().yOffset > 50);
        expect(testMap.gestureStarts).assertEqual(starts);
        near(camera().center.latitude, 0, 0.001);

        await reset(true);
        await until('the page scrolls back', () => testMap.scroller.currentOffset().yOffset === 0);
        const from: Point[] = [{ x: c.x - vp2px(50), y: c.y }, { x: c.x + vp2px(50), y: c.y }];
        const to: Point[] = [{ x: c.x - vp2px(150), y: c.y }, { x: c.x - vp2px(50), y: c.y }];
        await gesture(async () => {
          await driver.injectMultiPointerAction(twoFingers(from, to, 20), vp2px(300));
        });
        expect(testMap.scroller.currentOffset().yOffset).assertEqual(0);
        expect(camera().center.longitude).assertLarger(5);

        // The wheel scrolls the page, and zooms with Ctrl only.
        const zoom = camera().zoom;
        const wheelStarts = testMap.gestureStarts;
        await driver.mouseScroll(c, true, 3);
        await until('the wheel scrolls the page', () => testMap.scroller.currentOffset().yOffset > 0);
        expect(testMap.gestureStarts).assertEqual(wheelStarts);
        expect(camera().zoom).assertEqual(zoom);
        testMap.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
        await until('the page scrolls back', () => testMap.scroller.currentOffset().yOffset === 0);
        await gesture(() => driver.mouseScroll(c, false, 2, KeyCode.KEYCODE_CTRL_LEFT));
        expect(camera().zoom).assertLarger(zoom);
      } finally {
        testMap.gestures = {};
      }
    });
  });
}
