// Gestures and other input that move a map's camera or click it.
//
// ArkUI's recognizers, which MaplibreMap binds, decide whether the map owns a
// touch: against a parent such as a Scroll, and against content above the map.
// The raw touches decide how the camera moves, after a claim, as MapLibre
// Compose and MapLibre GL JS recognize them. Distances are in vp, which are the
// map's logical pixels, and times in milliseconds.

import displaySync from '@ohos.graphics.displaySync';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { CameraDelta, GesturePhase, ScreenPoint } from '@maplibre/native-ffi';

import { callHandler } from './log';

/**
 * How the user moves the map: which camera movements input makes, what the app
 * does as each starts, and what the wheel, rotation, and haptics do. Fields
 * that it leaves out keep their defaults, so every movement is on. Clicks reach
 * the map's handlers whichever movements are on.
 *
 * ```ets
 * MaplibreMap({
 *   controller: this.map,
 *   style: STYLE,
 *   interactions: { rotate: { enabled: false }, pitch: { enabled: false } },
 * })
 * ```
 *
 * A gesture is input on the map that moves the camera, as `interactions`
 * allows, until it and its momentum stop. The overlay's `MapZoomButtons` and
 * `MapCompassButton` move the camera through the controller, so they don't
 * count. The map's `onGestureStart` and `onGestureEnd` bracket each gesture:
 *
 * - Each `onGestureStart` is followed by exactly one `onGestureEnd` before the
 *   next `onGestureStart`.
 * - `onGestureStart` comes before any movement's `onStart`.
 * - `onGestureEnd` comes before that gesture's `onCameraIdle`.
 * - The end of a gesture that rotated the map can come a frame or more after
 *   the last input: once the map reports where the rotation left the bearing,
 *   and once the ease to a bearing of `snapBearings` ends, when there is one.
 * - A camera change by the app that stops momentum or held keys ends the
 *   gesture, and `onGestureEnd` runs before that call returns.
 * - A touch sequence that the system cancels (`TouchType.Cancel`) ends with no
 *   momentum and no snap, and still fires `onGestureEnd`.
 *
 * A change of the options applies at once. A movement that is turned off
 * stops at once, even in the middle of a gesture. Any such change also ends
 * momentum and held keys, and fingers that are down keep making the movements
 * that are still on.
 *
 * While the camera follows the user's location, as
 * `MapController.followUserLocation()` describes, zoom and rotation keep the
 * location at the center, and two fingers pan only after they drag 400 vp.
 */
export interface InteractionOptions {
  /**
   * Drag with one finger or the mouse, or with two fingers; swipe two fingers
   * on a touchpad; and the arrow keys. Turning it off lets a scrolling parent
   * have one-finger drags, and turns off double tap and drag.
   */
  pan?: MovementOptions;
  /**
   * Pinch, double tap, tap with two fingers, the wheel, a touchpad pinch, and
   * the plus and minus keys, and double tap and drag while `pan` is on. While
   * it's on, a tap waits 300 ms for a second tap before it clicks.
   */
  zoom?: MovementOptions;
  /**
   * Twist two fingers, drag with the right mouse button from side to side,
   * and Shift with the left and right arrows.
   */
  rotate?: RotationOptions;
  /**
   * Drag two fingers up or down together, drag with the right mouse button up
   * or down, and Shift with the up and down arrows.
   */
  pitch?: MovementOptions;
  /**
   * What the mouse wheel does: `WheelAction.ZOOM` at the pointer, the default,
   * or `WheelAction.PAN`. With Ctrl held, it does the other, except in
   * cooperative mode. A touchpad swipe pans, or zooms with Ctrl held.
   */
  wheel?: WheelAction;
  /**
   * Whether the map leaves the input that scrolls a page to a scrolling
   * parent, such as a `Scroll` or `List`. Off by default. While it's on:
   *
   * - One-finger drags, the wheel, and touchpad swipes go to the scrolling
   *   parent.
   * - Two fingers move the map.
   * - With Ctrl held, the wheel does what `wheel` says, and a touchpad swipe
   *   pans.
   * - A touchpad pinch, keys, right-button drags, and double and two-finger
   *   taps work as usual.
   * - Double tap and drag doesn't zoom.
   */
  cooperative?: boolean;
}

