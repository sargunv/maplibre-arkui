// Gestures and other input that move a map's camera or click it.
//
// ArkUI's recognizers, which MapLibreMap binds, decide whether the map owns a
// touch: against a parent such as a Scroll, and against content above the map.
// The raw touches decide how the camera moves, after a claim, as MapLibre
// Compose and MapLibre GL JS recognize them. Distances are in vp, which are the
// map's logical pixels, and times in milliseconds.

import displaySync from '@ohos.graphics.displaySync';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { CameraDelta, GesturePhase, ScreenPoint } from '@maplibre/native-ffi';

/**
 * Which gestures move the map. Each defaults to on, except `cooperative`.
 * Clicks reach the map's handlers whichever are on.
 *
 * ```ets
 * MapLibreMap({ controller: this.map, style: STYLE, gestures: { rotate: false, pitch: false } })
 * ```
 */
export interface MapGestureOptions {
  /** Drag with one finger or the mouse, or two fingers, to move the map. */
  pan?: boolean;
  /**
   * Pinch, double tap, two-finger tap, wheel, and keys, and double tap and
   * drag while `pan` is on.
   */
  zoom?: boolean;
  /** Twist two fingers. A rotation that ends near north snaps to it. */
  rotate?: boolean;
  /** Drag two fingers up or down together. */
  pitch?: boolean;
  /**
   * Leave one-finger drags and the plain wheel to a scrolling parent, so a
   * map in a Scroll or List moves only with two fingers or Ctrl and the wheel.
   */
  cooperative?: boolean;
}

/** A touch that is down, in the map's vp. */
export interface TouchPoint {
  id: number;
  x: number;
  y: number;
}

/** What gestures move and tell. The map implements it over its FFI map. */
export interface GestureTarget {
  applyCameraDelta(delta: CameraDelta): void;
  /** The user clicked at `point`: a tap, or a long press or right click if `long`. */
  clicked(point: ScreenPoint, long: boolean): void;
  /** The user started to move the camera. */
  gestureStarted(): void;
  /** The camera stopped moving from the user's input. */
  gestureEnded(rotated: boolean): void;
}

// Thresholds, after MapLibre Compose's GestureMath, which follows MapLibre
// Android and GL JS.
const PAIR_PAN_SLOP = 4;
// A change in the distance between two fingers that starts a pinch, and the
// larger one while they rotate. A slow change doesn't (startsZoom).
const ZOOM_SLOP = 3.5;
const ZOOM_SLOP_WHILE_ROTATING = 37.5;
// Degrees that start a rotation, and the arc that does while pinching, which
// keeps a pinch from rotating as the fingers close. A fast turn has to go
// further (startsRotation).
const ROTATE_SLOP = 3;
const ROTATE_ARC_WHILE_ZOOMING = 25;
// Two fingers that move this far up or down together, side by side, pitch.
const SHOVE_SLOP = 16;
const SHOVE_MAX_ANGLE = 45;
const PITCH_PER_VP = -0.3;
// Closer fingers (6 mm) give unstable scale and angle.
const MIN_SPAN = 37.8;
// A second press this soon and close after a tap is a double tap, as ArkUI's
// tap gesture finds it, and a drag from it zooms: four levels per map height,
// and dragging down zooms in. While zoom is on, a tap clicks once this long
// passes without that press.
const QUICK_ZOOM_MS = 300;
const QUICK_ZOOM_SLOP = 60;
const QUICK_ZOOM_LEVELS = 4;
// A tap, and each tap of a double tap, may move this far.
export const TAP_SLOP = 10;
// Momentum on release.
const VELOCITY_WINDOW_MS = 100;
const FLING_MIN_SPEED = 250;
const FLING_STEP = 16;
const TRANSFORM_MOMENTUM_MS = 600;
const MAX_ZOOM_MOMENTUM = 2.5;
// A rotation that ends within this of north snaps to it.
const BEARING_SNAP = 7;
// Taps, keys, and the snap animate this long.
export const GESTURE_ANIMATION_MS = 300;
// Zoom levels per unit of the wheel's axis value, 15 to a notch.
const WHEEL_LEVELS_PER_UNIT = 1 / 60;
const KEY_PAN = 100;
const KEY_ROTATE = 15;
const KEY_PITCH = 10;

/**
 * Turns a map's input into camera changes. `MapLibreMap` creates one and binds
 * its handlers to the map's ArkUI events and gestures; the claim callbacks come
 * from a `Pan`, `Pinch`, or `Rotation` gesture starting.
 */
export class MapGestures {
  private currentOptions: MapGestureOptions = {};
  /** The map's height, which a quick zoom measures its drag against. */
  height: number = 0;
  private readonly target: GestureTarget;

  get options(): MapGestureOptions {
    return this.currentOptions;
  }

