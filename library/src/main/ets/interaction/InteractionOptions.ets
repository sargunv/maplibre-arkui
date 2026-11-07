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
 * allows, until it and its momentum stop. A drag that lifts while it moves
 * glides on and slows down as ArkUI's `Scroll`, `List`, and `Grid` do after a
 * fling, and a pinch, twist, or tilt that lifts while it moves glides briefly
 * too. The overlay's `ZoomButtons` and
 * `CompassButton` move the camera through the controller, so they don't
 * count. The map's `onGestureStart` and `onGestureEnd` bracket each gesture:
 *
 * - Each `onGestureStart` is followed by exactly one `onGestureEnd` before the
 *   next `onGestureStart`.
 * - `onGestureStart` comes before any movement's `onStart`.
 * - The map's `onCameraMoveStart`, with `CameraMoveReason.GESTURE`, comes
 *   after `onGestureStart` and before any movement's `onStart`, when the
 *   camera was at rest. A gesture that starts while the camera moves, such as
 *   during an animation, takes the move over: `cameraMoveReason` becomes
 *   `GESTURE`, without another `onCameraMoveStart`.
 * - `onGestureEnd` comes before that gesture's `onCameraIdle`, and the
 *   controller's `cameraMoving` stays true until then, through the momentum
 *   and the snap.
 * - The end of a gesture that rotated the map can come a frame or more after
 *   the last input, once the map has settled the bearing as `rotate.snap`
 *   says.
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
 * `MapController.followUserLocation()` describes, a pan stops following and a
 * rotation clears the followed bearing, before `onGestureStart`. Zoom and
 * rotation keep the location at the center, and two fingers pan only after
 * they drag 400 vp. With `pan` or `rotate` off, the user can't do either.
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
   * runs after `onGestureStart`. Momentum, a held key's repeats, and a
   * rotation's snap never call it.
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
   * Where a rotation settles: once its momentum ends, a bearing near a snap
   * bearing eases to it, as the last part of the gesture. North, within 7°,
   * by default. `{ enabled: false }` turns snapping off.
   */
  snap?: RotationSnapOptions;
  /**
   * Where a soft tick plays as a twist or a right-button drag turns the map
   * across a bearing. North by default. `{ enabled: false }` turns the ticks
   * off. Ticks need the app to declare `ohos.permission.VIBRATE`, and play
   * only when the system's touch feedback is on.
   */
  haptics?: BearingIntervalOptions;
}

/**
 * Bearings every `spacing` degrees from `offset`, where a rotation snaps or
 * ticks. Each turn has the bearings `offset + k * spacing` that are less than
 * a turn from `offset`, so a spacing that doesn't divide 360 leaves a shorter
 * gap before `offset`.
 *
 * A value outside its range is reported to the map's `onError`, and its
 * default takes its place.
 */
export interface BearingIntervalOptions {
  /** Whether the rotation snaps or ticks at these bearings. On by default. */
  enabled?: boolean;
  /**
   * The degrees from one bearing to the next, at least 1. 360, one bearing
   * a turn, by default.
   */
  spacing?: number;
  /** One of the bearings, in degrees, taken modulo 360. 0, north, by default. */
  offset?: number;
}

/** Where a rotation settles: the snap bearings, how near it snaps, and how fast. */
export interface RotationSnapOptions extends BearingIntervalOptions {
  /**
   * How near a snap bearing, in degrees, a rotation that ends there snaps to
   * it, at least 0. 7 by default.
   */
  tolerance?: number;
  /**
   * How long the ease to the snap bearing takes, at least 0. 300 ms by
   * default; 0 settles at once.
   */
  durationMs?: number;
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
