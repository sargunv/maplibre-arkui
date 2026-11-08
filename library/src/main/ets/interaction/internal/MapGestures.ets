// Gestures and other input that move a map's camera or click it.
//
// ArkUI's recognizers, which MaplibreMap binds, decide whether the map owns a
// touch: against a parent such as a Scroll, and against content above the map.
// The raw touches decide how the camera moves, after a claim, as MapLibre
// Compose and MapLibre GL JS recognize them. Distances are in vp, which are the
// map's logical pixels, and times in milliseconds.

import { CameraDelta, GestureMomentum, GesturePhase, ScreenPoint } from '@maplibre/native-ffi';
import displaySync from '@ohos.graphics.displaySync';
import { KeyCode } from '@ohos.multimodalInput.keyCode';

import { callHandler } from '../../runtime/internal/Log';
import { InteractionOptions, MovementOptions, WheelAction } from '../InteractionOptions';
import { BearingNotches, wrap } from './BearingNotches';
import { anchoredMomentum, checkGlides, Glides, panMomentum, Velocity, VELOCITY_WINDOW_MS } from './Momentum';

/** A touch that is down, in the map's vp. */
export interface TouchPoint {
  id: number;
  x: number;
  y: number;
}

/** What gestures move and tell. The map implements it over its FFI map. */
export interface GestureTarget {
  applyCameraDelta(delta: CameraDelta): void;
  /** Stops the camera animations of the deltas whose animation has `transitionId`. */
  cancelTransitions(transitionId: bigint): void;
  /** The user clicked at `point`: a tap, or a long press or right click if `long`. */
  clicked(point: ScreenPoint, long: boolean): void;
  /** The camera's bearing, as the map last applied the changes. */
  getBearing(): number;
  /** The display's px per vp, which ArkUI's fling thresholds are in. */
  density(): number;
  /** The user started to move the camera. */
  gestureStarted(): void;
  /**
   * The user's input pans, rotates, or zooms the camera, with the change it
   * just applied. Each comes before `gestureStarted()` and the movement's
   * `onStart`. Momentum and a snap, which FFI runs, don't call them.
   */
  panned(): void;
  rotated(): void;
  zoomed(): void;
  /**
   * Whether zoom and rotation keep the camera's center in place, as while the
   * camera follows the user's location.
   */
  keepsCenter(): boolean;
  /** The camera stopped moving from the user's input. */
  gestureEnded(): void;
  /** A rotation by the user crossed a haptic notch. */
  hapticTick(): void;
  /** An option was invalid. */
  fail(error: Error): void;
}

// Thresholds, after MapLibre Compose's GestureMath, which follows MapLibre
// Android and GL JS.
const PAIR_PAN_SLOP = 4;
// While zoom and rotation keep the center, two fingers pan only this far, so a
// pinch or twist that drifts doesn't pan, as MapLibre Android's location
// tracking does.
const PAIR_PAN_SLOP_KEEPING_CENTER = 400;
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
// Taps and a key's step take this long.
export const GESTURE_ANIMATION_MS = 300;
// The ID of the camera transitions of the animated steps and of a gesture's
// end, which stops them.
const STEP_TRANSITION = BigInt('0x6d61706c69627265');
// Zoom levels and vp per unit of the wheel's axis value, 15 to a notch. A
// touchpad's axis values are vp.
const WHEEL_LEVELS_PER_UNIT = 1 / 60;
const WHEEL_PAN_PER_UNIT = 4;
// A held key moves one step each GESTURE_ANIMATION_MS.
const KEY_PAN = 100;
const KEY_ROTATE = 15;
const KEY_PITCH = 10;
// A right-button drag turns and tilts this much per vp, as in MapLibre GL JS.
const MOUSE_BEARING_PER_VP = 0.8;
const MOUSE_PITCH_PER_VP = -0.5;

// The camera movements, as bits, for the options' onStart.
const PAN = 1;
const ZOOM = 2;
const ROTATE = 4;
const PITCH = 8;

// A key that moves the camera while it's held: per step, the offset, zoom
// levels, and degrees it moves. `progress` counts the steps it has moved. A
// key starts moving at the frame after the one that sees it (`fresh`); a
// released key finishes its first step; a dead key, which other input stopped,
// moves no more but stays until it's released.
class HeldKey {
  x: number = 0;
  y: number = 0;
  zoom: number = 0;
  bearing: number = 0;
  pitch: number = 0;
  movement: number = 0;
  progress: number = 0;
  fresh: boolean = true;
  released: boolean = false;
  dead: boolean = false;
}

/**
 * Turns a map's input into camera changes. `MaplibreMap` creates one and binds
 * its handlers to the map's ArkUI events and gestures; the claim callbacks come
 * from a `Pan`, `Pinch`, or `Rotation` gesture starting.
 */