  // Momentum, running or waiting for the last finger, may be for a motion
  // that's now off, so it goes.
  set options(options: MapGestureOptions) {
    this.currentOptions = options;
    this.staged = undefined;
    this.stop();
  }

  // The touches that are down, in the order they went down, and those where
  // recognition last restarted.
  private touches: TouchPoint[] = [];
  private origin: TouchPoint[] = [];
  private time: number = 0;
  // The touches at the last earlier time, which speeds are measured from:
  // ArkUI reports the fingers of one motion in separate events at one time.
  private earlier: TouchPoint[] = [];
  private earlierTime: number = 0;
  // An ArkUI gesture of the map won this touch sequence, so it moves the map.
  private claimed: boolean = false;
  // The components of the motion that move the camera.
  private panning: boolean = false;
  private zooming: boolean = false;
  private rotating: boolean = false;
  private pitching: boolean = false;
  private quickZooming: boolean = false;
  private zoomBase: number = 0;
  private minSpan: number = 0;
  // How far the fingers turned, and a quick zoom zoomed, for their velocity.
  private turned: number = 0;
  private quickZoom: number = 0;
  private anchor: ScreenPoint | undefined = undefined;
  private readonly panX: Velocity = new Velocity();
  private readonly panY: Velocity = new Velocity();
  private readonly zoom: Velocity = new Velocity();
  private readonly turn: Velocity = new Velocity();
  // Taps, for clicks and a double tap and drag.
  private down: TouchPoint | undefined = undefined;
  private tap: boolean = false;
  private lastTap: TouchPoint | undefined = undefined;
  private lastTapTime: number = -Infinity;
  private quickZoomReady: boolean = false;
  // A tap that clicks unless a second tap follows it, and the frame time when
  // it started to wait. The press of a second tap makes neither tap click.
  private pendingTap: TouchPoint | undefined = undefined;
  private pendingSince: number = -1;
  private secondTap: boolean = false;
  // Where the right mouse button went down.
  private rightDown: ScreenPoint | undefined = undefined;
  // The camera gesture: FFI's gesture phase is open, the app was told it
  // started, and whether it rotated the map.
  private phaseOpen: boolean = false;
  private moving: boolean = false;
  private rotated: boolean = false;
  // An animated step's number, so a step that something replaced doesn't end
  // the next one.
  private step: number = 0;
  private momentum: Momentum | undefined = undefined;
  private staged: Momentum | undefined = undefined;
  private stagedTime: number = 0;
  private momentumStart: number = -1;
  private frames: displaySync.DisplaySync | undefined = undefined;
  // Where the mouse or a touchpad pinch last was.
  private pointer: ScreenPoint | undefined = undefined;
  private pinchScale: number = 1;
  // Whether the wheel or a touchpad pinch opened the gesture that's under way,
  // so that their end doesn't end another input's gesture.
  private axisOwned: boolean = false;

  constructor(target: GestureTarget) {
    this.target = target;
  }

  /** Whether no input is moving the camera, by hand, momentum, or a step. */
  get idle(): boolean {
    return !this.moving;
  }

  /** Takes a touch event of the map. */
  onTouch(event: TouchEvent): void {
    if (event.type === TouchType.Cancel) {
      this.cancel();
      return;
    }
    this.height = event.target.area.height as number;
    const lifted = new Set<number>();
    if (event.type === TouchType.Up) {
      for (const touch of event.changedTouches) {
        lifted.add(touch.id);
      }
    }
    // Each event moves one finger. On HarmonyOS 6, the other fingers in
    // `touches` have window coordinates of 0, which makes their x and y wrong,
    // so they stay where their last change put them.
    const changed = new Map<number, TouchPoint>();
    for (const touch of event.changedTouches) {
      changed.set(touch.id, { id: touch.id, x: touch.x, y: touch.y });
    }
    const pressed: TouchPoint[] = [];
    for (const touch of event.touches) {
      if (!lifted.has(touch.id)) {
        pressed.push(changed.get(touch.id) ?? this.touches.find((p: TouchPoint) => p.id === touch.id) ??
          { id: touch.id, x: touch.x, y: touch.y });
      }
    }
    this.touch(event.timestamp / 1e6, inOrder(this.touches, pressed));
  }

