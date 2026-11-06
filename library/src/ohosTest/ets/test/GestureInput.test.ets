// Real input on the test page's map, injected through the system with
// UiTest's Driver, and read back from the camera. Driver takes px, so the
// cases aim in vp and convert, whatever the display's density.

import { beforeEach, describe, expect, it } from '@ohos/hypium';
import { CameraUpdateMode, LatLng, ScreenPoint, WheelAction } from '@maplibre/arkui';

import { Driver, Point, UiDirection } from '@ohos.UiTest';
import { KeyCode } from '@ohos.multimodalInput.keyCode';

import { STYLE, testMap } from '../testability/TestMaps';
import {
  camera,
  expectNear,
  frames,
  gesture,
  inMap,
  latLngAt,
  mapBounds,
  mapCenter,
  offset,
  pixelFor,
  speed,
  twist,
  twoFingers,
  until,
  vp2px,
} from './helpers';

const ZOOM = 3;
const ORIGIN: LatLng = { latitude: 0, longitude: 0 };

// Shows the map alone or in a Scroll, with the camera at the origin at ZOOM.
async function start(inScroll: boolean = false): Promise<void> {
  await testMap.reset(STYLE, inScroll);
  await testMap.controller.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: ZOOM } });
}

// How far the map has moved the origin from its center, in vp.
function moved(): ScreenPoint {
  const center = pixelFor(camera().center);
  const origin = pixelFor(ORIGIN);
  return { x: origin.x - center.x, y: origin.y - center.y };
}

// Fingers that twist 10 degrees and hold still for 200 ms at 200 vp/s, longer
// than the 100 ms that a release measures its speed over, so they leave no
// momentum.
const STILL_TWIST_HOLD = 40;

function wrap(degrees: number): number {
  return (((degrees + 180) % 360) + 360) % 360 - 180;
}

