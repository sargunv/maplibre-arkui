// The gesture recognizer, fed made-up touches. Real input on the emulator is
// in GestureInput.test.ets.

import { describe, expect, it } from '@ohos/hypium';
import { CameraDelta, GesturePhase, ScreenPoint } from '@maplibre/arkui';
import {
  GestureTarget,
  MapGestures,
  Momentum,
  snapBearing,
  TouchPoint,
} from '@maplibre/arkui/src/main/ets/gestures';

import { expectNear, frames, until } from './helpers';

// Records what the gestures do to the camera.
class Recorder implements GestureTarget {
  deltas: CameraDelta[] = [];
  starts: number = 0;
  ends: number = 0;
  rotated: boolean = false;

  // Where each click was, and whether it was long.
  clicks: ScreenPoint[] = [];
  long: boolean[] = [];

  applyCameraDelta(delta: CameraDelta): void {
    this.deltas.push(delta);
  }

  clicked(point: ScreenPoint, long: boolean): void {
    this.clicks.push({ x: point.x, y: point.y });
    this.long.push(long);
  }

  gestureStarted(): void {
    this.starts++;
  }

  gestureEnded(rotated: boolean): void {
    this.ends++;
    this.rotated = rotated;
  }

  offsetX(from: number = 0): number {
    return this.deltas.slice(from).reduce((sum: number, d: CameraDelta) => sum + (d.offset?.x ?? 0), 0);
  }

  offsetY(from: number = 0): number {
    return this.deltas.slice(from).reduce((sum: number, d: CameraDelta) => sum + (d.offset?.y ?? 0), 0);
  }

  zoom(): number {
    return this.deltas.reduce((sum: number, d: CameraDelta) => sum + Math.log2(d.scale ?? 1), 0);
  }

  bearing(): number {
    return this.deltas.reduce((sum: number, d: CameraDelta) => sum + (d.bearing ?? 0), 0);
  }

  pitch(): number {
    return this.deltas.reduce((sum: number, d: CameraDelta) => sum + (d.pitch ?? 0), 0);
  }

  phases(): number[] {
    return this.deltas.map((d: CameraDelta) => d.gesturePhase ?? GesturePhase.none);
  }

  lastPhase(): number {
    return this.deltas[this.deltas.length - 1].gesturePhase ?? GesturePhase.none;
  }
}

function touch(id: number, x: number, y: number): TouchPoint {
  return { id: id, x: x, y: y };
}

function lerp(from: TouchPoint[], to: TouchPoint[], t: number): TouchPoint[] {
  return from.map((a: TouchPoint, i: number) => touch(a.id, a.x + (to[i].x - a.x) * t, a.y + (to[i].y - a.y) * t));
}

// Puts `from` down at `time`, moves to `to` in `steps` events `ms` apart, and
// claims at the first move, as ArkUI's pan does after 5 vp. Returns the time
// of the last move.
function drag(gestures: MapGestures, time: number, from: TouchPoint[], to: TouchPoint[], steps: number,
  ms: number, claim: boolean = true): number {
  gestures.touch(time, from);
  for (let i = 1; i <= steps; i++) {
    gestures.touch(time + i * ms, lerp(from, to, i / steps));
    if (i === 1 && claim) {
      gestures.claim();
    }
  }
  return time + steps * ms;
}

// Two touches on a circle about (200, 300), `degrees` around it.
function onCircle(radius: number, degrees: number): TouchPoint[] {
  const r = degrees * Math.PI / 180;
  return [
    touch(1, 200 - radius * Math.cos(r), 300 - radius * Math.sin(r)),
    touch(2, 200 + radius * Math.cos(r), 300 + radius * Math.sin(r)),
  ];
}

// Where a delta moves the content at `x` on the fingers' line: by its offset,
// then about its anchor.
function moveX(delta: CameraDelta, x: number): number {
  const moved = x + (delta.offset?.x ?? 0);
  const anchor = delta.anchor?.x ?? 0;
  return anchor + (moved - anchor) * (delta.scale ?? 1);
}