  /**
   * Takes the touches that are down after an event, in the order they went
   * down. `onTouch` calls it; tests call it with made-up touches.
   */
  touch(time: number, pressed: TouchPoint[]): void {
    const previous = this.touches;
    if (time > this.time) {
      this.earlier = previous;
      this.earlierTime = this.time;
    }
    this.touches = pressed;
    this.time = time;
    if (previous.length === 0) {
      if (pressed.length > 0) {
        this.press(time, pressed[0]);
        this.restart(false);
      }
      return;
    }
    if (pressed.length === 0) {
      this.release(time, previous);
      return;
    }
    if (!sameTouches(previous, pressed)) {
      // Fingers rarely lift at once, so a pair's momentum waits for the last
      // one, unless the finger left behind pans.
      if (this.claimed && previous.length >= 2) {
        this.staged = this.plan(time);
        this.stagedTime = time;
      }
      this.tap = false;
      this.restart(false);
      return;
    }
    const down = this.down;
    if (down !== undefined && distance(down, pressed[0]) > TAP_SLOP) {
      this.tap = false;
    }
    if (!this.claimed) {
      return;
    }
    if (pressed.length === 1) {
      this.moveOne(time, previous[0], pressed[0]);
    } else {
      this.moveTwo(time, previous[0], previous[1], pressed[0], pressed[1]);
    }
  }

  /**
   * One of the map's ArkUI gestures won the touches that are down, so they
   * move the map from here on. Motion before the claim doesn't move it.
   */
  claim(): void {
    if (this.claimed || this.touches.length === 0) {
      return;
    }
    this.claimed = true;
    this.tap = false;
    this.restart(true);
  }

  /**
   * The map's long press gesture recognized the touch that's down. It's a
   * long click unless the touch moved, and its release doesn't click.
   */
  longPress(): void {
    if (!this.tap || this.claimed || this.touches.length !== 1) {
      return;
    }
    this.tap = false;
    this.target.clicked(this.touches[0], true);
  }

  /** Takes a mouse event of the map: a right click is a long click. */
  onMouse(event: MouseEvent): void {
    if (event.button === MouseButton.Right) {
      this.rightClick(event.action, { x: event.x, y: event.y });
    }
  }

  /** Takes the right mouse button going down or up at `point`. */
  rightClick(action: MouseAction, point: ScreenPoint): void {
    const down = this.rightDown;
    if (action === MouseAction.Press) {
      this.rightDown = point;
    } else if (action === MouseAction.Release && down !== undefined) {
      this.rightDown = undefined;
      if (distance(down, point) <= TAP_SLOP) {
        this.target.clicked(point, true);
      }
    }
  }

  /** Zooms in at a double tap. */
  doubleTap(x: number, y: number): void {
    if (this.options.zoom !== false) {
      this.animate({ scale: 2, anchor: { x: x, y: y } });
    }
  }

  /** Zooms out at a two-finger tap, about the point between the fingers. */
  twoFingerTap(x: number, y: number): void {
    if (this.options.zoom !== false) {
      this.animate({ scale: 0.5, anchor: { x: x, y: y } });
    }
  }

  /** Takes an axis event of the map: the mouse wheel zooms at the pointer. */
  onAxis(event: AxisEvent): void {
    this.pointer = { x: event.x, y: event.y };
    if (event.action === AxisAction.CANCEL) {
      this.pinchCancelled();
      return;
    }
    if (event.action === AxisAction.END) {
      this.axisEnded();
      return;
    }
    // The begin and end of a notch carry its value too, so only its updates
    // zoom.
    if (event.action === AxisAction.UPDATE) {
      this.wheel(event.getVerticalAxisValue(), event.getModifierKeyState?.(['Ctrl']) ?? false);
    }
  }

  /** Zooms at the pointer by a wheel update of `value`, with Ctrl held or not. */
  wheel(value: number, ctrl: boolean): void {
    if (value === 0 || this.options.zoom === false || (this.options.cooperative === true && !ctrl)) {
      return;
    }
    this.stop();
    this.move({ scale: Math.pow(2, -value * WHEEL_LEVELS_PER_UNIT), anchor: this.pointer });
    this.axisOwned = true;
  }

  /**
   * Takes the updates of the map's pinch gesture. Touch pinches come through
   * `onTouch`, so only a touchpad pinch moves the camera here.
   */
  onPinch(event: GestureEvent): void {
    if (event.sourceTool === SourceTool.TOUCHPAD) {
      this.touchpadPinch(event.scale);
    }
  }

  /** Zooms by a touchpad pinch that has reached `scale` since it started. */
  touchpadPinch(scale: number): void {
    if (this.options.zoom === false) {
      return;
    }
    this.stop();
    const step = scale / this.pinchScale;
    this.pinchScale = scale;
    // The event's pinch center is in window coordinates, and the axis events
    // of the pinch have the map's.
    this.move({ scale: step, anchor: this.pointer });
    this.axisOwned = true;
  }

  /** The map's pinch gesture ended. */
  onPinchEnd(event: GestureEvent): void {
    this.pinchScale = 1;
    if (event.sourceTool === SourceTool.TOUCHPAD) {
      this.axisEnded();
    }
  }

