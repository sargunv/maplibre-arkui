/**
 * How the user's input moves the map. Fields left out keep their defaults, so
 * every movement is on by default. Clicks reach the map's click handlers even
 * when movements are off.
 *
 * New options apply at once, and a movement that is turned off stops at once.
 * A value outside its documented range is reported to the map's `onError`, and
 * its default is used instead.
 */
export interface InteractionOptions {
  /**
   * Panning: dragging with one finger, two fingers, or the mouse, swiping two
   * fingers on a touchpad, and the arrow keys. While it's off, a scrolling
   * parent gets one-finger drags.
   */
  pan?: MovementOptions;
  /**
   * Zooming: pinching, double tapping, tapping with two fingers, the wheel, a
   * touchpad pinch, and the plus and minus keys. While it's on, a tap counts as
   * a click only after 300 ms pass without a second tap.
   */
  zoom?: SnapMovementOptions;
  /**
   * Rotation: twisting two fingers, dragging sideways with the right mouse
   * button, and Shift with the left and right arrow keys.
   */
  rotate?: RotationOptions;
  /**
   * Pitch: dragging two fingers up or down, dragging up or down with the right
   * mouse button, and Shift with the up and down arrow keys.
   */
  pitch?: SnapMovementOptions;
  /**
   * What the mouse wheel does. Defaults to `WheelAction.ZOOM`. With Ctrl held,
   * the wheel does the other action, except in cooperative mode. A touchpad
   * swipe pans, or zooms with Ctrl held.
   */
  wheel?: WheelAction;
  /**
   * Whether the map leaves page-scrolling input to a scrolling parent, such as
   * a `Scroll` or `List`. False by default. While it's true, one-finger drags,
   * the wheel, and touchpad swipes scroll the parent, two fingers move the map,
   * and Ctrl with the wheel does what `wheel` says.
   */
  cooperative?: boolean;
}

/** Options for one camera movement. */
export interface MovementOptions {
  /** Whether the user's input makes this movement. True by default. */
  enabled?: boolean;
  /**
   * How the movement glides after the user lets go while it moves. Fields left
   * out keep their defaults.
   */
  momentum?: MomentumOptions;
  /**
   * Called each time the user starts this movement, after `onGestureStart`.
   * It can be called more than once in a gesture, such as when a finger goes
   * down. Runs on the UI thread; if it throws, the map logs the error.
   */
  onStart?: () => void;
}

/** Options for a movement that can snap to chosen values. */
export interface SnapMovementOptions extends MovementOptions {
  /**
   * The values that the movement settles on: zoom levels, or degrees of bearing
   * or pitch. When a gesture stops within `tolerance` of one, after its
   * momentum, the camera eases to it. Off (`{ interval: 0 }`) by default for
   * zoom and pitch, and north (`{ interval: 360 }`) for rotation.
   */
  snap?: SnapOptions;
}

/** Options for rotation. */
export interface RotationOptions extends SnapMovementOptions {
  /**
   * The bearings where the device plays a soft tick as a twist or right-button
   * drag turns the map past one. North (`{ interval: 360 }`) by default;
   * `{ interval: 0 }` turns ticks off. Ticks need the app to declare
   * `ohos.permission.VIBRATE`.
   */
  haptics?: IntervalOptions;
}

/**
 * How a movement glides after the user lets go. The speed halves every
 * `halfLifeMs` until it falls to `stopSpeed`. Speeds and distances are in the
 * movement's unit: vp for pan, zoom levels for zoom, and degrees for rotation
 * and pitch. Speeds are per second.
 */
export interface MomentumOptions {
  /**
   * Whether the movement glides. True by default. A movement that doesn't
   * glide still snaps.
   */
  enabled?: boolean;
  /**
   * How long the speed takes to halve, in ms. Positive. 140 by default for
   * zoom, rotation, and pitch. By default, a pan glides like a `List` fling;
   * when set, a pan glides from the release speed with this half-life.
   */
  halfLifeMs?: number;
  /**
   * The slowest release that glides. Not negative. Defaults to 240 for pan, 0
   * for zoom, 60 for rotation, and 5 for pitch.
   */
  minSpeed?: number;
  /**
   * The speed at which the glide ends. Positive. Defaults to 120 for pan, 0.01
   * for zoom, and 1 for rotation and pitch.
   */
  stopSpeed?: number;
  /**
   * The fastest speed a glide starts at. Positive. Defaults to 9000 for pan,
   * and no limit for the others.
   */
  maxSpeed?: number;
  /**
   * The farthest a glide goes; a glide that would go farther starts slower.
   * Positive. Defaults to 2.5 for zoom, and no limit for the others.
   */
  maxDistance?: number;
}

/**
 * Values spaced `interval` apart, starting from `offset`, in the movement's
 * unit. For bearings, the values repeat every 360°.
 */
export interface IntervalOptions {
  /**
   * The distance between values. Not negative; 0 means no values. The field
   * that holds these options gives the default.
   */
  interval?: number;
  /** One of the values. Finite. 0 by default. */
  offset?: number;
}

/** Where a movement snaps, and how it eases there. */
export interface SnapOptions extends IntervalOptions {
  /**
   * How close to a value the movement must stop to snap to it. Not negative.
   * Defaults to 7° for rotation and pitch, and half a level for zoom, so
   * `{ interval: 1 }` snaps to the nearest whole level.
   */
  tolerance?: number;
  /**
   * How long the snap takes. Not negative; 0 snaps at once. 300 ms by default.
   */
  durationMs?: number;
}

/**
 * An action for the mouse wheel. Values may be added in later releases; give a
 * `switch` over it a `default` branch.
 */
export enum WheelAction {
  /** Zoom at the pointer. */
  ZOOM,
  /** Pan up and down, or sideways with a tilting wheel. */
  PAN,
}