function twist(gestures: MapGestures, radius: number, degrees: number, steps: number): number {
  gestures.touch(0, onCircle(radius, 0));
  for (let i = 1; i <= steps; i++) {
    gestures.touch(i * 16, onCircle(radius, degrees * i / steps));
    if (i === 1) {
      gestures.claim();
    }
  }
  return steps * 16;
}

export default function gesturesTest(): void {
  describe('MapGestures', () => {
    it('moves nothing until one of its ArkUI gestures claims the touches', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 16, false);
      gestures.touch(end, []);
      expect(camera.deltas.length).assertEqual(0);
      expect(camera.starts).assertEqual(0);
    });

    it('pans by the motion after the claim, and ends without momentum when slow', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 200)], 10, 50);
      gestures.touch(end + 10, []);
      expectNear(camera.offsetY(), 90, 0.001);
      expect(camera.offsetX()).assertEqual(0);
      expect(camera.phases()[0]).assertEqual(GesturePhase.begin);
      expect(camera.lastPhase()).assertEqual(GesturePhase.end);
      expect(camera.starts).assertEqual(1);
      expect(camera.ends).assertEqual(1);
    });

    it('flings a fast drag, in steps of at most 16 vp, then ends', 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      const released = camera.deltas.length;
      gestures.touch(end + 5, []);
      expect(camera.ends).assertEqual(0);
      await until('the fling ends', () => camera.ends === 1);
      expect(camera.lastPhase()).assertEqual(GesturePhase.end);
      // 2000 vp/s flings for 2000 / 10.5 + 150 ms, and 0.28 of the speed
      // times that, 190.7 vp.
      expectNear(camera.offsetY(released), 2000 * (2000 / 10.5 + 150) * 0.28 / 1000, 0.001);
      for (const delta of camera.deltas.slice(released)) {
        expect(Math.abs(delta.offset?.y ?? 0)).assertLessOrEqual(16);
      }
    });

    it('stops momentum when a finger goes down', 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.touch(end + 5, []);
      gestures.touch(end + 20, [touch(2, 50, 50)]);
      expect(camera.ends).assertEqual(1);
      expect(camera.lastPhase()).assertEqual(GesturePhase.end);
      const count = camera.deltas.length;
      await frames(5);
      expect(camera.deltas.length).assertEqual(count);
    });

    it('stops momentum when the wheel or a touchpad pinch takes over', 0, async () => {
      for (const wheel of [true, false]) {
        const camera = new Recorder();
        const gestures = new MapGestures(camera);
        const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
        gestures.touch(end + 5, []);
        if (wheel) {
          gestures.wheel(-1, false);
        } else {
          gestures.touchpadPinch(1.5);
        }
        // The fling's gesture ends, then the new input starts its own.
        expect(camera.ends).assertEqual(1);
        expect(camera.starts).assertEqual(2);
        expect(camera.lastPhase()).assertEqual(GesturePhase.begin);
        // No fling steps follow the new input.
        const count = camera.deltas.length;
        await frames(5);
        expect(camera.deltas.length).assertEqual(count);
      }
    });

    it('leaves a fling alone when the wheel it ignores ends', 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = { zoom: false };
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.touch(end + 5, []);
      gestures.wheel(-1, false);
      gestures.axisEnded();
      expect(camera.ends).assertEqual(0);
      await until('the fling ends', () => camera.ends === 1);
      expect(camera.starts).assertEqual(1);
    });

    it('stops a fling whose options change', 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.touch(end + 5, []);
      gestures.options = { pan: false };
      expect(camera.ends).assertEqual(1);
      const count = camera.deltas.length;
      await frames(5);
      expect(camera.deltas.length).assertEqual(count);
    });

    it('starts a touchpad pinch afresh after one is cancelled', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.touchpadPinch(1.5);
      gestures.pinchCancelled();
      expect(camera.ends).assertEqual(1);
      const zoom = camera.zoom();
      gestures.touchpadPinch(1.1);
      expectNear(camera.zoom() - zoom, Math.log2(1.1), 0.0001);
    });

    it('ends without momentum when the system cancels the touches', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.cancel();
      expect(camera.lastPhase()).assertEqual(GesturePhase.cancel);
      expect(camera.ends).assertEqual(1);
      expect(gestures.idle).assertTrue();
    });

    it('releases without momentum for a motion turned off just before', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.options = { pan: false };
      gestures.touch(end + 5, []);
      expect(camera.ends).assertEqual(1);

      // A pinch's momentum waits for its last finger.
      const pinch = new Recorder();
      const pinching = new MapGestures(pinch);
      const last = drag(pinching, 0, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 50, 300), touch(2, 350, 300)], 20, 16);
      pinching.touch(last + 5, [touch(2, 350, 300)]);
      pinching.options = { zoom: false };
      pinching.touch(last + 10, []);
      expect(pinch.ends).assertEqual(1);
    });

    it('drops the waiting momentum of a pinch when the app takes over', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const last = drag(gestures, 0, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 50, 300), touch(2, 350, 300)], 20, 16);
      gestures.touch(last + 5, [touch(2, 350, 300)]);
      gestures.stop();
      gestures.touch(last + 10, []);
      expect(camera.ends).assertEqual(1);
    });

    it('pans with no finger left from a pair in cooperative mode', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = { cooperative: true };
      const end = drag(gestures, 0, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 250, 300), touch(2, 350, 300)], 10, 40);
      gestures.touch(end + 40, [touch(2, 350, 300)]);
      const panned = camera.offsetX();
      for (let i = 1; i <= 10; i++) {
        gestures.touch(end + 40 + i * 40, [touch(2, 350 + i * 10, 300)]);
      }
      expect(camera.offsetX()).assertEqual(panned);
    });

    it('pinches about the fingers without panning or rotating', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 50, 300), touch(2, 350, 300)], 20, 16);
      gestures.touch(end + 100, []);
      // The span grew from 100 to 300 vp; the first two steps start the pinch.
      expectNear(camera.zoom(), Math.log2(300 / 120), 0.001);
      expect(camera.offsetX()).assertEqual(0);
      expect(camera.bearing()).assertEqual(0);
      expect(camera.pitch()).assertEqual(0);
      const anchor = camera.deltas[1].anchor;
      expect(anchor?.x).assertEqual(200);
      expect(anchor?.y).assertEqual(300);
    });

    it('keeps the content under the fingers of a pinch that report one at a time', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const fingers = [touch(1, 150, 300), touch(2, 250, 300)];
      gestures.touch(0, fingers);
      let zooms = 0;
      for (let i = 1; i <= 40; i++) {
        // As ArkUI reports them: each event moves one finger out, in turn.
        const moving = (i - 1) % 2;
        const still = fingers[1 - moving].x;
        fingers[moving] = touch(moving + 1, fingers[moving].x + (moving === 0 ? -5 : 5), 300);
        const count = camera.deltas.length;
        gestures.touch(i * 8, fingers.slice());
        if (i === 1) {
          gestures.claim();
        }
        const delta = camera.deltas[count];
        if (delta?.scale !== undefined) {
          zooms++;
          expectNear(moveX(delta, still), still, 1e-9);
        }
      }
      expect(zooms).assertLarger(30);
    });

    it('twists to rotate without zooming', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = twist(gestures, 100, 60, 20);
      gestures.touch(end + 100, []);
      // The claim takes the first step, and a fast turn has to go 7 degrees,
      // three more steps, to start the rotation.
      expectNear(camera.bearing(), -48, 0.001);
      expect(camera.zoom()).assertEqual(0);
      expect(camera.ends).assertEqual(1);
      expect(camera.rotated).assertTrue();
    });

    it("doesn't rotate from a pinch's small changes of angle", 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.touch(0, onCircle(40, 0));
      for (let i = 1; i <= 20; i++) {
        gestures.touch(i * 16, onCircle(40 + i * 5, i * 0.5));
        if (i === 1) {
          gestures.claim();
        }
      }
      gestures.touch(400, []);
      expect(camera.zoom()).assertLarger(1);
      expect(camera.bearing()).assertEqual(0);
    });

    it("doesn't zoom from a slow change of span", 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 140, 300), touch(2, 260, 300)], 20, 16);
      gestures.touch(end + 100, []);
      expect(camera.zoom()).assertEqual(0);
    });

    it('pitches when two fingers move up together, and stops panning', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 150, 400), touch(2, 250, 400)],
        [touch(1, 150, 250), touch(2, 250, 250)], 15, 40);
      gestures.touch(end + 100, []);
      // 10 vp a step after the claim: the first starts a pan, the second moves
      // it and starts the pitch, and 12 more tilt 0.3 degrees a vp.
      expectNear(camera.pitch(), 36, 0.001);
      expectNear(camera.offsetY(), -10, 0.001);
      expect(camera.zoom()).assertEqual(0);
    });

    it("doesn't fling the finger left behind by a pinch", 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 100, 300), touch(2, 300, 300)], 10, 16);
      gestures.touch(end + 10, [touch(1, 100, 300)]);
      const lifted = camera.deltas.length;
      gestures.touch(end + 20, [touch(1, 103, 300)]);
      gestures.touch(end + 30, []);
      await until('the gesture ends', () => camera.ends === 1);
      expect(camera.offsetX(lifted)).assertEqual(0);
    });

    it('moves only as the options allow', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = { rotate: false, zoom: false };
      let end = twist(gestures, 100, 60, 20);
      gestures.touch(end + 100, []);
      end = drag(gestures, 1000, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 50, 300), touch(2, 350, 300)], 20, 40);
      gestures.touch(end + 100, []);
      expect(camera.bearing()).assertEqual(0);
      expect(camera.zoom()).assertEqual(0);
      gestures.doubleTap(100, 100);
      expect(camera.zoom()).assertEqual(0);
    });

    it('pans with a tap and then a drag down while zoom is off', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.height = 600;
      gestures.options = { zoom: false };
      gestures.touch(0, [touch(1, 200, 300)]);
      gestures.touch(80, []);
      const end = drag(gestures, 200, [touch(2, 200, 300)], [touch(2, 200, 450)], 10, 50);
      gestures.touch(end + 100, []);
      expect(camera.zoom()).assertEqual(0);
      expectNear(camera.offsetY(), 135, 0.001);
    });

    it('stops a two-finger motion whose option turns off mid-gesture', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const from = [touch(1, 150, 300), touch(2, 250, 300)];
      const to = [touch(1, 350, 300), touch(2, 450, 300)];
      gestures.touch(0, from);
      for (let i = 1; i <= 20; i++) {
        if (i === 11) {
          gestures.options = { pan: false };
        }
        gestures.touch(i * 40, lerp(from, to, i / 20));
        if (i === 1) {
          gestures.claim();
        }
      }
      // It panned until the option turned off at 100 of the 200 vp.
      const panned = camera.offsetX();
      expect(panned).assertLarger(0);
      expect(panned).assertLess(101);
    });

    it('zooms about the center with a tap and then a drag down', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.height = 600;
      gestures.touch(0, [touch(1, 200, 300)]);
      gestures.touch(80, []);
      const end = drag(gestures, 200, [touch(2, 200, 300)], [touch(2, 200, 450)], 10, 50);
      gestures.touch(end + 100, []);
      // The claim's 15 vp doesn't count: 135 vp of 600 is 0.9 levels.
      expectNear(camera.zoom(), 0.9, 0.001);
      expect(camera.offsetY()).assertEqual(0);
      expect(camera.deltas[0].anchor).assertUndefined();
    });

    it('zooms in at a double tap and out at a two-finger tap, as animations', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.doubleTap(10, 20);
      expect(camera.deltas[0].scale).assertEqual(2);
      expect(camera.deltas[0].anchor?.x).assertEqual(10);
      expect(camera.deltas[0].animation?.durationMs).assertEqual(300);
      gestures.twoFingerTap(30, 40);
      expect(camera.deltas[1].scale).assertEqual(0.5);
      // The second step replaced the first, which ended.
      expect(camera.starts).assertEqual(2);
      expect(camera.ends).assertEqual(1);
    });

    it('clicks at a tap once no second tap follows, and not at a double tap and drag', 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.height = 600;
      gestures.touch(0, [touch(1, 200, 300)]);
      gestures.touch(80, [touch(1, 204, 300)]);
      gestures.touch(100, []);
      // It waits for a second tap first.
      expect(camera.clicks.length).assertEqual(0);
      await until('the tap clicks', () => camera.clicks.length === 1);
      expect(camera.clicks[0].x).assertEqual(204);
      expect(camera.long[0]).assertFalse();

      gestures.touch(1000, [touch(2, 200, 300)]);
      gestures.touch(1080, []);
      const end = drag(gestures, 1200, [touch(3, 200, 300)], [touch(3, 200, 450)], 10, 50);
      gestures.touch(end + 100, []);
      await frames(40);
      expect(camera.clicks.length).assertEqual(1);
      expect(camera.zoom()).assertLarger(0);
    });

    it('clicks at once while zoom is off, and long at a long press or a right click', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = { zoom: false };
      gestures.touch(0, [touch(1, 200, 300)]);
      gestures.touch(80, []);
      expect(JSON.stringify(camera.long)).assertEqual('[false]');

      gestures.touch(1000, [touch(2, 100, 100)]);
      gestures.longPress();
      gestures.touch(1600, []);
      expect(JSON.stringify(camera.long)).assertEqual('[false,true]');
      expect(camera.clicks[1].x).assertEqual(100);

      gestures.rightClick(MouseAction.Press, { x: 50, y: 60 });
      gestures.rightClick(MouseAction.Release, { x: 52, y: 60 });
      expect(JSON.stringify(camera.long)).assertEqual('[false,true,true]');
      // A long press after a drag isn't a click.
      drag(gestures, 2000, [touch(3, 200, 300)], [touch(3, 300, 300)], 5, 20);
      gestures.longPress();
      expect(camera.long.length).assertEqual(3);
    });

    it('snaps a bearing near north', 0, () => {
      expect(snapBearing(5)).assertEqual(0);
      expect(snapBearing(-6)).assertEqual(0);
      expect(snapBearing(355)).assertEqual(360);
      expect(snapBearing(20)).assertUndefined();
      expect(snapBearing(0)).assertUndefined();
    });

    it("plans momentum as MapLibre Compose's GestureMath does", 0, () => {
      expect(Momentum.plan(200, 0, 0, 0, undefined)).assertUndefined();
      const fling = Momentum.plan(1000, 0, 0, 0, undefined);
      expectNear(fling?.durationMs ?? NaN, 1000 / 10.5 + 150, 0.001);
      expectNear(fling?.offsetX ?? NaN, 1000 * (1000 / 10.5 + 150) * 0.28 / 1000, 0.001);
      expect(fling?.power).assertEqual(2);
      // With zoom, the pan follows the zoom's quartic curve over 600 ms.
      const pinch = Momentum.plan(1000, 0, 4, 0, { x: 1, y: 2 });
      expect(pinch?.durationMs).assertEqual(600);
      expect(pinch?.power).assertEqual(4);
      expectNear(pinch?.zoomLevels ?? NaN, 0.6, 0.001);
      expect(Momentum.plan(0, 0, 100, 0, undefined)?.zoomLevels).assertEqual(2.5);
      // Its steps add up to the whole.
      const deltas = pinch?.advance(300) ?? [];
      const rest = pinch?.advance(600) ?? [];
      const total = deltas.concat(rest).reduce((sum: number, d: CameraDelta) => sum + Math.log2(d.scale ?? 1), 0);
      expectNear(total, 0.6, 0.0001);
      expect(pinch?.done).assertTrue();
    });
  });
}