  /**
   * The map's pinch gesture was cancelled. A touchpad pinch ends here; a touch
   * pinch ends with its touches.
   */
  pinchCancelled(): void {
    this.pinchScale = 1;
    this.axisEnded();
  }

  /** The wheel or a touchpad pinch ended: so does the gesture they opened. */
  axisEnded(): void {
    if (this.axisOwned) {
      this.finish();
    }
  }

  /**
   * Takes a key event of the map. Arrows pan, Shift and the arrows rotate and
   * pitch, and plus and minus zoom. Returns whether it used the key.
   */
  onKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) {
      return false;
    }
    const shift = event.getModifierKeyState?.(['Shift']) ?? false;
    const options = this.options;
    const delta: CameraDelta = {};
    switch (event.keyCode) {
      case KeyCode.KEYCODE_DPAD_LEFT:
      case KeyCode.KEYCODE_DPAD_RIGHT: {
        const sign = event.keyCode === KeyCode.KEYCODE_DPAD_LEFT ? 1 : -1;
        if (shift && options.rotate !== false) {
          delta.bearing = sign * KEY_ROTATE;
        } else if (!shift && options.pan !== false) {
          delta.offset = { x: sign * KEY_PAN, y: 0 };
        }
        break;
      }
      case KeyCode.KEYCODE_DPAD_UP:
      case KeyCode.KEYCODE_DPAD_DOWN: {
        const sign = event.keyCode === KeyCode.KEYCODE_DPAD_UP ? 1 : -1;
        if (shift && options.pitch !== false) {
          delta.pitch = sign * KEY_PITCH;
        } else if (!shift && options.pan !== false) {
          delta.offset = { x: 0, y: sign * KEY_PAN };
        }
        break;
      }
      case KeyCode.KEYCODE_PLUS:
      case KeyCode.KEYCODE_EQUALS:
      case KeyCode.KEYCODE_NUMPAD_ADD:
      case KeyCode.KEYCODE_MINUS:
      case KeyCode.KEYCODE_NUMPAD_SUBTRACT:
        if (options.zoom !== false) {
          const zoomIn = event.keyCode !== KeyCode.KEYCODE_MINUS &&
            event.keyCode !== KeyCode.KEYCODE_NUMPAD_SUBTRACT;
          delta.scale = zoomIn ? 2 : 0.5;
        }
        break;
      default:
        return false;
    }
    if (delta.offset === undefined && delta.bearing === undefined && delta.pitch === undefined &&
      delta.scale === undefined) {
      return false;
    }
    this.animate(delta);
    return true;
  }

  /**
   * Stops momentum, and ends the gesture it belongs to. Fingers that are down
   * keep moving the camera.
   */
  stop(): void {
    // Momentum that waits for the last finger goes too.
    this.staged = undefined;
    if (this.momentum !== undefined) {
      this.stopMomentum();
      this.finish();
    }
  }

  /** The system took the touches back: end without momentum or a click. */
  cancel(): void {
    this.stopMomentum();
    this.touches = [];
    this.claimed = false;
    this.tap = false;
    this.lastTap = undefined;
    this.pendingTap = undefined;
    this.rightDown = undefined;
    this.idleFrames();
    if (this.phaseOpen) {
      this.phaseOpen = false;
      this.moving = false;
      this.target.applyCameraDelta({ gesturePhase: GesturePhase.cancel });
      this.target.gestureEnded(false);
    }
  }

  /** Stops input for good, as the map leaves, and ends what it started. */
  dispose(): void {
    this.cancel();
    this.endStep();
    this.frames?.off('frame');
    this.frames = undefined;
  }

  // The first touch of a sequence stops momentum. A press soon after a tap may
  // start a quick zoom, and is a second tap: the tap before it doesn't click.
  // Any other press lets that tap click at once.
  private press(time: number, point: TouchPoint): void {
    this.stopMomentum();
    this.finish();
    this.claimed = false;
    this.staged = undefined;
    this.down = point;
    this.tap = true;
    const lastTap = this.lastTap;
    this.quickZoomReady = lastTap !== undefined && time - this.lastTapTime < QUICK_ZOOM_MS &&
      distance(lastTap, point) < QUICK_ZOOM_SLOP;
    const pending = this.pendingTap;
    this.pendingTap = undefined;
    this.idleFrames();
    this.secondTap = pending !== undefined && this.quickZoomReady;
    if (pending !== undefined && !this.secondTap) {
      this.target.clicked(pending, false);
    }
  }

  // Recognition starts again from the touches that are down. Once the map
  // claims one touch, it pans at once, or quick-zooms after a tap when the
  // claim's motion is mostly vertical.
  private restart(claimed: boolean): void {
    const touches = this.touches;
    this.origin = touches;
    this.panning = false;
    this.zooming = false;
    this.rotating = false;
    this.pitching = false;
    this.quickZooming = false;
    this.panX.clear();
    this.panY.clear();
    this.zoom.clear();
    this.turn.clear();
    if (touches.length >= 2) {
      this.zoomBase = distance(touches[0], touches[1]);
      this.minSpan = this.zoomBase;
    } else if (claimed && this.down !== undefined) {
      const dx = Math.abs(touches[0].x - this.down.x);
      const dy = Math.abs(touches[0].y - this.down.y);
      this.quickZooming = this.quickZoomReady && this.options.zoom !== false && dy > dx;
      this.panning = !this.quickZooming;
      this.quickZoom = 0;
    }
  }

  private moveOne(time: number, before: TouchPoint, after: TouchPoint): void {
    if (this.quickZooming) {
      if (this.options.zoom !== false && this.height > 0) {
        const levels = (after.y - before.y) / this.height * QUICK_ZOOM_LEVELS;
        this.quickZoom += levels;
        this.zoom.add(time, this.quickZoom);
        this.anchor = undefined;
        this.move({ scale: Math.pow(2, levels) });
      }
      return;
    }
    if (!this.panning) {
      // After a second finger lifts, the one left pans once it moves.
      this.panning = distance(this.origin[0], after) >= PAIR_PAN_SLOP;
      if (this.panning) {
        this.staged = undefined;
      }
      return;
    }
    // In cooperative mode, one finger never pans, even the one left after a
    // pair.
    if (this.options.pan !== false && this.options.cooperative !== true) {
      this.panX.add(time, after.x);
      this.panY.add(time, after.y);
      this.move({ offset: { x: after.x - before.x, y: after.y - before.y } });
    }
  }

  // Two fingers pan, pinch, rotate, or pitch. Each starts once its motion since
  // the origin passes a threshold, and moves the camera from the next event,
  // so the threshold's motion doesn't jump the camera.
  private moveTwo(time: number, a0: TouchPoint, b0: TouchPoint, a: TouchPoint, b: TouchPoint): void {
    const options = this.options;
    const o1 = this.origin[0];
    const o2 = this.origin[1];
    const span0 = distance(a0, b0);
    const span = distance(a, b);
    const center = midpoint(a, b);
    this.minSpan = Math.min(this.minSpan, span);
    const stable = span0 >= MIN_SPAN && span >= MIN_SPAN;

    // Options can change mid-gesture, so each motion checks its option too.
    const delta: CameraDelta = {};
    if (this.panning && options.pan !== false) {
      const center0 = midpoint(a0, b0);
      delta.offset = { x: center.x - center0.x, y: center.y - center0.y };
      this.panX.add(time, center.x);
      this.panY.add(time, center.y);
    }
    if (this.zooming && stable && options.zoom !== false) {
      delta.scale = span / span0;
      delta.anchor = center;
      this.zoom.add(time, Math.log2(span));
    }
    if (this.rotating && stable && options.rotate !== false) {
      const turn = wrap(angle(a, b) - angle(a0, b0));
      this.turned -= turn;
      delta.bearing = -turn;
      delta.anchor = center;
      this.turn.add(time, this.turned);
    }
    if (this.pitching && options.pitch !== false) {
      delta.pitch = ((a.y - a0.y) + (b.y - b0.y)) / 2 * PITCH_PER_VP;
    }
    if (delta.anchor !== undefined) {
      this.anchor = delta.anchor;
      // ArkUI reports one finger at a time, so the midpoint moves by half that
      // finger's step even when the pair doesn't pan. Moving with it keeps the
      // content under both fingers; scaling or turning about it alone drifts.
      if (delta.offset === undefined && options.pan !== false) {
        const center0 = midpoint(a0, b0);
        delta.offset = { x: center.x - center0.x, y: center.y - center0.y };
      }
    }
    if (delta.offset !== undefined || delta.scale !== undefined || delta.bearing !== undefined ||
      delta.pitch !== undefined) {
      this.move(delta);
    }

    if (this.pitching) {
      return;
    }
    // Pitch wins when it starts with the others, but can't interrupt a pinch
    // or rotation, and it owns the fingers alone.
    if (!this.zooming && !this.rotating && options.pitch !== false && isShove(o1, o2, a, b)) {
      this.pitching = true;
      this.panning = false;
      return;
    }
    // Speeds are since the last earlier time, while the same two fingers were
    // down.
    const earlier = this.earlier;
    const known = sameTouches(earlier, this.touches);
    const elapsed = known ? time - this.earlierTime : 0;
    const e1 = known ? earlier[0] : a;
    const e2 = known ? earlier[1] : b;
    if (!this.zooming && options.zoom !== false) {
      const slop = this.rotating ? ZOOM_SLOP_WHILE_ROTATING : ZOOM_SLOP;
      if (startsZoom(span - this.zoomBase, span - distance(e1, e2), elapsed, wrap(angle(a, b) - angle(e1, e2)),
        slop)) {
        this.zooming = true;
        this.zoom.clear();
      }
    }
    if (!this.rotating && options.rotate !== false) {
      const slop = this.zooming ?
        Math.max(ROTATE_SLOP, ROTATE_ARC_WHILE_ZOOMING * 360 / (Math.PI * this.minSpan)) : ROTATE_SLOP;
      if (startsRotation(wrap(angle(a, b) - angle(o1, o2)), wrap(angle(a, b) - angle(e1, e2)), elapsed, slop)) {
        this.rotating = true;
        this.zoomBase = span;
        this.turn.clear();
      }
    }
    if (!this.panning && options.pan !== false &&
      distance(midpoint(o1, o2), center) >= PAIR_PAN_SLOP) {
      this.panning = true;
      this.panX.clear();
      this.panY.clear();
    }
  }

  // The last finger lifted: coast with the motion's momentum, then end. A tap
  // clicks, after the time for a second tap while zoom is on.
  private release(time: number, previous: TouchPoint[]): void {
    const claimed = this.claimed;
    this.claimed = false;
    if (this.tap && previous.length === 1) {
      this.lastTap = previous[0];
      this.lastTapTime = time;
      if (this.secondTap) {
        // A double tap, which zooms if anything.
      } else if (this.options.zoom === false) {
        this.target.clicked(previous[0], false);
      } else {
        this.pendingTap = previous[0];
        this.pendingSince = -1;
        this.runFrames();
      }
    } else {
      this.lastTap = undefined;
    }
    if (!claimed || !this.phaseOpen) {
      this.finish();
      return;
    }
    let momentum = this.plan(time);
    if (momentum === undefined && time - this.stagedTime <= VELOCITY_WINDOW_MS) {
      momentum = this.staged;
    }
    this.staged = undefined;
    if (momentum === undefined) {
      this.finish();
      return;
    }
    this.momentum = momentum;
    this.momentumStart = -1;
    this.runFrames();
  }

  // Frames drive momentum and the wait for a second tap.
  private runFrames(): void {
    if (this.frames === undefined) {
      const frames = displaySync.create();
      frames.on('frame', (info: displaySync.IntervalInfo) => this.frame(info.timestamp / 1e6));
      this.frames = frames;
    }
    this.frames.start();
  }

  private idleFrames(): void {
    if (this.momentum === undefined && this.pendingTap === undefined) {
      this.frames?.stop();
    }
  }

  private frame(time: number): void {
    this.coast(time);
    const pending = this.pendingTap;
    if (pending === undefined) {
      return;
    }
    if (this.pendingSince < 0) {
      this.pendingSince = time;
    }
    if (time - this.pendingSince >= QUICK_ZOOM_MS) {
      this.pendingTap = undefined;
      this.idleFrames();
      this.target.clicked(pending, false);
    }
  }

  // The momentum of the motion so far, if the last finger lifted at `time`.
  private plan(time: number): Momentum | undefined {
    const options = this.options;
    const pan = this.panning && options.pan !== false;
    const zoom = (this.zooming || this.quickZooming) && options.zoom !== false;
    const rotate = this.rotating && options.rotate !== false;
    return Momentum.plan(
      pan ? this.panX.perSecond(time) : 0,
      pan ? this.panY.perSecond(time) : 0,
      zoom ? this.zoom.perSecond(time) : 0,
      rotate ? this.turn.perSecond(time) : 0,
      this.anchor);
  }

  private coast(time: number): void {
    const momentum = this.momentum;
    if (momentum === undefined) {
      return;
    }
    if (this.momentumStart < 0) {
      this.momentumStart = time;
    }
    for (const delta of momentum.advance(time - this.momentumStart)) {
      this.move(delta);
    }
    if (momentum.done) {
      this.stopMomentum();
      this.finish();
    }
  }

  private stopMomentum(): void {
    if (this.momentum !== undefined) {
      this.momentum = undefined;
      this.idleFrames();
    }
  }

  // Moves the camera as part of the gesture, which starts with the first move.
  private move(delta: CameraDelta): void {
    if (!this.phaseOpen) {
      this.endStep();
      this.phaseOpen = true;
      this.moving = true;
      this.rotated = false;
      delta.gesturePhase = GesturePhase.begin;
    } else {
      delta.gesturePhase = GesturePhase.update;
    }
    if (delta.bearing !== undefined) {
      this.rotated = true;
    }
    this.target.applyCameraDelta(delta);
    // After the change, so a camera change that the app makes as the gesture
    // starts follows it.
    if (delta.gesturePhase === GesturePhase.begin) {
      this.target.gestureStarted();
    }
  }

  // Ends the gesture. A rotation that ends near north snaps to it.
  private finish(): void {
    this.axisOwned = false;
    if (this.phaseOpen) {
      this.phaseOpen = false;
      this.moving = false;
      this.target.applyCameraDelta({ gesturePhase: GesturePhase.end });
      this.target.gestureEnded(this.rotated && this.options.rotate !== false);
    }
  }

  // A step that animates on its own, such as a double tap's zoom. It ends when
  // the animation does, unless other input replaced it.
  private animate(delta: CameraDelta): void {
    this.stopMomentum();
    this.finish();
    this.endStep();
    const step = ++this.step;
    this.moving = true;
    delta.animation = {
      durationMs: GESTURE_ANIMATION_MS,
      endHandler: {
        callback: () => {
          if (this.step === step) {
            this.endStep();
          }
        },
      },
    };
    this.target.applyCameraDelta(delta);
    this.target.gestureStarted();
  }

  private endStep(): void {
    if (this.moving && !this.phaseOpen) {
      this.moving = false;
      this.target.gestureEnded(false);
    }
    this.step++;
  }
}