/** Whether a camera movement is on, and what the app does as the user starts it. */
export interface MovementOptions {
  /** Whether the user's input makes this movement. On by default. */
  enabled?: boolean;
  /**
   * The user started this movement, such as a pan. It runs each time a
   * gesture starts to move the camera this way, which can be more than once in
   * a gesture: a finger that goes down or lifts starts the movements again. It
   * runs after `onGestureStart`. Momentum, a held key's repeats, and a snap to
   * `snapBearings` never call it.
   *
   * Fingers that are down keep moving the camera from where the app puts it
   * here. A camera change, including `followUserLocation()`, ends held keys
   * and an animated step, such as a double tap's zoom.
   *
   * Called on the UI thread. When it throws, the map logs the exception, and
   * the other movements' `onStart` still run.
   */
  onStart?: () => void;
}

/** Rotation's options: those of each movement, and where it settles and ticks. */
export interface RotationOptions extends MovementOptions {
  /**
   * The bearings that a rotation eases to when it ends within 7° of one,
   * after its momentum, as the last part of the gesture. `[0]`, north, by
   * default; `[]` turns snapping off.
   *
   * Each bearing is in degrees, taken modulo 360. A bearing that isn't finite
   * is reported to the map's `onError` and left out.
   */
  snapBearings?: number[];
  /**
   * The bearings where a soft tick plays as a twist or a right-button drag
   * turns the map across one. `[0]`, north, by default; `[]` turns the ticks
   * off. Ticks need the app to declare `ohos.permission.VIBRATE`, and play
   * only when the system's touch feedback is on.
   *
   * Each bearing is in degrees, taken modulo 360. A bearing that isn't finite
   * is reported to the map's `onError` and left out.
   */
  hapticBearings?: number[];
}

/**
 * What the mouse wheel does to the camera. Values may be added in later
 * releases; give a `switch` over it a `default` branch.
 */
export enum WheelAction {
  /** Zoom at the pointer. */
  ZOOM,
  /** Pan up and down, or sideways with a wheel that tilts. */
  PAN,
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
  /** The camera's bearing, as the map last applied the changes. */
  getBearing(): number;
  /**
   * Reads the camera's bearing once the map has applied the changes before
   * the call, and passes it to `read`, or undefined when the map can't say.
   */
  readBearing(read: (bearing: number | undefined) => void): void;
  /** The user started to move the camera. */
  gestureStarted(): void;
  /**
   * Whether zoom and rotation keep the camera's center in place, as while the
   * camera follows the user's location.
   */
  keepsCenter(): boolean;
  /**
   * Whether the camera catches up with the user's location as a gesture ends.
   * The catch-up then turns it to the gesture's snap bearing.
   */
  catchesUp(): boolean;
  /**
   * The camera stopped moving from the user's input. A camera that catches up
   * with the location turns to `snapBearing`, when there is one.
   */
  gestureEnded(snapBearing: number | undefined): void;
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
// Momentum on release.
const VELOCITY_WINDOW_MS = 100;
const FLING_MIN_SPEED = 250;
const FLING_STEP = 16;
const TRANSFORM_MOMENTUM_MS = 600;
const MAX_ZOOM_MOMENTUM = 2.5;
// A rotation that ends within this of a snap bearing snaps to it.
const BEARING_SNAP = 7;
// After MapLibre Compose's BearingHapticDetector: a notch ticks as the bearing
// comes within 1° of it or crosses it, and again only after the bearing has
// gone 2° away. Ticks come at most once in 50 ms.
const NOTCH_CAPTURE = 1;
const NOTCH_REARM = 2;
const NOTCH_MIN_MS = 50;
// Taps, a key's step, and the snap take this long.
export const GESTURE_ANIMATION_MS = 300;
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
  // The rotation's snap and haptic bearings, as the options give them.
  private readonly snapBearings: Bearings = new Bearings('snapBearings');
  private readonly hapticBearings: Bearings = new Bearings('hapticBearings');
  /** The map's height, which a quick zoom measures its drag against. */
  height: number = 0;
  private readonly target: GestureTarget;

  get options(): InteractionOptions {
    return this.currentOptions;
  }

