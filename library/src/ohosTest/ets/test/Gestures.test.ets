// The gesture recognizer, fed made-up touches. Real input on the emulator is
// in GestureInput.test.ets.

import { describe, expect, it } from '@ohos/hypium';
import { InteractionOptions, WheelAction } from '@maplibre/arkui';
import { CameraDelta, CameraTransitionOutcome, GesturePhase, ScreenPoint } from '@maplibre/native-ffi';
import { GestureTarget, MapGestures, TouchPoint } from '@maplibre/arkui/src/main/ets/interaction/internal/MapGestures';
import { playTick } from '@maplibre/arkui/src/main/ets/interaction/internal/Haptics';
import { KeyCode } from '@ohos.multimodalInput.keyCode';

import { expectNear, frames, until } from './helpers';

// Records what the gestures do to the camera.
class Recorder implements GestureTarget {
  deltas: CameraDelta[] = [];
  starts: number = 0;
  ends: number = 0;
  // The display's px per vp.
  px: number = 3;
  // The pans, rotations, zooms, and starts that the gestures told of, in order.
  told: string[] = [];
  errors: string[] = [];
  ticks: number = 0;
  // The camera's bearing before the deltas.
  initialBearing: number = 0;
  // Whether zoom and rotation keep the center, as while following a location.
  keeps: boolean = false;

  // Where each click was, and whether it was long.
  clicks: ScreenPoint[] = [];
  long: boolean[] = [];

  // A gesture's end with nothing to glide or snap ends at once, as the map
  // ends it.
  applyCameraDelta(delta: CameraDelta): void {
    this.deltas.push(delta);
    const m = delta.momentum;
    if (m !== undefined && (m.pan?.velocity?.x ?? 0) === 0 && (m.pan?.velocity?.y ?? 0) === 0 &&
      (m.zoom?.velocity ?? 0) === 0 && (m.bearing?.velocity ?? 0) === 0 && (m.pitch?.velocity ?? 0) === 0 &&
      m.zoom?.snap === undefined && m.bearing?.snap === undefined && m.pitch?.snap === undefined) {
      this.endAnimation(delta);
    }
  }

  // The IDs of the transitions that the gestures stopped.
  cancelled: bigint[] = [];

  cancelTransitions(transitionId: bigint): void {
    this.cancelled.push(transitionId);
  }

  clicked(point: ScreenPoint, long: boolean): void {
    this.clicks.push({ x: point.x, y: point.y });
    this.long.push(long);
  }

  getBearing(): number {
    return this.initialBearing + this.bearing();
  }

  density(): number {
    return this.px;
  }

  gestureStarted(): void {
    this.starts++;
    this.told.push('start');
  }

  panned(): void {
    this.told.push('pan');
  }

  rotated(): void {
    this.told.push('rotate');
  }

  zoomed(): void {
    this.told.push('zoom');
  }

  gestureEnded(): void {
    this.ends++;
  }

  hapticTick(): void {
    this.ticks++;
  }

  keepsCenter(): boolean {
    return this.keeps;
  }

  fail(error: Error): void {
    this.errors.push(error.message);
  }