export class MapGestures {
  private currentOptions: InteractionOptions = {};
  // The options' momentum, snaps, and haptics, as checked, and the options
  // that they come from.
  private glides: Glides = checkGlides({}, () => {});
  private glidesKey: string = glidesKey({});
  /** The map's height, which a quick zoom measures its drag against. */
  height: number = 0;
  private readonly target: GestureTarget;

  get options(): InteractionOptions {
    return this.currentOptions;
  }

  // Momentum, running or waiting for the last finger, and held keys may be for
  // a movement that's now off, so they go. Options that an app writes in
  // `build()` are a new value each time, so the rest carries on, and an
  // invalid value is reported once.
  set options(options: InteractionOptions) {
    const before = this.currentOptions;
    this.currentOptions = options;
    const key = glidesKey(options);
    if (key !== this.glidesKey) {
      this.glidesKey = key;
      this.glides = checkGlides(options, (error: Error) => this.target.fail(error));
      // A rotation under way ticks at the new bearings.
      this.notches = undefined;
    }
    if ((enabled(before.pan) && !enabled(options.pan)) || (enabled(before.zoom) && !enabled(options.zoom)) ||
      (enabled(before.rotate) && !enabled(options.rotate)) || (enabled(before.pitch) && !enabled(options.pitch))) {
      this.stop();
    }
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
  // How far the fingers turned and tilted, and a quick zoom zoomed, for their
  // velocity, and the point that the last zoom or rotation kept in place.
  private turned: number = 0;
  private tilted: number = 0;
  private quickZoom: number = 0;
  private anchor: ScreenPoint | undefined = undefined;
  private readonly panX: Velocity = new Velocity();
  private readonly panY: Velocity = new Velocity();
  private readonly zoom: Velocity = new Velocity();
  private readonly turn: Velocity = new Velocity();
  private readonly tilt: Velocity = new Velocity();
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
  // The camera gesture: FFI's gesture phase is open, the app was told it
  // started and not yet that it ended, the movements whose onStart ran, and
  // the movements that it made, which snap as it ends.
  private phaseOpen: boolean = false;
  private moving: boolean = false;
  private started: number = 0;
  private changed: number = 0;
  // The haptic notches of the rotation by the pointer that's under way.
  private notches: BearingNotches | undefined = undefined;
  // The number of the animated step or gesture end under way, so one that
  // something replaced doesn't end the next one.
  private step: number = 0;
  // The momentum of a pair as one of its fingers lifted, and when, which the
  // last finger's release takes while the fingers left haven't moved the map.
  private staged: GestureMomentum | undefined = undefined;
  private stagedTime: number = 0;
  // Frames run while held keys move the camera, and while a tap waits.
  private frames: displaySync.DisplaySync | undefined = undefined;
  private framesRunning: boolean = false;
  // Where the mouse or a touchpad pinch last was.
  private pointer: ScreenPoint | undefined = undefined;
  private pinchScale: number = 1;
  // Whether the wheel, the touchpad, or the keys opened the gesture that's
  // under way, so that their end doesn't end another input's gesture.
  private axisOwned: boolean = false;
  private keysOwned: boolean = false;
  // Whether the axis events have said a touchpad made them. Until they do, a
  // touchpad swipe pans through the pan gesture, which is under way while
  // `touchpadPanning` is set, and the axis events that it makes are left out.
  private axisReportsTouchpad: boolean = false;
  private touchpadPanning: boolean = false;
  private panOffset: ScreenPoint = { x: 0, y: 0 };
  // A drag with the right mouse button: where it went down, where it last was,
  // and whether it has gone far enough to move the camera.
  private rightDown: ScreenPoint | undefined = undefined;
  private rightLast: ScreenPoint = { x: 0, y: 0 };
  private rightDragging: boolean = false;
  // The keys that are held, or finishing their step, by key code, and the
  // time of the last frame they moved in.
  private readonly keys: Map<number, HeldKey> = new Map<number, HeldKey>();
  private keyTime: number = -1;
  // Released keys that finish their step after the key went down again with
  // another movement take negative IDs from this count, apart from key codes.
  private finishingKeys: number = 0;

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
      // one.
      if (this.claimed && previous.length >= 2) {
        this.staged = this.momentum(time);
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

  /** Zooms in at a double tap. */
  doubleTap(x: number, y: number): void {
    if (this.canZoom()) {
      this.animate({ scale: 2, anchor: this.anchorAt({ x: x, y: y }) }, ZOOM);
    }
  }

  /** Zooms out at a two-finger tap, about the point between the fingers. */
  twoFingerTap(x: number, y: number): void {
    if (this.canZoom()) {
      this.animate({ scale: 0.5, anchor: this.anchorAt({ x: x, y: y }) }, ZOOM);
    }
  }

  /**
   * Takes an axis event of the map, from the mouse wheel or a two-finger swipe
   * on a touchpad.
   */
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
    // move the camera.
    if (event.action === AxisAction.UPDATE) {
      this.axisUpdate(event.getHorizontalAxisValue(), event.getVerticalAxisValue(),
        event.getModifierKeyState?.(['Ctrl']) ?? false, event.sourceTool === SourceTool.TOUCHPAD);
    }
  }

  /**
   * Takes an axis update of `x` and `y`, with Ctrl held or not, from a
   * touchpad or not. `onAxis` calls it; tests call it with made-up updates.
   */
  axisUpdate(x: number, y: number, ctrl: boolean, touchpad: boolean): void {
    if (touchpad) {
      this.axisReportsTouchpad = true;
    } else if (this.touchpadPanning) {
      // The pan gesture pans this swipe.
      return;
    }
    this.scroll(x, y, ctrl, touchpad);
  }

  /**
   * Moves the camera by an axis update of `x` and `y`, with Ctrl held or not:
   * a wheel's, 15 to a notch, or a touchpad swipe's, in vp.
   */
  private scroll(x: number, y: number, ctrl: boolean, touchpad: boolean): void {
    const options = this.options;
    const cooperative = options.cooperative === true;
    if (cooperative && !ctrl) {
      return;
    }
    // Ctrl swaps panning and zooming, except in cooperative mode, where it's
    // what lets the axis move the map.
    const pans = (touchpad || options.wheel === WheelAction.PAN) !== (ctrl && !cooperative);
    if (pans) {
      if ((x === 0 && y === 0) || !this.canPan()) {
        return;
      }
      const perUnit = touchpad ? 1 : WHEEL_PAN_PER_UNIT;
      this.stop();
      this.move({ offset: { x: -x * perUnit, y: -y * perUnit } }, PAN);
    } else {
      if (y === 0 || !this.canZoom()) {
        return;
      }
      this.stop();
      this.move({ scale: Math.pow(2, -y * WHEEL_LEVELS_PER_UNIT), anchor: this.anchorAt(this.pointer) }, ZOOM);
      // Each of a wheel's notches is a gesture, which a snap would undo.
      if (!touchpad) {
        this.changed &= ~ZOOM;
      }
    }
    this.axisOwned = true;
  }

  /**
   * Takes the updates of the map's pan gesture. Touches pan through `onTouch`,
   * so only a touchpad swipe moves the camera here, on a system whose axis
   * events don't say that the touchpad made them.
   */
  onPan(event: GestureEvent): void {
    if (event.sourceTool === SourceTool.TOUCHPAD) {
      this.touchpadPan(event.offsetX, event.offsetY, event.getModifierKeyState?.(['Ctrl']) ?? false);
    }
  }

  /**
   * Takes a touchpad swipe that the pan gesture reports, which has moved by
   * `offsetX`, `offsetY` since it started, with Ctrl held or not. `onPan`
   * calls it; tests call it with made-up swipes.
   */
  touchpadPan(offsetX: number, offsetY: number, ctrl: boolean): void {
    if (this.axisReportsTouchpad) {
      return;
    }
    if (!this.touchpadPanning) {
      this.touchpadPanning = true;
      this.panOffset = { x: 0, y: 0 };
    }
    const dx = offsetX - this.panOffset.x;
    const dy = offsetY - this.panOffset.y;
    this.panOffset = { x: offsetX, y: offsetY };
    // The fingers move the content, so they scroll the other way.
    this.scroll(-dx, -dy, ctrl, true);
  }

  /** The map's pan gesture ended or was cancelled. */
  onPanEnd(): void {
    if (this.touchpadPanning) {
      this.touchpadPanning = false;
      this.axisEnded();
    }
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
    if (!this.canZoom()) {
      return;
    }
    this.stop();
    const step = scale / this.pinchScale;
    this.pinchScale = scale;
    // The event's pinch center is in window coordinates, and the axis events
    // of the pinch have the map's.
    this.move({ scale: step, anchor: this.anchorAt(this.pointer) }, ZOOM);
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
   * Takes a mouse event of the map: a drag with the right button rotates and
   * pitches, and a right click is a long click.
   */
  onMouse(event: MouseEvent): void {
    this.mouse(event.action, event.button, event.timestamp / 1e6, event.x, event.y);
  }

  /**
   * Takes a mouse event's action and button, at `time` and the point `x`,
   * `y`. `onMouse` calls it; tests call it with made-up events. Side to side
   * turns the map and up and down tilts it, once the pointer has moved past
   * a click's slop, without momentum. A release within the slop clicks.
   */
  mouse(action: MouseAction, button: MouseButton, time: number, x: number, y: number): void {
    const point: ScreenPoint = { x: x, y: y };
    this.pointer = point;
    if (action === MouseAction.Press && button === MouseButton.Right) {
      this.stop();
      this.finish();
      this.rightDown = point;
      this.rightLast = point;
      this.rightDragging = false;
      return;
    }
    const down = this.rightDown;
    if (down === undefined) {
      return;
    }
    if ((action === MouseAction.Release && button === MouseButton.Right) || action === MouseAction.CANCEL) {
      this.rightDown = undefined;
      this.finish();
      if (action === MouseAction.Release && !this.rightDragging && distance(down, point) <= TAP_SLOP) {
        this.target.clicked(point, true);
      }
      return;
    }
    if (action !== MouseAction.Move) {
      return;
    }
    // The motion past the slop moves the camera from the next event, as a
    // touch's does.
    if (!this.rightDragging) {
      this.rightDragging = distance(down, point) > TAP_SLOP;
      this.rightLast = point;
      return;
    }
    const dx = x - this.rightLast.x;
    const dy = y - this.rightLast.y;
    this.rightLast = point;
    const delta: CameraDelta = {};
    let movements = 0;
    if (dx !== 0 && this.canRotate()) {
      delta.bearing = dx * MOUSE_BEARING_PER_VP;
      movements |= ROTATE;
    }
    if (dy !== 0 && this.canPitch()) {
      delta.pitch = dy * MOUSE_PITCH_PER_VP;
      movements |= PITCH;
    }
    if (movements !== 0) {
      this.moveTurning(delta, time, movements);
    }
  }

  /**
   * Takes a key event of the map. While they're held, the arrows pan, Shift
   * and the arrows rotate and pitch, and plus and minus zoom. Returns whether
   * it used the key.
   */
  onKey(event: KeyEvent): boolean {
    if (event.type === KeyType.Down) {
      return this.keyDown(event.keyCode, event.getModifierKeyState?.(['Shift']) ?? false);
    }
    return event.type === KeyType.Up ? this.keyUp(event.keyCode) : false;
  }

  /**
   * A key went down, with Shift held or not, or the system repeated it while
   * it's held. The key moves the camera a step each 300 ms, every frame,
   * until it's released, and a key released before a step finishes the step.
   * Keys add up, so opposite ones cancel. Repeats don't move the camera.
   * Returns whether the map uses the key. `onKey` calls it; tests call it too.
   */
  keyDown(code: number, shift: boolean): boolean {
    const held = this.keys.get(code);
    if (held !== undefined && !held.released) {
      return true;
    }
    const key = this.keyStep(code, shift);
    if (held !== undefined) {
      // Pressed again before its step finished: the same movement moves a step
      // more, and another one, as Shift makes, moves once the step finishes.
      if (key !== undefined && sameStep(held, key)) {
        held.released = false;
        held.progress -= 1;
        return true;
      }
      this.keys.delete(code);
      this.keys.set(-1 - this.finishingKeys++, held);
    }
    if (key === undefined) {
      return false;
    }
    // The first key stops the input before it; more keys join it.
    if (!this.keysMoving()) {
      this.stop();
      this.finish();
      this.endStep();
    }
    this.keys.set(code, key);
    this.syncFrames();
    return true;
  }

  /** A key went up. Returns whether the map used it. */
  keyUp(code: number): boolean {
    const key = this.keys.get(code);
    if (key === undefined) {
      return false;
    }
    if (key.dead || key.progress >= 1) {
      this.keys.delete(code);
      this.keysStopped();
    } else {
      key.released = true;
    }
    return true;
  }

  /** The map lost focus, so it won't hear the keys that are held go up. */
  blur(): void {
    this.keys.clear();
    this.keysStopped();
  }

  /**
   * Stops momentum, held keys, and an animated step, such as a snap, and ends
   * the gesture they belong to. Fingers that are down keep moving the camera.
   */
  stop(): void {
    // Momentum that waits for the last finger goes too.
    this.staged = undefined;
    // Held keys stay until they go up, so their repeats don't start them again.
    this.keys.forEach((key: HeldKey, code: number) => {
      if (key.released) {
        this.keys.delete(code);
      } else {
        key.dead = true;
      }
    });
    this.keysStopped();
    // So do the momentum and snap that the end of the input started.
    this.endStep();
  }

  /** The system took the touches back: end without momentum, a snap, or a click. */
  cancel(): void {
    this.touches = [];
    this.claimed = false;
    this.tap = false;
    this.lastTap = undefined;
    this.pendingTap = undefined;
    this.rightDown = undefined;
    this.syncFrames();
    if (this.phaseOpen) {
      this.phaseOpen = false;
      this.moving = false;
      this.target.applyCameraDelta({ gesturePhase: GesturePhase.cancel });
      this.target.gestureEnded();
    }
  }

  /** Stops input for good, as the map leaves, and ends what it started. */
  dispose(): void {
    this.keys.clear();
    this.cancel();
    this.endStep();
    this.frames?.off('frame');
    this.frames?.stop();
    this.frames = undefined;
    this.framesRunning = false;
  }

  // The first touch of a sequence stops momentum and keys. A press soon after
  // a tap may start a quick zoom, and is a second tap: the tap before it
  // doesn't click. Any other press lets that tap click at once.
  private press(time: number, point: TouchPoint): void {
    this.stop();
    this.finish();
    this.claimed = false;
    this.down = point;
    this.tap = true;
    const lastTap = this.lastTap;
    this.quickZoomReady = lastTap !== undefined && time - this.lastTapTime < QUICK_ZOOM_MS &&
      distance(lastTap, point) < QUICK_ZOOM_SLOP;
    const pending = this.pendingTap;
    this.pendingTap = undefined;
    this.syncFrames();
    this.secondTap = pending !== undefined && this.quickZoomReady;
    if (pending !== undefined && !this.secondTap) {
      this.target.clicked(pending, false);
    }
  }

  // Recognition starts again from the touches that are down, and the
  // movements that they start run their onStart again. Once the map claims one
  // touch, it pans at once, or quick-zooms after a tap when the claim's motion
  // is mostly vertical.
  private restart(claimed: boolean): void {
    const touches = this.touches;
    this.origin = touches;
    this.started = 0;
    this.panning = false;
    this.zooming = false;
    this.rotating = false;
    this.pitching = false;
    this.quickZooming = false;
    this.panX.clear();
    this.panY.clear();
    this.zoom.clear();
    this.turn.clear();
    this.tilt.clear();
    this.notches = undefined;
    if (touches.length >= 2) {
      this.zoomBase = distance(touches[0], touches[1]);
      this.minSpan = this.zoomBase;
    } else if (claimed && this.down !== undefined) {
      const dx = Math.abs(touches[0].x - this.down.x);
      const dy = Math.abs(touches[0].y - this.down.y);
      this.quickZooming = this.quickZoomReady && this.canZoom() && dy > dx;
      this.panning = !this.quickZooming;
      this.quickZoom = 0;
    }
  }

  private moveOne(time: number, before: TouchPoint, after: TouchPoint): void {
    if (this.quickZooming) {
      if (this.canZoom() && this.height > 0) {
        const levels = (after.y - before.y) / this.height * QUICK_ZOOM_LEVELS;
        this.quickZoom += levels;
        this.zoom.add(time, this.quickZoom);
        this.move({ scale: Math.pow(2, levels) }, ZOOM);
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
    if (this.canPan() && this.options.cooperative !== true) {
      this.panX.add(time, after.x);
      this.panY.add(time, after.y);
      this.move({ offset: { x: after.x - before.x, y: after.y - before.y } }, PAN);
    }
  }

  // Two fingers pan, pinch, rotate, or pitch. Each starts once its motion since
  // the origin passes a threshold, and moves the camera from the next event,
  // so the threshold's motion doesn't jump the camera.
  private moveTwo(time: number, a0: TouchPoint, b0: TouchPoint, a: TouchPoint, b: TouchPoint): void {
    this.staged = undefined;
    const o1 = this.origin[0];
    const o2 = this.origin[1];
    const span0 = distance(a0, b0);
    const span = distance(a, b);
    const center = midpoint(a, b);
    this.minSpan = Math.min(this.minSpan, span);
    const stable = span0 >= MIN_SPAN && span >= MIN_SPAN;
    const anchor = this.anchorAt(center);

    // Options can change mid-gesture, so each motion checks its option too.
    const delta: CameraDelta = {};
    let movements = 0;
    if (this.panning && this.canPan()) {
      const center0 = midpoint(a0, b0);
      delta.offset = { x: center.x - center0.x, y: center.y - center0.y };
      this.panX.add(time, center.x);
      this.panY.add(time, center.y);
      movements |= PAN;
    }
    if (this.zooming && stable && this.canZoom()) {
      delta.scale = span / span0;
      delta.anchor = anchor;
      this.zoom.add(time, Math.log2(span));
      movements |= ZOOM;
    }
    if (this.rotating && stable && this.canRotate()) {
      const turn = wrap(angle(a, b) - angle(a0, b0));
      this.turned -= turn;
      delta.bearing = -turn;
      delta.anchor = anchor;
      this.turn.add(time, this.turned);
      movements |= ROTATE;
    }
    if (this.pitching && this.canPitch()) {
      delta.pitch = ((a.y - a0.y) + (b.y - b0.y)) / 2 * PITCH_PER_VP;
      this.tilted += delta.pitch;
      this.tilt.add(time, this.tilted);
      movements |= PITCH;
    }
    if (delta.anchor !== undefined) {
      // ArkUI reports one finger at a time, so the midpoint moves by half that
      // finger's step even when the pair doesn't pan. Moving with it keeps the
      // content under both fingers; scaling or turning about it alone drifts.
      if (delta.offset === undefined && this.canPan()) {
        const center0 = midpoint(a0, b0);
        delta.offset = { x: center.x - center0.x, y: center.y - center0.y };
      }
    }
    if (delta.offset !== undefined || delta.scale !== undefined || delta.bearing !== undefined ||
      delta.pitch !== undefined) {
      this.moveTurning(delta, time, movements);
    }

    if (this.pitching) {
      return;
    }
    // Pitch wins when it starts with the others, but can't interrupt a pinch
    // or rotation, and it owns the fingers alone.
    if (!this.zooming && !this.rotating && this.canPitch() && isShove(o1, o2, a, b)) {
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
    if (!this.zooming && this.canZoom()) {
      const slop = this.rotating ? ZOOM_SLOP_WHILE_ROTATING : ZOOM_SLOP;
      if (startsZoom(span - this.zoomBase, span - distance(e1, e2), elapsed, wrap(angle(a, b) - angle(e1, e2)),
        slop)) {
        this.zooming = true;
        this.zoom.clear();
      }
    }
    if (!this.rotating && this.canRotate()) {
      const slop = this.zooming ?
        Math.max(ROTATE_SLOP, ROTATE_ARC_WHILE_ZOOMING * 360 / (Math.PI * this.minSpan)) : ROTATE_SLOP;
      if (startsRotation(wrap(angle(a, b) - angle(o1, o2)), wrap(angle(a, b) - angle(e1, e2)), elapsed, slop)) {
        this.rotating = true;
        this.zoomBase = span;
        this.turn.clear();
      }
    }
    const panSlop = this.target.keepsCenter() ? PAIR_PAN_SLOP_KEEPING_CENTER : PAIR_PAN_SLOP;
    if (!this.panning && this.canPan() && distance(midpoint(o1, o2), center) >= panSlop) {
      this.panning = true;
      this.panX.clear();
      this.panY.clear();
    }
  }

  // The last finger lifted: end with the motion's momentum, which FFI runs. A
  // tap clicks, after the time for a second tap while zoom is on.
  private release(time: number, previous: TouchPoint[]): void {
    const claimed = this.claimed;
    this.claimed = false;
    if (this.tap && previous.length === 1) {
      this.lastTap = previous[0];
      this.lastTapTime = time;
      if (this.secondTap) {
        // A double tap, which zooms if anything.
      } else if (!this.canZoom()) {
        this.target.clicked(previous[0], false);
      } else {
        this.pendingTap = previous[0];
        this.pendingSince = -1;
        this.syncFrames();
      }
    } else {
      this.lastTap = undefined;
    }
    const staged = time - this.stagedTime <= VELOCITY_WINDOW_MS ? this.staged : undefined;
    this.staged = undefined;
    this.finish(claimed ? staged ?? this.momentum(time) : undefined);
  }

  // The momentum of the motion so far, if the last finger lifted at `time`,
  // and the snaps of the movements that the gesture made. FFI glides the parts
  // that move fast enough. Without a time, nothing glides.
  private momentum(time?: number): GestureMomentum {
    const glides = this.glides;
    const speed = (moving: boolean, velocity: Velocity): number | undefined =>
      moving && time !== undefined ? velocity.perSecond(time) : undefined;
    return {
      pan: this.panning && this.canPan() && time !== undefined ?
        panMomentum(glides.pan, this.panX.perSecond(time), this.panY.perSecond(time), this.target.density()) :
        undefined,
      zoom: anchoredMomentum(glides.zoom, speed((this.zooming || this.quickZooming) && this.canZoom(), this.zoom),
        this.snaps(ZOOM) && this.canZoom(), this.anchor),
      bearing: anchoredMomentum(glides.rotate, speed(this.rotating && this.canRotate(), this.turn),
        this.snaps(ROTATE) && this.canRotate(), this.anchor),
      pitch: anchoredMomentum(glides.pitch, speed(this.pitching && this.canPitch(), this.tilt),
        this.snaps(PITCH) && this.canPitch(), undefined),
    };
  }

  private snaps(movement: number): boolean {
    return (this.changed & movement) !== 0;
  }

  // The key's step, if it's one that moves the camera in a way that's on.
  private keyStep(code: number, shift: boolean): HeldKey | undefined {
    const key = new HeldKey();
    switch (code) {
      case KeyCode.KEYCODE_DPAD_LEFT:
      case KeyCode.KEYCODE_DPAD_RIGHT: {
        const sign = code === KeyCode.KEYCODE_DPAD_LEFT ? 1 : -1;
        if (shift && this.canRotate()) {
          key.bearing = sign * KEY_ROTATE;
          key.movement = ROTATE;
        } else if (!shift && this.canPan()) {
          key.x = sign * KEY_PAN;
          key.movement = PAN;
        }
        break;
      }
      case KeyCode.KEYCODE_DPAD_UP:
      case KeyCode.KEYCODE_DPAD_DOWN: {
        const sign = code === KeyCode.KEYCODE_DPAD_UP ? 1 : -1;
        if (shift && this.canPitch()) {
          key.pitch = sign * KEY_PITCH;
          key.movement = PITCH;
        } else if (!shift && this.canPan()) {
          key.y = sign * KEY_PAN;
          key.movement = PAN;
        }
        break;
      }
      case KeyCode.KEYCODE_PLUS:
      case KeyCode.KEYCODE_EQUALS:
      case KeyCode.KEYCODE_NUMPAD_ADD:
      case KeyCode.KEYCODE_MINUS:
      case KeyCode.KEYCODE_NUMPAD_SUBTRACT:
        if (this.canZoom()) {
          key.zoom = code === KeyCode.KEYCODE_MINUS || code === KeyCode.KEYCODE_NUMPAD_SUBTRACT ? -1 : 1;
          key.movement = ZOOM;
        }
        break;
      default:
        break;
    }
    return key.movement === 0 ? undefined : key;
  }

  private keysMoving(): boolean {
    let moving = false;
    this.keys.forEach((key: HeldKey) => {
      moving = moving || !key.dead;
    });
    return moving;
  }

  // Moves the camera by the keys that are held for the time since the last
  // frame. A key moves from the frame after the one that first sees it, as
  // the time before that frame isn't known.
  private holdKeys(time: number): void {
    const fraction = this.keyTime < 0 ? 0 : Math.max(0, time - this.keyTime) / GESTURE_ANIMATION_MS;
    this.keyTime = time;
    let x = 0;
    let y = 0;
    let zoom = 0;
    let bearing = 0;
    let pitch = 0;
    let movements = 0;
    this.keys.forEach((key: HeldKey, code: number) => {
      if (key.dead) {
        return;
      }
      if (key.fresh) {
        key.fresh = false;
        return;
      }
      const part = key.released ? Math.min(fraction, 1 - key.progress) : fraction;
      key.progress += part;
      x += key.x * part;
      y += key.y * part;
      zoom += key.zoom * part;
      bearing += key.bearing * part;
      pitch += key.pitch * part;
      movements |= key.movement;
      if (key.released && key.progress >= 1 - 1e-9) {
        this.keys.delete(code);
      }
    });
    if (x !== 0 || y !== 0 || zoom !== 0 || bearing !== 0 || pitch !== 0) {
      const delta: CameraDelta = {};
      if (x !== 0 || y !== 0) {
        delta.offset = { x: x, y: y };
      }
      if (zoom !== 0) {
        delta.scale = Math.pow(2, zoom);
      }
      if (bearing !== 0) {
        delta.bearing = bearing;
      }
      if (pitch !== 0) {
        delta.pitch = pitch;
      }
      this.move(delta, movements);
      this.keysOwned = true;
    }
    this.keysStopped();
  }

  // Once no key moves the camera, the gesture that they opened ends.
  private keysStopped(): void {
    if (this.keysMoving()) {
      return;
    }
    this.keyTime = -1;
    if (this.keysOwned) {
      this.finish();
    }
    this.syncFrames();
  }

  // Frames run while keys move the camera, and while a tap waits for a second
  // one.
  private syncFrames(): void {
    const run = this.keysMoving() || this.pendingTap !== undefined;
    if (run === this.framesRunning) {
      return;
    }
    this.framesRunning = run;
    if (!run) {
      this.frames?.stop();
      return;
    }
    let frames = this.frames;
    if (frames === undefined) {
      frames = displaySync.create();
      frames.on('frame', (info: displaySync.IntervalInfo) => this.frame(info.timestamp / 1e6));
      this.frames = frames;
    }
    frames.start();
  }

  private frame(time: number): void {
    this.holdKeys(time);
    const pending = this.pendingTap;
    if (pending === undefined) {
      return;
    }
    if (this.pendingSince < 0) {
      this.pendingSince = time;
    }
    if (time - this.pendingSince >= QUICK_ZOOM_MS) {
      this.pendingTap = undefined;
      this.syncFrames();
      this.target.clicked(pending, false);
    }
  }

  // Moves the camera by a twist or a right-button drag, which tick as they
  // cross a haptic notch. The notches measure from the bearing before the
  // rotation's first change.
  private moveTurning(delta: CameraDelta, time: number, movements: number): void {
    let tick = false;
    const haptics = this.glides.haptics;
    if (delta.bearing !== undefined && haptics.interval > 0) {
      let notches = this.notches;
      if (notches === undefined) {
        notches = new BearingNotches(haptics, this.target.getBearing());
        this.notches = notches;
      }
      tick = notches.turn(delta.bearing, time);
    }
    this.move(delta, movements);
    if (tick) {
      this.target.hapticTick();
    }
  }

  // Moves the camera as part of the gesture, which starts with the first move.
  // The movements that the user started with it run their onStart.
  private move(delta: CameraDelta, movements: number): void {
    if (!this.phaseOpen) {
      this.endStep();
      this.phaseOpen = true;
      this.moving = true;
      this.started = 0;
      this.changed = 0;
      delta.gesturePhase = GesturePhase.begin;
    } else {
      delta.gesturePhase = GesturePhase.update;
    }
    this.target.applyCameraDelta(delta);
    if (delta.scale !== undefined || delta.bearing !== undefined) {
      this.anchor = delta.anchor;
    }
    const moved = this.moved(delta, movements);
    this.changed |= moved;
    // After the change, so a camera change that the app makes as the gesture
    // starts follows it.
    if (delta.gesturePhase === GesturePhase.begin) {
      this.target.gestureStarted();
    }
    this.began(moved);
  }

  // The movements of `movements` that `delta` moves the camera in, which the
  // target hears of: a pinch that pans for a moment hasn't zoomed yet, and
  // keys that cancel don't move.
  private moved(delta: CameraDelta, movements: number): number {
    const offset = delta.offset;
    if (offset === undefined || (offset.x === 0 && offset.y === 0)) {
      movements &= ~PAN;
    }
    if ((delta.scale ?? 1) === 1) {
      movements &= ~ZOOM;
    }
    if ((delta.bearing ?? 0) === 0) {
      movements &= ~ROTATE;
    }
    if ((delta.pitch ?? 0) === 0) {
      movements &= ~PITCH;
    }
    if ((movements & PAN) !== 0) {
      this.target.panned();
    }
    if ((movements & ROTATE) !== 0) {
      this.target.rotated();
    }
    if ((movements & ZOOM) !== 0) {
      this.target.zoomed();
    }
    return movements;
  }

  // Runs the onStart of the movements that haven't started in this gesture.
  private began(movements: number): void {
    const fresh = movements & ~this.started;
    this.started |= movements;
    const options = this.options;
    if ((fresh & PAN) !== 0) {
      runOnStart('pan', options.pan);
    }
    if ((fresh & ZOOM) !== 0) {
      runOnStart('zoom', options.zoom);
    }
    if ((fresh & ROTATE) !== 0) {
      runOnStart('rotate', options.rotate);
    }
    if ((fresh & PITCH) !== 0) {
      runOnStart('pitch', options.pitch);
    }
  }

  // Ends the gesture's input with its momentum, which FFI runs, and the
  // gesture with it.
  private finish(momentum?: GestureMomentum): void {
    this.axisOwned = false;
    this.keysOwned = false;
    this.notches = undefined;
    if (this.phaseOpen) {
      this.phaseOpen = false;
      this.animateStep({ gesturePhase: GesturePhase.end, momentum: momentum ?? this.momentum() });
    }
  }

  // Where zoom and rotation at `point` keep the content: there, or at the
  // camera's center while the target keeps it.
  private anchorAt(point: ScreenPoint | undefined): ScreenPoint | undefined {
    return this.target.keepsCenter() ? undefined : point;
  }

  private canPan(): boolean {
    return enabled(this.options.pan);
  }

  private canZoom(): boolean {
    return enabled(this.options.zoom);
  }

  private canRotate(): boolean {
    return enabled(this.options.rotate);
  }

  private canPitch(): boolean {
    return enabled(this.options.pitch);
  }

  // A gesture of one step that animates on its own, such as a double tap's
  // zoom.
  private animate(delta: CameraDelta, movements: number): void {
    this.finish();
    this.endStep();
    this.moving = true;
    this.animateStep(delta, GESTURE_ANIMATION_MS);
    const moved = this.moved(delta, movements);
    this.target.gestureStarted();
    this.started = 0;
    this.began(moved);
  }

  // Animates the camera by `delta`, over `durationMs` or as its momentum
  // runs, as a step that ends the gesture when it ends, unless other input or
  // the app ended it first.
  private animateStep(delta: CameraDelta, durationMs?: number): void {
    const step = ++this.step;
    delta.animation = {
      durationMs: durationMs,
      transitionId: STEP_TRANSITION,
      endHandler: {
        callback: () => {
          if (this.step === step) {
            this.endStep();
          }
        },
      },
    };
    this.target.applyCameraDelta(delta);
  }

  // Ends the animated step, if one is under way, and the gesture with it. A
  // step that something else ends stops where it is.
  private endStep(): void {
    this.step++;
    if (this.moving && !this.phaseOpen) {
      this.moving = false;
      this.target.cancelTransitions(STEP_TRANSITION);
      this.target.gestureEnded();
    }
  }
}

// What the options give to `checkGlides()`, to tell a new value from the same
// one again.
function glidesKey(options: InteractionOptions): string {
  const rotate = options.rotate;
  return JSON.stringify([options.pan?.momentum, options.zoom?.momentum, options.zoom?.snap, rotate?.momentum,
    rotate?.snap, rotate?.haptics, options.pitch?.momentum, options.pitch?.snap]);
}

// Runs the onStart of a movement's options, which logs what it throws.
function runOnStart(movement: string, options: MovementOptions | undefined): void {
  const onStart = options?.onStart;
  if (onStart !== undefined) {
    callHandler(`interactions.${movement}.onStart`, onStart);
  }
}

function sameStep(a: HeldKey, b: HeldKey): boolean {
  return a.x === b.x && a.y === b.y && a.zoom === b.zoom && a.bearing === b.bearing && a.pitch === b.pitch;
}

function enabled(movement: MovementOptions | undefined): boolean {
  return movement?.enabled !== false;
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