/**
 * The bearing that a rotation ending at `bearing` snaps to, or undefined when
 * it's too far from north.
 */
export function snapBearing(bearing: number): number | undefined {
  const fromNorth = wrap(bearing);
  return fromNorth !== 0 && Math.abs(fromNorth) <= BEARING_SNAP ? bearing - fromNorth : undefined;
}

/**
 * The camera's motion after a release, eased out over its duration. Pan alone
 * slows as a fling; zoom and rotation slow faster, and a pan with them follows
 * their curve so neither runs ahead. From MapLibre Compose's GestureMath.
 */
export class Momentum {
  readonly offsetX: number;
  readonly offsetY: number;
  readonly zoomLevels: number;
  readonly bearing: number;
  readonly anchor: ScreenPoint | undefined;
  readonly durationMs: number;
  readonly power: number;
  done: boolean = false;
  private progress: number = 0;

  constructor(offsetX: number, offsetY: number, zoomLevels: number, bearing: number,
    anchor: ScreenPoint | undefined, durationMs: number, power: number) {
    this.offsetX = offsetX;
    this.offsetY = offsetY;
    this.zoomLevels = zoomLevels;
    this.bearing = bearing;
    this.anchor = anchor;
    this.durationMs = durationMs;
    this.power = power;
  }