  // Ends the animation or momentum of a delta, the last by default, as the
  // map does.
  endAnimation(delta: CameraDelta = this.deltas[this.deltas.length - 1]): void {
    delta.animation?.endHandler?.callback?.({
      outcome: CameraTransitionOutcome.completed,
      generation: BigInt(0),
      velocity: { pan: { x: 0, y: 0 }, zoom: 0, bearing: 0, pitch: 0 },
    });
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

// Twists from `start`, and returns the time of the last move.
function twist(gestures: MapGestures, radius: number, degrees: number, steps: number, start: number = 0): number {
  gestures.touch(start, onCircle(radius, 0));
  for (let i = 1; i <= steps; i++) {
    gestures.touch(start + i * 16, onCircle(radius, degrees * i / steps));
    if (i === 1) {
      gestures.claim();
    }
  }
  return start + steps * 16;
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

    it('pans by the motion after the claim, and ends without momentum when still', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 200)], 10, 50);
      // The finger rests longer than the release measures its speed over.
      gestures.touch(end + 150, []);
      expectNear(camera.offsetY(), 90, 0.001);
      expect(camera.offsetX()).assertEqual(0);
      expect(camera.phases()[0]).assertEqual(GesturePhase.begin);
      expect(camera.lastPhase()).assertEqual(GesturePhase.end);
      expect(camera.starts).assertEqual(1);
      expect(camera.ends).assertEqual(1);
    });

    it('flings a drag as ArkUI flings a list, and ends when the glide does', 0, () => {
      for (const px of [3, 1]) {
        const camera = new Recorder();
        camera.px = px;
        const gestures = new MapGestures(camera);
        // 2000 vp/s.
        const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
        gestures.touch(end + 5, []);
        const glide = camera.deltas[camera.deltas.length - 1];
        expect(glide.gesturePhase).assertEqual(GesturePhase.end);
        expect(glide.animation?.durationMs).assertUndefined();
        // 6000 px/s glides with 1.5 times the speed and friction 0.75, and
        // 2000 px/s, under 3000, with 1.2 times and friction 1.
        const pan = glide.momentum?.pan;
        expectNear(pan?.velocity?.y ?? NaN, px === 3 ? 3000 : 2400, 1e-6);
        expect(pan?.velocity?.x).assertEqual(0);
        expectNear(pan?.decay?.halfLifeMs ?? NaN, Math.LN2 / (4.2 * (px === 3 ? 0.75 : 1)) * 1000, 1e-6);
        expectNear(pan?.decay?.minSpeed ?? NaN, 240 / px, 1e-9);
        expectNear(pan?.decay?.stopSpeed ?? NaN, 120 / px, 1e-9);
        expect(pan?.decay?.maxSpeed).assertEqual(9000);
        // The gesture lasts until the map ends the glide.
        expect(camera.ends).assertEqual(0);
        expect(gestures.idle).assertFalse();
        camera.endAnimation();
        expect(camera.ends).assertEqual(1);
        expect(gestures.idle).assertTrue();
      }
    });

    it("doesn't glide a movement whose momentum is off, and still snaps it", 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = { pan: { momentum: { enabled: false } }, rotate: { momentum: { enabled: false } } };
      let end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.touch(end + 5, []);
      expect(camera.deltas[camera.deltas.length - 1].momentum?.pan).assertUndefined();
      expect(camera.ends).assertEqual(1);
      end = twist(gestures, 100, 60, 10, 1000);
      gestures.touch(end + 5, []);
      const bearing = camera.deltas[camera.deltas.length - 1].momentum?.bearing;
      expect(bearing?.velocity).assertUndefined();
      expect(bearing?.snap?.spacing).assertEqual(360);
    });

    it("glides with the app's decay, and a pan from its release speed under the app's half-life", 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = {
        pan: { momentum: { halfLifeMs: 300, maxDistance: 500 } },
        zoom: { momentum: { stopSpeed: 0.1, maxSpeed: 4 } },
      };
      // 2000 vp/s.
      let end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.touch(end + 5, []);
      const pan = camera.deltas[camera.deltas.length - 1].momentum?.pan;
      expectNear(pan?.velocity?.y ?? NaN, 2000, 1e-6);
      expect(pan?.decay?.halfLifeMs).assertEqual(300);
      expect(pan?.decay?.maxDistance).assertEqual(500);
      // ArkUI's speeds stay.
      expectNear(pan?.decay?.minSpeed ?? NaN, 240 / camera.px, 1e-9);
      end = drag(gestures, 1000, [touch(1, 150, 300), touch(2, 250, 300)], [touch(1, 50, 300), touch(2, 350, 300)],
        20, 16);
      gestures.touch(end + 5, []);
      const zoom = camera.deltas[camera.deltas.length - 1].momentum?.zoom;
      expect(zoom?.velocity ?? 0).assertLarger(0);
      expect(JSON.stringify(zoom?.decay)).assertEqual('{"stopSpeed":0.1,"maxSpeed":4}');
    });

    it('snaps zoom and pitch only as the options ask, after a gesture that moved them', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const pinch = (start: number): void => {
        const end = drag(gestures, start, [touch(1, 150, 300), touch(2, 250, 300)],
          [touch(1, 50, 300), touch(2, 350, 300)], 20, 16);
        gestures.touch(end + 100, []);
      };
      const last = (): CameraDelta => camera.deltas[camera.deltas.length - 1];
      // Off by default.
      pinch(0);
      expect(last().momentum?.zoom?.snap).assertUndefined();
      expect(camera.ends).assertEqual(1);

      gestures.options = { zoom: { snap: { interval: 1 } }, pitch: { snap: { interval: 30, tolerance: 5, durationMs: 0 } } };
      pinch(1000);
      expect(JSON.stringify(last().momentum?.zoom?.snap)).assertEqual('{"spacing":1,"offset":0}');
      expect(last().momentum?.pitch?.snap).assertUndefined();
      // Two fingers up together pitch.
      const end = drag(gestures, 2000, [touch(1, 150, 400), touch(2, 250, 400)],
        [touch(1, 150, 250), touch(2, 250, 250)], 15, 40);
      gestures.touch(end + 100, []);
      expect(JSON.stringify(last().momentum?.pitch?.snap))
        .assertEqual('{"spacing":30,"offset":0,"tolerance":5,"durationMs":0}');
      expect(last().momentum?.zoom?.snap).assertUndefined();
      // A wheel's notch doesn't snap.
      gestures.axisUpdate(0, 15, false, false);
      gestures.axisEnded();
      expect(last().momentum?.zoom?.snap).assertUndefined();
    });

    it('stops momentum when a finger goes down', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.touch(end + 5, []);
      const glide = camera.deltas[camera.deltas.length - 1];
      gestures.touch(end + 20, [touch(2, 50, 50)]);
      expect(camera.ends).assertEqual(1);
      expect(camera.cancelled.includes(glide.animation?.transitionId ?? BigInt(-1))).assertTrue();
      // The glide's end, which comes later, doesn't end the gesture again.
      camera.endAnimation(glide);
      expect(camera.ends).assertEqual(1);
      expect(gestures.idle).assertTrue();
    });

    it('stops momentum when the wheel or a touchpad pinch takes over', 0, () => {
      for (const wheel of [true, false]) {
        const camera = new Recorder();
        const gestures = new MapGestures(camera);
        const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
        gestures.touch(end + 5, []);
        const glide = camera.deltas[camera.deltas.length - 1];
        if (wheel) {
          gestures.axisUpdate(0, -1, false, false);
        } else {
          gestures.touchpadPinch(1.5);
        }
        // The fling's gesture ends, then the new input starts its own.
        expect(camera.ends).assertEqual(1);
        expect(camera.starts).assertEqual(2);
        expect(camera.lastPhase()).assertEqual(GesturePhase.begin);
        expect(camera.cancelled.includes(glide.animation?.transitionId ?? BigInt(-1))).assertTrue();
        camera.endAnimation(glide);
        expect(camera.ends).assertEqual(1);
      }
    });

    it('leaves a fling alone when the wheel it ignores ends', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = { zoom: { enabled: false } };
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.touch(end + 5, []);
      gestures.axisUpdate(0, -1, false, false);
      gestures.axisEnded();
      expect(camera.ends).assertEqual(0);
      expect(camera.cancelled.length).assertEqual(0);
      camera.endAnimation();
      expect(camera.ends).assertEqual(1);
      expect(camera.starts).assertEqual(1);
    });

    it('stops a fling whose options change', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.touch(end + 5, []);
      gestures.options = { pan: { enabled: false } };
      expect(camera.ends).assertEqual(1);
      expect(camera.cancelled.length).assertEqual(1);
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
      gestures.options = { pan: { enabled: false } };
      gestures.touch(end + 5, []);
      expect(camera.ends).assertEqual(1);

      // A pinch's momentum waits for its last finger.
      const pinch = new Recorder();
      const pinching = new MapGestures(pinch);
      const last = drag(pinching, 0, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 50, 300), touch(2, 350, 300)], 20, 16);
      pinching.touch(last + 5, [touch(2, 350, 300)]);
      pinching.options = { zoom: { enabled: false } };
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

    it('zooms and rotates about the center while the target keeps it, and two fingers don\'t pan', 0, () => {
      const camera = new Recorder();
      camera.keeps = true;
      const gestures = new MapGestures(camera);
      // A pinch whose fingers drift down and to the side, which pans after 4 vp.
      let end = drag(gestures, 0, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 70, 360), touch(2, 370, 360)], 20, 16);
      gestures.touch(end + 100, []);
      expect(camera.zoom()).assertLarger(1);
      expect(camera.offsetX()).assertEqual(0);
      expect(camera.offsetY()).assertEqual(0);
      expect(camera.deltas.every((d: CameraDelta) => d.anchor === undefined)).assertTrue();

      const twisted = camera.deltas.length;
      end = twist(gestures, 100, 60, 20, end + 1000);
      gestures.touch(end + 100, []);
      expect(camera.bearing()).assertLess(-40);
      expect(camera.offsetX(twisted)).assertEqual(0);
      expect(camera.deltas.every((d: CameraDelta) => d.anchor === undefined)).assertTrue();

      gestures.doubleTap(100, 100);
      expect(camera.deltas[camera.deltas.length - 1].scale).assertEqual(2);
      expect(camera.deltas[camera.deltas.length - 1].anchor).assertUndefined();

      // Once the target lets the center go, the fingers pan and anchor again.
      camera.keeps = false;
      const panned = camera.deltas.length;
      end = drag(gestures, end + 2000, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 70, 360), touch(2, 370, 360)], 20, 16);
      gestures.touch(end + 100, []);
      expect(camera.offsetY(panned)).assertLarger(0);
      expect(camera.deltas.slice(panned).some((d: CameraDelta) => d.anchor !== undefined)).assertTrue();
    });

    it('tells the target of a pan, a rotation, or a zoom before the gesture starts', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      let end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 200)], 10, 50);
      gestures.touch(end + 10, []);
      expect(camera.told.slice(0, 2).join()).assertEqual('pan,start');

      camera.told = [];
      end = twist(gestures, 100, 60, 20, end + 1000);
      gestures.touch(end + 100, []);
      expect(camera.told.slice(0, 2).join()).assertEqual('rotate,start');

      camera.told = [];
      gestures.doubleTap(100, 100);
      expect(camera.told.join()).assertEqual('zoom,start');

      camera.told = [];
      gestures.options = { wheel: WheelAction.PAN };
      gestures.axisUpdate(0, 15, false, false);
      expect(camera.told.join()).assertEqual('pan,start');
      gestures.dispose();
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
      // The map snaps it, if it's near north, and the gesture ends after.
      expect(camera.ends).assertEqual(0);
      camera.endAnimation();
      expect(camera.ends).assertEqual(1);
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

    it("doesn't fling the finger left behind by a pinch, which glides as the pinch", 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 100, 300), touch(2, 300, 300)], 10, 16);
      gestures.touch(end + 10, [touch(1, 100, 300)]);
      const lifted = camera.deltas.length;
      gestures.touch(end + 20, [touch(1, 103, 300)]);
      gestures.touch(end + 30, []);
      expect(camera.offsetX(lifted)).assertEqual(0);
      const momentum = camera.deltas[camera.deltas.length - 1].momentum;
      expect(momentum?.pan).assertUndefined();
      expect(momentum?.zoom?.velocity ?? 0).assertLarger(0);
      expect(momentum?.zoom?.anchor?.x).assertEqual(200);
      camera.endAnimation();
      expect(camera.ends).assertEqual(1);
    });

    it('moves only as the options allow', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = { rotate: { enabled: false }, zoom: { enabled: false } };
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
      gestures.options = { zoom: { enabled: false } };
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
          gestures.options = { pan: { enabled: false } };
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
      gestures.options = { zoom: { enabled: false } };
      gestures.touch(0, [touch(1, 200, 300)]);
      gestures.touch(80, []);
      expect(JSON.stringify(camera.long)).assertEqual('[false]');

      gestures.touch(1000, [touch(2, 100, 100)]);
      gestures.longPress();
      gestures.touch(1600, []);
      expect(JSON.stringify(camera.long)).assertEqual('[false,true]');
      expect(camera.clicks[1].x).assertEqual(100);

      gestures.mouse(MouseAction.Press, MouseButton.Right, 1700, 50, 60);
      gestures.mouse(MouseAction.Move, MouseButton.None, 1710, 52, 60);
      gestures.mouse(MouseAction.Release, MouseButton.Right, 1720, 52, 60);
      expect(JSON.stringify(camera.long)).assertEqual('[false,true,true]');
      // A long press after a drag isn't a click.
      drag(gestures, 2000, [touch(3, 200, 300)], [touch(3, 300, 300)], 5, 20);
      gestures.longPress();
      expect(camera.long.length).assertEqual(3);
    });

    it('has the map snap a rotation as it ends, and then ends the gesture', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      let end = twist(gestures, 100, 60, 20);
      gestures.touch(end + 100, []);
      // North alone by default.
      const snap = camera.deltas[camera.deltas.length - 1];
      expect(snap.gesturePhase).assertEqual(GesturePhase.end);
      expect(JSON.stringify(snap.momentum?.bearing?.snap)).assertEqual('{"spacing":360,"offset":0}');
      expect(camera.ends).assertEqual(0);
      expect(gestures.idle).assertFalse();
      camera.endAnimation();
      expect(camera.ends).assertEqual(1);
      expect(gestures.idle).assertTrue();
      expect(camera.starts).assertEqual(1);

      // The options' bearings. A touch during the snap ends the gesture
      // first, and so does the app.
      for (const app of [false, true]) {
        const other = new Recorder();
        const snapping = new MapGestures(other);
        snapping.options = { rotate: { snap: { interval: 90, offset: 10 } } };
        end = twist(snapping, 100, 60, 20);
        snapping.touch(end + 100, []);
        const ease = other.deltas[other.deltas.length - 1];
        expect(JSON.stringify(ease.momentum?.bearing?.snap)).assertEqual('{"spacing":90,"offset":10}');
        if (app) {
          snapping.stop();
        } else {
          snapping.touch(end + 200, [touch(1, 100, 100)]);
        }
        expect(other.ends).assertEqual(1);
        // The snap stops where it is.
        expect(other.cancelled.includes(ease.animation?.transitionId ?? BigInt(-1))).assertTrue();
        other.endAnimation(ease);
        expect(other.ends).assertEqual(1);
        snapping.dispose();
      }

      // Without snapping, a rotation ends at once.
      const still = new Recorder();
      const unsnapped = new MapGestures(still);
      unsnapped.options = { rotate: { snap: { interval: 0 } } };
      end = twist(unsnapped, 100, 60, 20);
      unsnapped.touch(end + 100, []);
      expect(still.deltas[still.deltas.length - 1].momentum?.bearing?.snap).assertUndefined();
      expect(still.ends).assertEqual(1);
    });

    it("reports the rotation's invalid values, and takes their defaults", 0, () => {
      const camera = new Recorder();
      camera.initialBearing = 30;
      const gestures = new MapGestures(camera);
      const options = (): InteractionOptions => ({
        pan: { momentum: { halfLifeMs: 0 } },
        zoom: { snap: { interval: 1, tolerance: -1 } },
        rotate: { snap: { interval: NaN }, haptics: { interval: -90, offset: Infinity } },
      });
      gestures.options = options();
      expect(JSON.stringify(camera.errors)).assertEqual(JSON.stringify([
        'interactions.pan.momentum.halfLifeMs must be finite and positive: 0',
        'interactions.zoom.snap.tolerance must be finite and not negative: -1',
        'interactions.rotate.snap.interval must be finite and not negative: NaN',
        'interactions.rotate.haptics.interval must be finite and not negative: -90',
        'interactions.rotate.haptics.offset must be finite: Infinity',
      ]));
      // The same options again, as `build()` writes them, report nothing new.
      gestures.options = options();
      expect(camera.errors.length).assertEqual(5);
      // The twist from 30 to -18 ticks at north, and snaps there.
      let end = twist(gestures, 100, 60, 20);
      gestures.touch(end + 100, []);
      expect(camera.ticks).assertEqual(1);
      expect(JSON.stringify(camera.deltas[camera.deltas.length - 1].momentum?.bearing?.snap))
        .assertEqual('{"spacing":360,"offset":0}');
      // A fling of 2000 vp/s at 3 px per vp glides as ArkUI's.
      end = drag(gestures, 1000, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.touch(end + 5, []);
      const pan = camera.deltas[camera.deltas.length - 1].momentum?.pan;
      expectNear(pan?.velocity?.y ?? NaN, 3000, 1e-6);
      expectNear(pan?.decay?.halfLifeMs ?? NaN, Math.LN2 / (4.2 * 0.75) * 1000, 1e-6);
    });

    it("runs each movement's onStart as it starts", 0, () => {
      const counts: number[] = [0, 0, 0, 0];
      const options: InteractionOptions = {
        pan: {
          onStart: () => {
            counts[0]++;
          },
        },
        zoom: {
          onStart: () => {
            counts[1]++;
          },
        },
        rotate: {
          onStart: () => {
            counts[2]++;
          },
        },
        pitch: {
          onStart: () => {
            counts[3]++;
          },
        },
      };
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = options;
      let end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 200)], 10, 50);
      gestures.touch(end + 10, []);
      expect(counts).assertDeepEquals([1, 0, 0, 0]);
      // A pinch zooms, and its midpoint's drift isn't a pan.
      end = drag(gestures, 1000, [touch(1, 150, 300), touch(2, 250, 300)],
        [touch(1, 50, 300), touch(2, 350, 300)], 20, 16);
      gestures.touch(end + 100, []);
      expect(counts).assertDeepEquals([1, 1, 0, 0]);
      end = twist(gestures, 100, 60, 20, 2000);
      gestures.touch(end + 100, []);
      expect(counts).assertDeepEquals([1, 1, 1, 0]);
      end = drag(gestures, 3000, [touch(1, 150, 400), touch(2, 250, 400)],
        [touch(1, 150, 250), touch(2, 250, 250)], 15, 40);
      gestures.touch(end + 100, []);
      expect(counts[3]).assertEqual(1);
      // Each wheel update of one gesture, and a double tap.
      const zooms = counts[1];
      gestures.axisUpdate(0, 15, false, false);
      gestures.axisUpdate(0, 15, false, false);
      gestures.axisEnded();
      gestures.doubleTap(10, 10);
      expect(counts[1]).assertEqual(zooms + 2);
      // A movement that's off doesn't start.
      gestures.options = { zoom: options.zoom, pan: { enabled: false, onStart: options.pan?.onStart } };
      const pans = counts[0];
      end = drag(gestures, 5000, [touch(1, 100, 100)], [touch(1, 100, 200)], 10, 50);
      gestures.touch(end + 10, []);
      expect(counts[0]).assertEqual(pans);
    });

    it("doesn't start a movement until it moves the camera", 0, async () => {
      let pans = 0;
      let zooms = 0;
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = {
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
      // A pinch starts, then the fingers move together without changing their
      // span, so the zoom that was recognized doesn't scale.
      gestures.touch(0, [touch(1, 150, 300), touch(2, 250, 300)]);
      gestures.touch(16, [touch(1, 149, 300), touch(2, 251, 300)]);
      gestures.claim();
      gestures.touch(32, [touch(1, 139, 300), touch(2, 261, 300)]);
      gestures.touch(48, [touch(1, 149, 300), touch(2, 271, 300)]);
      gestures.touch(200, []);
      expect(zooms).assertEqual(0);

      // Opposite keys cancel, so only the zoom key starts a movement.
      gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, false);
      gestures.keyDown(KeyCode.KEYCODE_DPAD_RIGHT, false);
      gestures.keyDown(KeyCode.KEYCODE_EQUALS, false);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_LEFT);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_RIGHT);
      gestures.keyUp(KeyCode.KEYCODE_EQUALS);
      await until('the keys finish their steps', () => camera.ends === 2);
      expect(zooms).assertEqual(1);
      expect(pans).assertEqual(0);
    });

    it("runs onStart again as a movement starts again in one touch sequence", 0, () => {
      let pans = 0;
      let rotations = 0;
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = {
        pan: {
          onStart: () => {
            pans++;
          },
        },
        rotate: {
          onStart: () => {
            rotations++;
          },
        },
      };
      // One finger pans.
      gestures.touch(0, [touch(1, 70, 300)]);
      gestures.touch(16, [touch(1, 80, 300)]);
      gestures.claim();
      gestures.touch(32, [touch(1, 90, 300)]);
      gestures.touch(48, [touch(1, 100, 300)]);
      expect(pans).assertEqual(1);
      // A second finger goes down, and the pair twists about its midpoint.
      let time = 64;
      gestures.touch(time, onCircle(100, 0));
      for (let i = 1; i <= 20; i++) {
        time += 16;
        gestures.touch(time, onCircle(100, i * 3));
      }
      expect(rotations).assertEqual(1);
      expect(pans).assertEqual(1);
      // The second finger lifts, and the one left pans again.
      const left = onCircle(100, 60)[0];
      time += 16;
      gestures.touch(time, [left]);
      for (let i = 1; i <= 5; i++) {
        time += 16;
        gestures.touch(time, [touch(1, left.x + i * 10, left.y)]);
      }
      gestures.touch(time + 100, []);
      expect(pans).assertEqual(2);
      expect(rotations).assertEqual(1);
      camera.endAnimation();
      expect(camera.starts).assertEqual(1);
      expect(camera.ends).assertEqual(1);
    });

    it("runs the other movements' onStart when one throws, and ends the gesture", 0, async () => {
      let zooms = 0;
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = {
        pan: {
          onStart: () => {
            throw new Error('the app handler failed');
          },
        },
        zoom: {
          onStart: () => {
            zooms++;
          },
        },
      };
      // Keys that pan and zoom start both movements in one frame.
      gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, false);
      gestures.keyDown(KeyCode.KEYCODE_EQUALS, false);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_LEFT);
      gestures.keyUp(KeyCode.KEYCODE_EQUALS);
      await until('the keys finish their steps', () => camera.ends === 1);
      expect(zooms).assertEqual(1);
      expectNear(camera.offsetX(), 100, 1e-6);
      expectNear(camera.zoom(), 1, 1e-6);
      expect(camera.starts).assertEqual(1);
    });

    it('keeps momentum when the options change but the movements stay on', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const end = drag(gestures, 0, [touch(1, 100, 100)], [touch(1, 100, 300)], 10, 10);
      gestures.touch(end + 5, []);
      gestures.options = { wheel: WheelAction.PAN };
      expect(camera.ends).assertEqual(0);
      expect(camera.cancelled.length).assertEqual(0);
    });

    it('zooms with the wheel, and pans with Ctrl', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      // One notch down zooms out a quarter level.
      gestures.axisUpdate(0, 15, false, false);
      expectNear(camera.zoom(), -0.25, 1e-9);
      expect(camera.offsetY()).assertEqual(0);
      gestures.axisUpdate(5, 15, true, false);
      expectNear(camera.offsetY(), -60, 1e-9);
      expectNear(camera.offsetX(), -20, 1e-9);
      expectNear(camera.zoom(), -0.25, 1e-9);
    });

    it('pans with the wheel in pan mode, and zooms with Ctrl', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = { wheel: WheelAction.PAN };
      // A notch down shows what's below: the content moves up.
      gestures.axisUpdate(0, 15, false, false);
      expectNear(camera.offsetY(), -60, 1e-9);
      expect(camera.zoom()).assertEqual(0);
      gestures.axisUpdate(0, -15, true, false);
      expectNear(camera.zoom(), 0.25, 1e-9);
      expectNear(camera.offsetY(), -60, 1e-9);
    });

    it('pans with a touchpad swipe, by its vp, and zooms with Ctrl', 0, () => {
      for (const wheel of [WheelAction.ZOOM, WheelAction.PAN]) {
        const camera = new Recorder();
        const gestures = new MapGestures(camera);
        gestures.options = { wheel: wheel };
        gestures.axisUpdate(10, 20, false, true);
        expectNear(camera.offsetX(), -10, 1e-9);
        expectNear(camera.offsetY(), -20, 1e-9);
        expect(camera.zoom()).assertEqual(0);
        gestures.axisUpdate(0, -60, true, true);
        expectNear(camera.zoom(), 1, 1e-9);
        gestures.axisEnded();
        expect(camera.ends).assertEqual(1);
      }
    });

    it('pans with the touchpad through the pan gesture when its axis events are like the wheel', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.touchpadPan(10, -20, false);
      gestures.touchpadPan(30, -50, false);
      // The axis events of the swipe don't zoom.
      gestures.axisUpdate(0, 15, false, false);
      expectNear(camera.offsetX(), 30, 1e-9);
      expectNear(camera.offsetY(), -50, 1e-9);
      expect(camera.zoom()).assertEqual(0);
      gestures.onPanEnd();
      expect(camera.ends).assertEqual(1);
      // After it, the wheel zooms again.
      gestures.axisUpdate(0, 15, false, false);
      expectNear(camera.zoom(), -0.25, 1e-9);

      // Once axis events say they're from the touchpad, they pan alone.
      const other = new Recorder();
      const reporting = new MapGestures(other);
      reporting.axisUpdate(0, 20, false, true);
      reporting.touchpadPan(0, -20, false);
      expectNear(other.offsetY(), -20, 1e-9);
    });

    it('leaves the wheel and touchpad to a parent in cooperative mode, unless Ctrl is held', 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = { cooperative: true };
      gestures.axisUpdate(0, 15, false, false);
      gestures.axisUpdate(0, 15, false, true);
      expect(camera.deltas.length).assertEqual(0);
      // With Ctrl, the wheel zooms and the touchpad pans, as they do otherwise.
      gestures.axisUpdate(0, 15, true, false);
      expectNear(camera.zoom(), -0.25, 1e-9);
      gestures.axisUpdate(0, 15, true, true);
      expectNear(camera.offsetY(), -15, 1e-9);
    });

    it('moves a held key every frame, a step each 300 ms, and ignores its repeats', 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      const down = Date.now();
      expect(gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, false)).assertTrue();
      for (let i = 0; i < 5; i++) {
        await frames(2);
        // The system's repeats.
        expect(gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, false)).assertTrue();
      }
      await until('the key moves two steps', () => camera.offsetX() >= 200);
      const moves = camera.deltas.length;
      expect(gestures.keyUp(KeyCode.KEYCODE_DPAD_LEFT)).assertTrue();
      const held = Date.now() - down;
      const panned = camera.offsetX();
      // Many small moves, at 100 vp each 300 ms, less the first frame.
      expect(moves).assertLarger(10);
      expect(panned).assertLessOrEqual(held / 300 * 100 + 1);
      expect(panned).assertLarger((held - 100) / 300 * 100);
      // Past its first step, the key stops as it's released.
      await frames(5);
      expect(camera.offsetX()).assertEqual(panned);
      expect(camera.starts).assertEqual(1);
      expect(camera.ends).assertEqual(1);
      expect(camera.lastPhase()).assertEqual(GesturePhase.end);
    });

    it('finishes the step of a key released early', 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.keyDown(KeyCode.KEYCODE_EQUALS, false);
      gestures.keyUp(KeyCode.KEYCODE_EQUALS);
      await until('the step ends', () => camera.ends === 1);
      expectNear(camera.zoom(), 1, 1e-9);
      // Two taps make two steps.
      gestures.keyDown(KeyCode.KEYCODE_DPAD_UP, false);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_UP);
      await frames(3);
      gestures.keyDown(KeyCode.KEYCODE_DPAD_UP, false);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_UP);
      await until('the steps end', () => camera.ends === 2);
      expectNear(camera.offsetY(), 200, 1e-6);
    });

    it('finishes a step before the same key moves another way with Shift', 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, false);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_LEFT);
      gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, true);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_LEFT);
      // The rotation's end goes to the map to snap.
      await until('the steps end', () => camera.phases().includes(GesturePhase.end));
      camera.endAnimation();
      expect(camera.ends).assertEqual(1);
      expectNear(camera.offsetX(), 100, 1e-6);
      expectNear(camera.bearing(), 15, 1e-6);
    });

    it('adds the keys that are held, so opposite ones cancel', 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, false);
      gestures.keyDown(KeyCode.KEYCODE_DPAD_RIGHT, false);
      gestures.keyDown(KeyCode.KEYCODE_DPAD_UP, false);
      await until('the keys move a step', () => camera.offsetY() >= 100);
      expect(camera.offsetX()).assertEqual(0);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_LEFT);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_RIGHT);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_UP);
      expect(camera.ends).assertEqual(1);
      // Shift and the arrows rotate and pitch.
      gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, true);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_LEFT);
      gestures.keyDown(KeyCode.KEYCODE_DPAD_DOWN, true);
      gestures.keyUp(KeyCode.KEYCODE_DPAD_DOWN);
      await until('the steps end', () => camera.lastPhase() === GesturePhase.end && camera.pitch() < 0);
      camera.endAnimation();
      expect(camera.ends).assertEqual(2);
      expectNear(camera.bearing(), 15, 1e-6);
      expectNear(camera.pitch(), -10, 1e-6);
      // Turning with keys doesn't tick.
      expect(camera.ticks).assertEqual(0);
    });

    it('stops held keys when other input takes over, until they go up', 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, false);
      await until('the key moves', () => camera.offsetX() > 0);
      gestures.touch(0, [touch(1, 100, 100)]);
      expect(camera.ends).assertEqual(1);
      const panned = camera.offsetX();
      // Its repeats don't start it again.
      expect(gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, false)).assertTrue();
      await frames(5);
      expect(camera.offsetX()).assertEqual(panned);
      expect(gestures.keyUp(KeyCode.KEYCODE_DPAD_LEFT)).assertTrue();
      gestures.touch(10, []);

      // Losing focus stops them too.
      gestures.keyDown(KeyCode.KEYCODE_DPAD_RIGHT, false);
      await until('the key moves', () => camera.ends === 1 && camera.offsetX() < panned);
      gestures.blur();
      expect(camera.ends).assertEqual(2);
      expect(gestures.keyUp(KeyCode.KEYCODE_DPAD_RIGHT)).assertFalse();
    });

    it("doesn't take the keys of a movement that's off", 0, () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.options = { pan: { enabled: false }, rotate: { enabled: false } };
      expect(gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, false)).assertFalse();
      expect(gestures.keyDown(KeyCode.KEYCODE_DPAD_LEFT, true)).assertFalse();
      expect(gestures.keyDown(KeyCode.KEYCODE_A, false)).assertFalse();
      expect(gestures.keyDown(KeyCode.KEYCODE_DPAD_UP, true)).assertTrue();
      gestures.dispose();
    });

    it('rotates and pitches with a right-button drag past the slop, without momentum', 0, async () => {
      const camera = new Recorder();
      const gestures = new MapGestures(camera);
      gestures.mouse(MouseAction.Press, MouseButton.Right, 0, 100, 100);
      gestures.mouse(MouseAction.Move, MouseButton.Right, 10, 108, 100);
      expect(camera.deltas.length).assertEqual(0);
      // Past the slop; it moves from the next event.
      gestures.mouse(MouseAction.Move, MouseButton.Right, 20, 120, 100);
      expect(camera.deltas.length).assertEqual(0);
      gestures.mouse(MouseAction.Move, MouseButton.Right, 30, 170, 100);
      gestures.mouse(MouseAction.Move, MouseButton.Right, 40, 170, 80);
      expectNear(camera.bearing(), 40, 1e-9);
      expectNear(camera.pitch(), 10, 1e-9);
      gestures.mouse(MouseAction.Release, MouseButton.Right, 50, 170, 80);
      // A rotation, whose end the map snaps.
      expect(camera.ends).assertEqual(0);
      camera.endAnimation();
      expect(camera.ends).assertEqual(1);
      const count = camera.deltas.length;

      // The left button drags through touches, and pitch alone needs no rotate.
      gestures.mouse(MouseAction.Press, MouseButton.Left, 100, 100, 100);
      gestures.mouse(MouseAction.Move, MouseButton.Left, 110, 200, 200);
      gestures.mouse(MouseAction.Move, MouseButton.Left, 120, 300, 300);
      expect(camera.deltas.length).assertEqual(count);
      gestures.mouse(MouseAction.Release, MouseButton.Left, 130, 300, 300);
      gestures.options = { rotate: { enabled: false } };
      gestures.mouse(MouseAction.Press, MouseButton.Right, 200, 100, 100);
      gestures.mouse(MouseAction.Move, MouseButton.Right, 210, 150, 50);
      gestures.mouse(MouseAction.Move, MouseButton.Right, 220, 200, 0);
      gestures.mouse(MouseAction.Release, MouseButton.Right, 230, 200, 0);
      expectNear(camera.bearing(), 40, 1e-9);
      expectNear(camera.pitch(), 35, 1e-9);
      expect(camera.ends).assertEqual(2);
    });

    it('ticks as a twist or a right-button drag crosses a haptic bearing', 0, () => {
      // A twist from 30 degrees turns the map 48 degrees back, across north.
      const camera = new Recorder();
      camera.initialBearing = 30;
      const gestures = new MapGestures(camera);
      let end = twist(gestures, 100, 60, 20);
      gestures.touch(end + 100, []);
      expect(camera.ticks).assertEqual(1);

      // With the ticks off, it doesn't.
      const silent = new Recorder();
      silent.initialBearing = 30;
      const quiet = new MapGestures(silent);
      quiet.options = { rotate: { haptics: { interval: 0 } } };
      end = twist(quiet, 100, 60, 20);
      quiet.touch(end + 100, []);
      expect(silent.ticks).assertEqual(0);

      // Starting at a notch is silent, and each crossing of one, every 30
      // degrees from 10, ticks.
      const dragged = new Recorder();
      dragged.initialBearing = 10;
      const dragging = new MapGestures(dragged);
      dragging.options = { rotate: { haptics: { interval: 30, offset: 10 } } };
      dragging.mouse(MouseAction.Press, MouseButton.Right, 0, 100, 100);
      dragging.mouse(MouseAction.Move, MouseButton.Right, 100, 120, 100);
      // 0.8 degrees per vp: to 30, 50, then back to 2.
      dragging.mouse(MouseAction.Move, MouseButton.Right, 200, 145, 100);
      expect(dragged.ticks).assertEqual(0);
      dragging.mouse(MouseAction.Move, MouseButton.Right, 300, 170, 100);
      expect(dragged.ticks).assertEqual(1);
      dragging.mouse(MouseAction.Move, MouseButton.Right, 400, 110, 100);
      expect(dragged.ticks).assertEqual(2);
      // A tick too soon after the last is dropped.
      dragging.mouse(MouseAction.Move, MouseButton.Right, 410, 150, 100);
      expect(dragged.ticks).assertEqual(2);
    });

    it('plays its tick silently without the VIBRATE permission', 0, async () => {
      // The test app doesn't declare ohos.permission.VIBRATE, so the vibrator
      // refuses with 201, and the tick resolves with the refusal.
      const error = await playTick();
      expect(error?.code).assertEqual(201);
    });
  });
}