  // Momentum, running or waiting for the last finger, and held keys may be for
  // a movement that's now off, so they go. Options that an app writes in
  // `build()` are a new value each time, so the rest carries on.
  set options(options: InteractionOptions) {
    const before = this.currentOptions;
    this.currentOptions = options;
    this.snapBearings.set(options.rotate?.snapBearings, this.target);
    this.hapticBearings.set(options.rotate?.hapticBearings, this.target);
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
  // The camera gesture: FFI's gesture phase is open, the app was told it
  // started, whether it rotated the map, and the movements whose onStart ran.
  private phaseOpen: boolean = false;
  private moving: boolean = false;
  private rotated: boolean = false;
  private started: number = 0;
  // The haptic notches of the rotation by the pointer that's under way.
  private notches: BearingNotches | undefined = undefined;
  // An animated step's number, so a step that something replaced doesn't end
  // the next one.
  private step: number = 0;
  private momentum: Momentum | undefined = undefined;
  private staged: Momentum | undefined = undefined;
  private stagedTime: number = 0;
  private momentumStart: number = -1;
  // Frames run while momentum or held keys move the camera.
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
    if (this.momentum !== undefined) {
      this.stopMomentum();
      this.finish();
    }
    // A snap that the end of the momentum or keys started goes too.
    this.endStep();
  }

  /** The system took the touches back: end without momentum, a snap, or a click. */
  cancel(): void {
    this.stopMomentum();
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
      this.target.gestureEnded(undefined);
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
        this.anchor = undefined;
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
      movements |= PITCH;
    }
    if ((movements & (ZOOM | ROTATE)) !== 0) {
      this.anchor = anchor;
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
    this.syncFrames();
  }

