/**
 * How the user moves the map: which camera movements input makes, what the app
 * does as each starts, how each glides and settles, and what the wheel and
 * haptics do. Fields that it leaves out keep their defaults, so every movement
 * is on. Clicks reach the map's handlers whichever movements are on.
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
 * allows, until it, its momentum, and its snap stop. A drag that lifts while
 * it moves glides on and slows down as ArkUI's `Scroll` and `List` do after a
 * fling, a pinch, twist, or tilt glides briefly too, and a rotation that ends
 * near north settles there. Each movement's `momentum` and `snap` change how
 * it glides and settles. The overlay's `ZoomButtons` and `CompassButton` move
 * the camera through the controller, so they don't count. The map's
 * `onGestureStart` and `onGestureEnd` bracket each gesture:
 *
 * - Each `onGestureStart` is followed by exactly one `onGestureEnd` before the
 *   next `onGestureStart`.
 * - `onGestureStart` comes before any movement's `onStart`.
 * - The map's `onCameraMoveStart`, with `CameraMoveReason.GESTURE`, comes
 *   after `onGestureStart` and before any movement's `onStart`, when the
 *   camera was at rest. A gesture that starts while the camera moves, such as
 *   during an animation, takes the move over: `cameraMoveReason` becomes
 *   `GESTURE`, without another `onCameraMoveStart`.
 * - `onGestureEnd` comes a frame or more after the last input, once the
 *   momentum and the snaps end, and before that gesture's
 *   `onCameraIdle`. The controller's `cameraMoving` stays true until then.
 * - A camera change by the app that stops momentum or held keys ends the
 *   gesture, and `onGestureEnd` runs before that call returns.
 * - A touch sequence that the system cancels (`TouchType.Cancel`) ends with no
 *   momentum and no snap, and still fires `onGestureEnd`.
 *
 * A value out of the range that its doc comment gives is reported to the
 * map's `onError` when the options change, and its default takes its place.
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
  zoom?: SnapMovementOptions;
  /**
   * Twist two fingers, drag with the right mouse button from side to side,
   * and Shift with the left and right arrows.
   */
  rotate?: RotationOptions;
  /**
   * Drag two fingers up or down together, drag with the right mouse button up
   * or down, and Shift with the up and down arrows.
   */
  pitch?: SnapMovementOptions;
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

/** Whether a camera movement is on, what the app does as the user starts it, and how it glides. */
export interface MovementOptions {
  /** Whether the user's input makes this movement. On by default. */
  enabled?: boolean;
  /**
   * How the movement glides on and slows down after the user lets go while it
   * moves. Fields that it leaves out keep their defaults.
   */
  momentum?: MomentumOptions;
  /**
   * The user started this movement, such as a pan. It runs each time a
   * gesture starts to move the camera this way, which can be more than once in
   * a gesture: a finger that goes down or lifts starts the movements again. It
   * runs after `onGestureStart`. Momentum, a held key's repeats, and a snap
   * never call it.
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

/** The options of a movement that changes one value of the camera, which can settle on chosen values. */
export interface SnapMovementOptions extends MovementOptions {
  /**
   * The values that the movement settles on, in its unit: zoom levels, or
   * degrees of bearing or pitch. A gesture that made this movement ends by
   * easing to the nearest one, after its momentum, when it stops within the
   * snap's `tolerance` of it. A wheel's notches and a double tap's zoom don't
   * snap. Off, `{ interval: 0 }`, by default for zoom and pitch, and north,
   * `{ interval: 360 }`, for rotation.
   */
  snap?: SnapOptions;
}

/** Rotation's options: those of a movement that snaps, and where it ticks. */
export interface RotationOptions extends SnapMovementOptions {
  /**
   * The bearings where a soft tick plays as a twist or a right-button drag
   * turns the map across one. North, `{ interval: 360 }`, by default;
   * `{ interval: 0 }` turns the ticks off. Ticks need the app to declare
   * `ohos.permission.VIBRATE`, and play only when the system's touch feedback
   * is on.
   */
  haptics?: IntervalOptions;
}

/**
 * How a movement glides after the user lets go: its speed halves every
 * `halfLifeMs` until it falls to `stopSpeed`, as friction slows it. Speeds and
 * distances are in the movement's unit: vp for pan, zoom levels for zoom, and
 * degrees for rotate and pitch. Speeds are per second.
 */
export interface MomentumOptions {
  /** Whether the movement glides. On by default. A movement that doesn't glide still snaps. */
  enabled?: boolean;
  /**
   * How long the speed takes to halve, in milliseconds. Positive. By default,
   * a pan glides as ArkUI's `List` flings: from 1.2 times the release's speed
   * with a half-life of 165 ms below 3000 px/s, and from 1.5 times it with
   * 220 ms above. A half-life that the app gives serves every release, and
   * the glide starts at the release's own speed. 140 ms for zoom, rotate, and
   * pitch.
   */
  halfLifeMs?: number;
  /**
   * The slowest release that glides. Not negative. ArkUI's 240 px/s, in vp,
   * for pan; 0 for zoom; 60 for rotate; 5 for pitch.
   */
  minSpeed?: number;
  /**
   * The speed at which the glide ends. Positive. ArkUI's 120 px/s, in vp, for
   * pan; 0.01 for zoom; 1 for rotate and pitch.
   */
  stopSpeed?: number;
  /**
   * The fastest the glide starts: a faster one starts at this speed.
   * Positive. 9000 for pan, ArkUI's fling limit; none for the others.
   */
  maxSpeed?: number;
  /**
   * The farthest the glide goes: one that would go farther starts slower.
   * Positive. 2.5 for zoom; none for the others.
   */
  maxDistance?: number;
}

/**
 * Values every `interval` from `offset`, in the unit of the movement that
 * takes them. Bearings repeat each turn: a turn has the bearings
 * `offset + k * interval` that are less than a turn from `offset`, so an
 * interval that doesn't divide 360 leaves a shorter gap before `offset`.
 */
export interface IntervalOptions {
  /**
   * The distance from one value to the next. Not negative; 0 leaves none. The
   * option that holds it gives the default.
   */
  interval?: number;
  /** One of the values. Finite. 0 by default. */
  offset?: number;
}

/** Where a movement settles: the values that `IntervalOptions` gives, and how it eases to them. */
export interface SnapOptions extends IntervalOptions {
  /**
   * How near one of the values the movement has to stop to ease to it. Not
   * negative. 7° for rotate and pitch; half a level for zoom, so that
   * `{ interval: 1 }` settles on the nearest whole level.
   */
  tolerance?: number;
  /** How long the ease takes, in milliseconds. Not negative; 0 settles at once. 300 by default. */
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