export default function gestureInputTest(): void {
  describe('GestureInput', () => {
    const driver = Driver.create();

    beforeEach(async () => {
      await start();
    });

    it('pans with a slow drag, without momentum', 0, async () => {
      const c = await mapCenter();
      const from = offset(c, 100, 0);
      const to = offset(c, -100, 0);
      // Under the speed that flings.
      await gesture(() => driver.swipe(from.x, from.y, to.x, to.y, speed(200)));
      // The drag less the claim's few vp.
      expect(moved().x).assertLess(-170);
      expect(moved().x).assertLargerOrEqual(-200);
      expectNear(moved().y, 0, 1);
      // The observable camera rests there too.
      await until('the controller\'s camera rests', () =>
        testMap.controller.camera?.center.longitude === camera().center.longitude);
    });

    it('keeps one gesture when the app moves the camera as it starts', 0, async () => {
      const c = await mapCenter();
      const from = offset(c, 100, 0);
      const to = offset(c, -100, 0);
      const starts = testMap.gestureStarts;
      const ends = testMap.gestureEnds;
      // As an app that stops following a location does.
      testMap.onGestureStart = () => {
        testMap.controller.cancelCameraTransitions();
      };
      await gesture(() => driver.swipe(from.x, from.y, to.x, to.y, speed(200)));
      expect(testMap.gestureStarts - starts).assertEqual(1);
      expect(testMap.gestureEnds - ends).assertEqual(1);
      expect(moved().x).assertLess(-170);
    });

    it('coasts past the end of a fast drag', 0, async () => {
      const c = await mapCenter();
      await gesture(() => driver.fling(offset(c, 100, 0), offset(c, -100, 0), speed(20), speed(2000)));
      // Without momentum, the camera would move less than the 200 vp drag.
      expect(moved().x).assertLess(-220);
    });

    it('zooms with a pinch, without rotating', 0, async () => {
      const c = await mapCenter();
      const from: Point[] = [offset(c, -50, 0), offset(c, 50, 0)];
      const to: Point[] = [offset(c, -150, 0), offset(c, 150, 0)];
      const steps = 20;
      await gesture(async () => {
        await driver.injectMultiPointerAction(twoFingers(from, to, steps), speed(400));
      });
      // The span tripled, less the slop, and momentum adds a little.
      const zoomed = camera().zoom - ZOOM;
      expect(zoomed).assertLarger(1.2);
      expect(zoomed).assertLess(3);
      expectNear(camera().bearing, 0, 0.01);
      // About the fingers, which are at the center. The system reports one
      // finger at a time, and the zoom starts from one finger's step, which
      // can leave the content half a step from the fingers' midpoint. The
      // map's center can be half a vp from the component's, since the map's
      // size is in whole vp. The zoom scales both.
      const slop = (100 / (steps - 1) / 2 + 1) * Math.pow(2, zoomed);
      expectNear(moved().x, 0, slop);
      expectNear(moved().y, 0, 1);
    });

    it('rotates with a twist, and snaps to north from near it', 0, async () => {
      testMap.compass = true;
      const c = await mapCenter();
      await gesture(async () => {
        await driver.injectMultiPointerAction(twist(c, 100, 60, 20), speed(300));
      });
      expect(Math.abs(wrap(camera().bearing))).assertLarger(40);
      expectNear(camera().zoom, ZOOM, 0.1);

      await start();
      testMap.compass = true;
      await gesture(async () => {
        await driver.injectMultiPointerAction(twist(c, 100, 10, 10, STILL_TWIST_HOLD), speed(200));
      });
      // The snap starts after the gesture ends, once the map reports the
      // bearing.
      await until('the bearing snaps to north', () => Math.abs(wrap(camera().bearing)) < 0.001);
    });

    it('snaps to the bearings that the options give, or not at all', 0, async () => {
      const c = await mapCenter();
      testMap.compass = true;
      testMap.interactions = { rotate: { snapBearings: [90] } };
      await testMap.controller.updateCamera({ mode: CameraUpdateMode.jump, camera: { bearing: 90 } });
      await gesture(async () => {
        await driver.injectMultiPointerAction(twist(c, 100, 10, 10, STILL_TWIST_HOLD), speed(200));
      });
      await until('the bearing snaps to east', () => Math.abs(wrap(camera().bearing - 90)) < 0.001);

      await start();
      testMap.compass = true;
      testMap.interactions = { rotate: { snapBearings: [] } };
      await gesture(async () => {
        await driver.injectMultiPointerAction(twist(c, 100, 10, 10, STILL_TWIST_HOLD), speed(200));
      });
      // A snap would start once the map reports the bearing; give it time.
      await frames(30);
      expect(Math.abs(wrap(camera().bearing))).assertLarger(1);
    });

    it('runs the onStart of each movement as the user starts it', 0, async () => {
      let pans = 0;
      let zooms = 0;
      testMap.interactions = {
        pan: {
          onStart: () => {
            pans++;
          },
        },
        zoom: {
          onStart: () => {
            zooms++;
          },
        },
      };
      const c = await mapCenter();
      const from = offset(c, 100, 0);
      const to = offset(c, -100, 0);
      await gesture(() => driver.swipe(from.x, from.y, to.x, to.y, speed(200)));
      expect(pans).assertEqual(1);
      expect(zooms).assertEqual(0);
      // A notch of the wheel is a gesture of its own.
      await gesture(() => driver.mouseScroll(c, true, 1));
      expect(zooms).assertEqual(1);
    });

    it('keeps a camera jump that the app makes as the gesture ends', 0, async () => {
      const c = await mapCenter();
      testMap.onGestureEnd = () => {
        testMap.controller.updateCamera({ mode: CameraUpdateMode.jump, camera: { bearing: 5 } });
      };
      await gesture(async () => {
        await driver.injectMultiPointerAction(twist(c, 100, 10, 10, STILL_TWIST_HOLD), speed(200));
      });
      // A snap would start once the map reports the bearing; give it time.
      await frames(30);
      expectNear(wrap(camera().bearing), 5, 0.001);
    });

    it('pitches when two fingers move up together', 0, async () => {
      testMap.compass = true;
      const c = await mapCenter();
      const from: Point[] = [offset(c, -50, 100), offset(c, 50, 100)];
      const to: Point[] = [offset(c, -50, -50), offset(c, 50, -50)];
      // The system reports one finger at a time, and a finger a step ahead
      // turns the pair. In steps of 2.5 vp, that stays under the rotation's
      // slop, which would start a rotation instead.
      await gesture(async () => {
        await driver.injectMultiPointerAction(twoFingers(from, to, 61), speed(300));
      });
      expect(camera().pitch).assertLarger(20);
      expectNear(camera().zoom, ZOOM, 0.01);
      expectNear(camera().bearing, 0, 0.01);
    });

    it('zooms in one level with a double tap, and out with a two-finger tap', 0, async () => {
      const c = await mapCenter();
      await gesture(() => driver.doubleClick(c.x, c.y));
      expectNear(camera().zoom, ZOOM + 1, 0.001);

      const fingers: Point[] = [offset(c, -40, 0), offset(c, 40, 0)];
      await gesture(async () => {
        await driver.injectMultiPointerAction(twoFingers(fingers, fingers, 2));
      });
      expectNear(camera().zoom, ZOOM, 0.001);
    });

    it('zooms out at the pointer with the mouse wheel', 0, async () => {
      const bounds = await mapBounds();
      const pointer = offset(await mapCenter(), 100, 100);
      const at = inMap(bounds, pointer);
      const under = latLngAt(at);
      await gesture(() => driver.mouseScroll(pointer, true, 3));
      expect(camera().zoom).assertLess(ZOOM);
      // The coordinate under the pointer stays there, to within the input's
      // rounding to px. About the center, it would move 50 vp.
      const now = pixelFor(under);
      expectNear(now.x, at.x, 1);
      expectNear(now.y, at.y, 1);
    });

    it('pans with the mouse wheel in pan mode, and zooms with Ctrl', 0, async () => {
      testMap.interactions = { wheel: WheelAction.pan };
      const c = await mapCenter();
      // Scrolling down shows what's below, as a page does.
      await gesture(() => driver.mouseScroll(c, true, 3));
      expect(moved().y).assertLess(-50);
      expectNear(moved().x, 0, 1);
      expectNear(camera().zoom, ZOOM, 1e-9);
      await gesture(() => driver.mouseScroll(c, false, 2, KeyCode.KEYCODE_CTRL_LEFT));
      expect(camera().zoom).assertLarger(ZOOM);
    });

    it('pans with a two-finger touchpad swipe the way a Scroll scrolls', 0, async () => {
      await start(true);
      const bounds = await mapBounds();
      const c = await mapCenter();
      // The page scrolls one way under a swipe below the map...
      const below = offset({ x: c.x, y: bounds.bottom }, 0, 250);
      await driver.touchPadTwoFingersScroll(below, UiDirection.UP, 2);
      await until('the page scrolls', () => testMap.scroller.currentOffset().yOffset !== 0);
      const scrolled = testMap.scroller.currentOffset().yOffset;
      testMap.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
      await until('the page scrolls back', () => testMap.scroller.currentOffset().yOffset === 0);
      // ...and the map's content moves the same way under one on the map.
      await gesture(() => driver.touchPadTwoFingersScroll(c, UiDirection.UP, 2));
      expectNear(camera().zoom, ZOOM, 1e-9);
      expect(Math.abs(moved().y)).assertLarger(20);
      expect(moved().y < 0).assertEqual(scrolled > 0);
      expectNear(moved().x, 0, 1);
    });

    it('pans and zooms with keys once a touch focuses it', 0, async () => {
      const c = await mapCenter();
      await driver.click(c.x, c.y);
      await gesture(() => driver.triggerKey(KeyCode.KEYCODE_DPAD_LEFT));
      expectNear(moved().x, 100, 0.01);
      await gesture(() => driver.triggerKey(KeyCode.KEYCODE_EQUALS));
      expectNear(camera().zoom, ZOOM + 1, 0.001);
      // Shift and an arrow rotate a step.
      await gesture(() => driver.triggerCombineKeys(KeyCode.KEYCODE_SHIFT_LEFT, KeyCode.KEYCODE_DPAD_LEFT));
      expectNear(wrap(camera().bearing), 15, 0.001);
    });

    it('takes the drags that start on it from a parent Scroll', 0, async () => {
      await start(true);
      const bounds = await mapBounds();
      const c = await mapCenter();
      const from = offset(c, 0, 80);
      const to = offset(c, 0, -80);
      await gesture(() => driver.swipe(from.x, from.y, to.x, to.y, speed(200)));
      expect(testMap.scroller.currentOffset().yOffset).assertEqual(0);
      expect(moved().y).assertLess(-100);

      // A drag below the map scrolls the page.
      const below = offset({ x: c.x, y: bounds.bottom }, 0, 250);
      const above = offset(below, 0, -150);
      await driver.swipe(below.x, below.y, above.x, above.y, speed(400));
      await until('the page scrolls', () => testMap.scroller.currentOffset().yOffset > 50);
    });

    it('leaves one-finger drags to a parent Scroll in cooperative mode', 0, async () => {
      await start(true);
      testMap.interactions = { cooperative: true };
      const c = await mapCenter();
      const starts = testMap.gestureStarts;
      const from = offset(c, 0, 80);
      const to = offset(c, 0, -40);
      await driver.swipe(from.x, from.y, to.x, to.y, speed(400));
      await until('the page scrolls', () => testMap.scroller.currentOffset().yOffset > 50);
      expect(testMap.gestureStarts).assertEqual(starts);
      expectNear(camera().center.latitude, 0, 1e-9);

      testMap.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
      await until('the page scrolls back', () => testMap.scroller.currentOffset().yOffset === 0);
      const pair: Point[] = [offset(c, -50, 0), offset(c, 50, 0)];
      const left: Point[] = [offset(c, -150, 0), offset(c, -50, 0)];
      await gesture(async () => {
        await driver.injectMultiPointerAction(twoFingers(pair, left, 20), speed(300));
      });
      expect(testMap.scroller.currentOffset().yOffset).assertEqual(0);
      expect(moved().x).assertLess(-50);

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
    });
  });
}