  /**
   * Plans the momentum of a release at these velocities, in vp, zoom levels,
   * and degrees of bearing per second, or none when it's too slow.
   */
  static plan(panX: number, panY: number, zoom: number, bearing: number,
    anchor: ScreenPoint | undefined): Momentum | undefined {
    const speed = Math.hypot(panX, panY);
    let offsetX = 0;
    let offsetY = 0;
    let panMs = 0;
    if (speed >= FLING_MIN_SPEED) {
      panMs = speed / 10.5 + 150;
      offsetX = panX * panMs * 0.28 / 1000;
      offsetY = panY * panMs * 0.28 / 1000;
    }
    // Quartic easing travels a quarter of the initial speed times the duration.
    const seconds = TRANSFORM_MOMENTUM_MS / 1000;
    const levels = Math.max(-MAX_ZOOM_MOMENTUM, Math.min(MAX_ZOOM_MOMENTUM, zoom * seconds / 4));
    const degrees = bearing * seconds / 4;
    const transform = Math.abs(levels) >= 0.01 || Math.abs(degrees) >= 0.1;
    if (!transform) {
      return panMs > 0 ? new Momentum(offsetX, offsetY, 0, 0, anchor, panMs, 2) : undefined;
    }
    // Keep the pan's initial speed on the quartic curve without adding travel.
    const scale = panMs > 0 ? Math.min(1, TRANSFORM_MOMENTUM_MS / panMs * 2 / 4) : 0;
    return new Momentum(offsetX * scale, offsetY * scale, levels, degrees, anchor,
      TRANSFORM_MOMENTUM_MS, 4);
  }