  // The momentum of the motion so far, if the last finger lifted at `time`.
  private plan(time: number): Momentum | undefined {
    const pan = this.panning && this.canPan();
    const zoom = (this.zooming || this.quickZooming) && this.canZoom();
    const rotate = this.rotating && this.canRotate();
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
      this.move(delta, 0);
    }
    if (momentum.done) {
      this.stopMomentum();
      this.finish();
    }
  }

  private stopMomentum(): void {
    if (this.momentum !== undefined) {
      this.momentum = undefined;
      this.syncFrames();
    }
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

  // Frames run while momentum or keys move the camera, and while a tap waits
  // for a second one.
  private syncFrames(): void {
    const run = this.momentum !== undefined || this.keysMoving() || this.pendingTap !== undefined;
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
    this.coast(time);
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
    if (delta.bearing !== undefined) {
      let notches = this.notches;
      if (notches === undefined) {
        notches = new BearingNotches(this.hapticBearings.values, this.target.getBearing());
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
      this.rotated = false;
      this.started = 0;
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
    this.began(delta, movements);
  }

  // Runs the onStart of the movements that haven't started in this gesture,
  // once `delta` moves the camera their way: a pinch that pans for a moment
  // hasn't zoomed yet, and keys that cancel don't move.
  private began(delta: CameraDelta, movements: number): void {
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

  // Ends the gesture's input. A rotation goes on to snap to a bearing near
  // where it ends.
  private finish(): void {
    this.axisOwned = false;
    this.keysOwned = false;
    this.notches = undefined;
    if (!this.phaseOpen) {
      return;
    }
    this.phaseOpen = false;
    this.target.applyCameraDelta({ gesturePhase: GesturePhase.end });
    if (this.rotated && this.canRotate() && this.snapBearings.values.length > 0) {
      this.snap();
    } else {
      this.moving = false;
      this.target.gestureEnded(undefined);
    }
  }

  // The last step of a rotation, which the gesture ends with. Once the map
  // reports where the rotation left the bearing, the camera eases to the
  // nearest snap bearing, or turns to it as it catches up with the user's
  // location after the gesture.
  private snap(): void {
    const step = ++this.step;
    this.target.readBearing((bearing: number | undefined) => {
      if (this.step !== step) {
        return;
      }
      const snapped = bearing === undefined ? undefined : snapBearing(bearing, this.snapBearings.values);
      if (bearing === undefined || snapped === undefined) {
        this.endStep();
      } else if (this.target.catchesUp()) {
        this.endStep(snapped);
      } else {
        this.animateStep({ bearing: snapped - bearing }, step);
      }
    });
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
    this.stopMomentum();
    this.finish();
    this.endStep();
    const step = ++this.step;
    this.moving = true;
    this.animateStep(delta, step);
    this.target.gestureStarted();
    this.started = 0;
    this.began(delta, movements);
  }

  // Animates the camera by `delta` as the step numbered `step`, which ends
  // when the animation does, unless other input or the app ended it first.
  private animateStep(delta: CameraDelta, step: number): void {
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
  }

  // Ends the animated step, if one is under way, and the gesture with it.
  private endStep(snapBearing?: number): void {
    this.step++;
    if (this.moving && !this.phaseOpen) {
      this.moving = false;
      this.target.gestureEnded(snapBearing);
    }
  }
}

// The bearings of a rotation option, each modulo 360. One that isn't finite
// is reported, once for each new value of the option, and left out.
class Bearings {
  values: number[] = [0];
  private readonly name: string;
  private given: string = '0';

  constructor(name: string) {
    this.name = name;
  }

  set(bearings: number[] | undefined, target: GestureTarget): void {
    const given = bearings ?? [0];
    // Options that an app writes in `build()` are a new value each time.
    if (given.join() === this.given) {
      return;
    }
    this.given = given.join();
    this.values = [];
    for (const bearing of given) {
      if (Number.isFinite(bearing)) {
        this.values.push((bearing % 360 + 360) % 360);
      } else {
        target.fail(new Error(`interactions.rotate.${this.name} has a bearing that isn't finite: ${bearing}`));
      }
    }
  }
}

// Runs the onStart of a movement's options, which logs what it throws.
function runOnStart(movement: string, options: MovementOptions | undefined): void {
  const onStart = options?.onStart;
  if (onStart !== undefined) {
    callHandler(`interactions.${movement}.onStart`, onStart);
  }
}

/**
 * The bearing that a rotation ending at `bearing` snaps to: the nearest of
 * `targets` within 7°, as many turns around as `bearing`, or undefined when
 * there's none or it's there already.
 */
export function snapBearing(bearing: number, targets: number[]): number | undefined {
  let nearest: number | undefined = undefined;
  for (const target of targets) {
    const offset = wrap(bearing - target);
    if (Math.abs(offset) <= BEARING_SNAP && (nearest === undefined || Math.abs(offset) < Math.abs(nearest))) {
      nearest = offset;
    }
  }
  return nearest === undefined || nearest === 0 ? undefined : bearing - nearest;
}

function sameStep(a: HeldKey, b: HeldKey): boolean {
  return a.x === b.x && a.y === b.y && a.zoom === b.zoom && a.bearing === b.bearing && a.pitch === b.pitch;
}

function enabled(movement: MovementOptions | undefined): boolean {
  return movement?.enabled !== false;
}

// The haptic notches of one rotation by the pointer, after MapLibre Compose's
// BearingHapticDetector. A notch that the rotation starts at is silent until
// the bearing leaves it.
class BearingNotches {
  private readonly bearings: number[];
  private readonly armed: boolean[];
  private bearing: number;
  private lastTick: number = -Infinity;

  constructor(bearings: number[], bearing: number) {
    this.bearings = bearings;
    this.bearing = bearing;
    this.armed = bearings.map((notch: number) => Math.abs(wrap(notch - bearing)) > NOTCH_CAPTURE);
  }

  // Turns by `degrees` at `time`, and returns whether that reached a notch. A
  // tick too soon after the last one is dropped, not delayed.
  turn(degrees: number, time: number): boolean {
    const from = this.bearing;
    const to = from + degrees;
    this.bearing = to;
    if (degrees === 0) {
      return false;
    }
    let reached = false;
    for (let i = 0; i < this.bearings.length; i++) {
      const ahead = wrap(this.bearings[i] - from);
      if (this.armed[i] && ahead >= Math.min(0, degrees) - NOTCH_CAPTURE &&
        ahead <= Math.max(0, degrees) + NOTCH_CAPTURE) {
        reached = true;
        this.armed[i] = false;
      }
      if (Math.abs(wrap(this.bearings[i] - to)) > NOTCH_REARM) {
        this.armed[i] = true;
      }
    }
    if (!reached || time - this.lastTick < NOTCH_MIN_MS) {
      return false;
    }
    this.lastTick = time;
    return true;
  }
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