  /**
   * The camera changes from the last call to `elapsedMs` after the release. A
   * long frame's pan comes in steps of at most 16 vp, so a pitched map doesn't
   * project one large offset.
   */
  advance(elapsedMs: number): CameraDelta[] {
    const t = Math.min(1, Math.max(0, elapsedMs / this.durationMs));
    const progress = 1 - Math.pow(1 - t, this.power);
    const fraction = progress - this.progress;
    this.progress = progress;
    this.done = t >= 1;
    const deltas: CameraDelta[] = [];
    if (this.zoomLevels !== 0 || this.bearing !== 0) {
      const delta: CameraDelta = { anchor: this.anchor };
      if (this.zoomLevels !== 0) {
        delta.scale = Math.pow(2, this.zoomLevels * fraction);
      }
      if (this.bearing !== 0) {
        delta.bearing = this.bearing * fraction;
      }
      deltas.push(delta);
    }
    const x = this.offsetX * fraction;
    const y = this.offsetY * fraction;
    const steps = Math.ceil(Math.hypot(x, y) / FLING_STEP);
    for (let i = 0; i < steps; i++) {
      deltas.push({ offset: { x: x / steps, y: y / steps } });
    }
    return deltas;
  }
}

// A velocity from the samples of the last 100 ms before a release.
class Velocity {
  private times: number[] = [];
  private values: number[] = [];

  add(time: number, value: number): void {
    const last = this.times.length - 1;
    if (last >= 0 && time < this.times[last]) {
      this.clear();
    }
    this.times.push(time);
    this.values.push(value);
    if (this.times.length > 20) {
      this.times.shift();
      this.values.shift();
    }
  }

  clear(): void {
    this.times = [];
    this.values = [];
  }

  perSecond(now: number): number {
    let first = -1;
    for (let i = 0; i < this.times.length; i++) {
      if (now - this.times[i] <= VELOCITY_WINDOW_MS) {
        first = i;
        break;
      }
    }
    const last = this.times.length - 1;
    if (first < 0 || last <= first || this.times[last] <= this.times[first]) {
      return 0;
    }
    return (this.values[last] - this.values[first]) / (this.times[last] - this.times[first]) * 1000;
  }
}

// The touches in `pressed`, those that were down before first, in their order.
function inOrder(before: TouchPoint[], pressed: TouchPoint[]): TouchPoint[] {
  const ordered: TouchPoint[] = [];
  for (const old of before) {
    const touch = pressed.find((p: TouchPoint) => p.id === old.id);
    if (touch !== undefined) {
      ordered.push(touch);
    }
  }
  for (const touch of pressed) {
    if (!before.some((p: TouchPoint) => p.id === touch.id)) {
      ordered.push(touch);
    }
  }
  return ordered;
}

function sameTouches(a: TouchPoint[], b: TouchPoint[]): boolean {
  return a.length === b.length && a.every((touch: TouchPoint, i: number) => touch.id === b[i].id);
}

// Whether a change of span this large starts a pinch, given the change and
// turn since the last earlier time. Slow changes, as fingers that pan or twist
// together make, don't zoom, and a pinch that also turns has to be faster.
// Without an earlier time, there's no speed, so neither component starts.
function startsZoom(fromBase: number, sinceLast: number, elapsed: number, turn: number, slop: number): boolean {
  if (Math.abs(fromBase) < slop || elapsed <= 0) {
    return false;
  }
  const speed = Math.abs(sinceLast) / elapsed;
  return speed >= 0.3 && (Math.abs(turn) <= 0.4 || speed >= 0.45);
}

// Whether a turn this far from the origin starts a rotation, given the turn
// since the last earlier time. A fast turn has to go further, so fingers that move
// one at a time, as a pinch or a shove's often do, don't rotate.
function startsRotation(fromOrigin: number, sinceLast: number, elapsed: number, slop: number): boolean {
  const turned = Math.abs(fromOrigin);
  if (turned < slop || elapsed <= 0) {
    return false;
  }
  const speed = Math.abs(sinceLast) / elapsed;
  return speed >= 0.04 && !(speed > 0.07 && turned < 5) && !(speed > 0.15 && turned < 7) &&
    !(speed > 0.5 && turned < 15);
}

// Both fingers move mostly vertically, the same way, side by side.
function isShove(o1: TouchPoint, o2: TouchPoint, a: TouchPoint, b: TouchPoint): boolean {
  const dx1 = a.x - o1.x;
  const dy1 = a.y - o1.y;
  const dx2 = b.x - o2.x;
  const dy2 = b.y - o2.y;
  const fromHorizontal = Math.abs(wrap(angle(a, b)));
  return Math.abs((dy1 + dy2) / 2) >= SHOVE_SLOP && Math.abs(dy1) > Math.abs(dx1) &&
    Math.abs(dy2) > Math.abs(dx2) && (dy1 > 0) === (dy2 > 0) &&
    Math.min(fromHorizontal, 180 - fromHorizontal) <= SHOVE_MAX_ANGLE;
}

function distance(a: ScreenPoint, b: ScreenPoint): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function midpoint(a: ScreenPoint, b: ScreenPoint): ScreenPoint {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}

// The angle from a to b, in degrees.
function angle(a: ScreenPoint, b: ScreenPoint): number {
  return Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI;
}

// An angle in degrees, wrapped to [-180, 180).
function wrap(degrees: number): number {
  return (((degrees + 180) % 360) + 360) % 360 - 180;
}
