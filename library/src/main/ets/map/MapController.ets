import { CameraFitOptions, CameraOptions, MapHandle, RenderSessionHandle } from '@maplibre/native-ffi';
import display from '@ohos.display';

import { CameraPosition, CameraUpdate } from '../camera/CameraPosition';
import { CameraTransitionOptions, FitCameraOptions } from '../camera/CameraTransitionOptions';
import { checkCamera, checkFit, checkTransition } from '../camera/internal/FfiCamera';
import { NO_INSETS, paddingInVp } from '../camera/internal/Insets';
import { Viewport } from '../camera/Viewport';
import { Expression } from '../expression/Expressions';
import { GeoJsonFeature, GeoJsonGeometry } from '../geometry/GeoJson';
import { LatLng, LatLngBounds, ScreenPoint } from '../geometry/Geometry';
import { checkBounds, checkCoordinates, checkGeometry } from '../geometry/internal/FfiGeometry';
import { FollowBearing, FollowUserLocationOptions } from '../location/FollowUserLocationOptions';
import { ControllerState, registerControllerState } from './internal/ControllerState';
import { checkHitPadding } from './internal/Queries';

/** Options for a new `MapController`. */
export interface MapControllerOptions {
  /**
   * Where the camera starts. Fields it leaves out take MapLibre's defaults:
   * center 0, 0, zoom 0, bearing 0, pitch 0, and no padding. A saved
   * `CameraPosition` restores the camera as it was.
   *
   * Its padding's lengths in px and fp convert to vp at the default display's
   * density and font scale. The constructor throws an `Error` for a camera
   * that `updateCamera()` would throw for, and for a padding side in lpx,
   * which needs a UI context.
   */
  camera?: CameraUpdate;
}

/**
 * Reads and moves the camera of a `MaplibreMap`, from inside or outside the
 * component, as a `Scroller` does for a list.
 *
 * Create one, pass it to a `MaplibreMap`, and keep it. It shows in one map at a
 * time: the one that appeared last. When the map leaves the screen and comes
 * back, such as after a navigation, the new map starts where the old one left
 * the camera.
 *
 * Its getters are observable, so a component that reads them updates when
 * they change. The app can't set them: the map, the user's input, and the
 * controller's methods change them, such as a pan that stops
 * `followingUserLocation` and a rotation that clears `followedBearing`.
 *
 * The camera methods check their arguments first, and throw an `Error` for an
 * invalid one. A move then waits until a map shows the controller at its
 * size, and the moves go to the map in the order the app makes them. They
 * keep waiting while no map shows the controller, until
 * `cancelCameraTransitions()`.
 *
 * The camera's `padding` is the app's: the space, in vp, around the part of
 * the map that the camera centers in. It's what `updateCamera()` or a fit last
 * set, even while an animation still moves the map toward it. The map's
 * `viewportInsets` add to it on the map, but never show in a camera that the
 * controller reports, so a saved camera restores the same way under different
 * insets.
 */
@ObservedV2
export class MapController {
  private readonly state: ControllerState;

  constructor(options?: MapControllerOptions) {
    this.state = new ControllerState(startCamera(options?.camera));
    registerControllerState(this, this.state);
  }

  /**
   * Where the camera is: the camera of the frame on screen while a map shows
   * one, and otherwise where the camera last was, or, before any map showed
   * the controller, the start camera of `MapControllerOptions` with MapLibre's
   * defaults for the fields it leaves out. Observable: it changes with every
   * frame while the camera moves, so read it in `@Computed` getters of the
   * components that follow the map. The map's `onCameraIdle` reports where the
   * camera comes to rest.
   */
  get camera(): CameraPosition {
    return this.state.camera;
  }

  /**
   * The latest frame that the map drew, with its camera and projection.
   * Undefined while no map shows a frame. Observable: it changes with every
   * frame that the view changes in, so read it in `@Computed` getters of the
   * components that follow the map. Its camera is `camera`.
   */
  get viewport(): Viewport | undefined {
    return this.state.viewport;
  }

  /**
   * Whether the map's style has loaded, so its layers and sources exist, with
   * the map's content. Observable.
   */
  get styleLoaded(): boolean {
    return this.state.styleLoaded;
  }

  /**
   * The attribution of the style's sources, as HTML, without repeats, in the
   * order the style lists them. Empty until the style loads. Show it with
   * `AttributionText`, or an `AttributionButton` in the map's overlay, as the
   * sources' terms require. Observable.
   */
  get attributions(): string[] {
    return this.state.attributions;
  }

  /**
   * Whether the camera follows the map's `userLocation`: from
   * `followUserLocation()` until `stopFollowingUserLocation()`, a pan by the
   * user, or a camera move by the app that sets a center, as
   * `followUserLocation()` describes. Observable.
   */
  get followingUserLocation(): boolean {
    return this.state.followingUserLocation;
  }

  /**
   * The direction that the camera turns to while it follows the map's
   * `userLocation`, as `followUserLocation()` set it. Undefined while the
   * camera doesn't follow, or follows without turning: a rotation by the user,
   * or a camera move by the app that sets a bearing, such as a
   * `CompassButton`'s, clears it. Observable.
   */
  get followedBearing(): FollowBearing | undefined {
    return this.state.followedBearing;
  }

  /**
   * Moves the camera, at once or with an animation, as `options` says. A
   * `padding` replaces the camera's padding, inside the map's
   * `viewportInsets`; without one, the camera keeps its padding. A `center`
   * goes to the middle of what they leave.
   *
   * ```ets
   * controller.updateCamera({ zoom: 12 }, { mode: CameraTransitionMode.EASE });
   * ```
   *
   * It throws an `Error` for a field that isn't finite, a `center` latitude
   * outside -90 to 90, a padding side below 0 or in percent, or a `durationMs`
   * below 0. Otherwise the move waits for a map, as the class describes, and
   * the promise resolves when the move ends: `true` once the camera gets
   * there, or `false` when `cancelCameraTransitions()`, the user's input, a
   * later camera change, or the map leaving or starting again at a new
   * density stopped it first. It rejects when the map rejects the move.
   */
  updateCamera(update: CameraUpdate, options?: CameraTransitionOptions): Promise<boolean> {
    return this.state.updateCamera(checkCamera(update), checkTransition(options));
  }

  /**
   * Moves the camera so `bounds` fits in the part of the map that the
   * `viewportInsets`, the camera's padding, and `options.fitPadding` leave.
   *
   * ```ets
   * controller.fitCameraToBounds(bounds, {
   *   mode: CameraTransitionMode.EASE,
   *   fitPadding: { top: 24, left: 24, bottom: 24, right: 24 },
   * });
   * ```
   *
   * It throws an `Error` for bounds with a value that isn't finite, a latitude
   * outside -90 to 90, or a southwest corner north or east of the northeast,
   * and for `options` that `updateCamera()` would throw for, or with a bearing
   * or pitch that isn't finite. Otherwise it waits and resolves as
   * `updateCamera()` does, and also rejects when the padding leaves no room.
   */
  fitCameraToBounds(bounds: LatLngBounds, options?: FitCameraOptions): Promise<boolean> {
    const checked = checkBounds(bounds);
    return this.state.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForLatLngBounds(checked, fit));
  }

  /**
   * Moves the camera so `coordinates` fit, as `fitCameraToBounds()` does. It
   * throws an `Error` for an empty array, or a coordinate that `updateCamera()`
   * would throw for as a `center`.
   */
  fitCameraToCoordinates(coordinates: LatLng[], options?: FitCameraOptions): Promise<boolean> {
    const checked = checkCoordinates(coordinates);
    return this.state.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForLatLngs(checked, fit));
  }

  /**
   * Moves the camera so `geometry` fits, as `fitCameraToBounds()` does. It
   * throws an `Error` for a geometry with no position, or with a position
   * whose longitude isn't finite or whose latitude is outside -90 to 90.
   */
  fitCameraToGeometry(geometry: GeoJsonGeometry, options?: FitCameraOptions): Promise<boolean> {
    const checked = checkGeometry(geometry);
    return this.state.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions): Promise<CameraOptions> => map.cameraForGeometry(checked, fit));
  }

  /**
   * Stops every camera move, those that wait for a map too, and a gesture's
   * momentum. An animation stops where it is. Each move that it stops
   * resolves `false`.
   */
  cancelCameraTransitions(): void {
    this.state.cancelCameraTransitions();
  }

  /**
   * Moves the camera to the map's `userLocation`, and then to each new one,
   * and to each new `userHeading` too while it follows the heading, until
   * following stops. Without a location yet, the camera moves once the map
   * gets one, after the camera moves that wait for the map. A new call
   * replaces the options of the last.
   *
   * ```ets
   * this.controller.followUserLocation({ zoom: 16, bearing: FollowBearing.HEADING });
   * ```
   *
   * Each move is a 1000 ms ease with MapLibre's default curve, as the
   * indicator's move to the location is, so the location stays at the
   * center. It moves the center, the first move also to `options.zoom`, and
   * each to the bearing of `followedBearing` while there is one; the rest of
   * the camera stays as it is. An app that draws its own `location-indicator`
   * layer, with `userLocationIndicator.visible` false, matches it with a
   * 1000 ms `location-transition`.
   *
   * While it follows, the user's input and the app's camera moves change it:
   *
   * - A pan by the user, in any way that `interactions.pan` allows, stops
   *   following. Two fingers pan only after they drag 400 vp, so a pinch or a
   *   twist that drifts keeps following.
   * - A rotation by the user clears `followedBearing`, and the camera keeps
   *   the bearing that the user leaves it at.
   * - The user's zoom and pitch keep following, and zoom and rotation keep
   *   the location at the center.
   * - Both changes happen before `onGestureStart` and the movement's
   *   `onStart`, so those see the new state. The camera waits for the user's
   *   input to end, after `onGestureEnd`, then catches up with the location.
   * - A camera move by the app that sets `center`, and every fit, stops
   *   following. One that sets `bearing`, such as a `CompassButton`'s, clears
   *   `followedBearing`. Others, such as those of `ZoomButtons`, keep
   *   following.
   * - A zoom by the user or the app before the first move takes the place of
   *   `options.zoom`.
   *
   * To lock the camera to the location, turn the movements off: with
   * `interactions.pan.enabled` false, the user can't stop following, and with
   * `interactions.rotate.enabled` false, the user can't clear the bearing.
   */
  followUserLocation(options?: FollowUserLocationOptions): void {
    this.state.followUserLocation(options);
  }

  /**
   * Stops following the map's `userLocation`, so the camera stays where it is
   * when the location changes, and clears `followedBearing`. A move to the
   * location that's under way finishes.
   */
  stopFollowingUserLocation(): void {
    this.state.stopFollowingUserLocation();
  }

  /**
   * Finds the features that the map drew at `point` of its latest frame, or
   * within `options.hitPadding` of it: each layer's features front first, as
   * the map draws them, and the layers in no set order. A feature that several
   * layers draw comes once for each. Resolves undefined
   * while no map shows a frame, and when the map leaves before it answers.
   *
   * It throws an `Error` for a `hitPadding` below 0 or that isn't finite. It
   * rejects when the map rejects the query, such as for a `filter` that isn't
   * a valid filter expression.
   */
  queryRenderedFeatures(point: ScreenPoint,
    options?: RenderedFeatureQueryOptions): Promise<RenderedFeature[] | undefined> {
    const hitPadding = checkHitPadding(options?.hitPadding);
    return this.state.queryRenderedFeatures(point, hitPadding, options);
  }

  /**
   * Finds the features of the source with `sourceId` in the tiles that it has
   * loaded for the map's view, which a source loads only while a visible
   * layer draws it. Resolves undefined while no map shows a frame, and when
   * the map leaves before it answers. It rejects when the map rejects the
   * query.
   */
  querySourceFeatures(sourceId: string, options?: SourceFeatureQueryOptions): Promise<SourceFeature[] | undefined> {
    return this.state.querySourceFeatures(sourceId, options);
  }

  /**
   * Lends `block` the MapLibre Native FFI map that shows the controller, and
   * its render session while it has a surface, for what this library doesn't
   * cover, such as feature state or a style's own sources and layers. It
   * returns what `block` returns, or undefined without calling it when no map
   * shows the controller. What `block` throws reaches the caller.
   *
   * ```ets
   * controller.withFfiMap((map: MapHandle) => map.discarding.requestRepaint());
   * ```
   *
   * `block` runs at once. Don't keep the map or the session, or use them after
   * `block` returns, including after an `await` in it: the map can release
   * them at any time after. Don't release them either.
   *
   * The library owns some of the map's state, which `block` must not change:
   * the style, which the map's `style` sets; the camera padding, which
   * `updateCamera()` sets; the camera bounds, which the map's `cameraBounds`
   * set; the runtime's event handler; and the map's event mask. What `block`
   * adds to the style, such as a source, is gone in the next style.
   *
   * The types are those of `@maplibre/native-ffi`. An app that imports it
   * must use the version that this library depends on, and FFI's types may
   * change in any release.
   */
  withFfiMap<T>(block: (map: MapHandle, session: RenderSessionHandle | undefined) => T): T | undefined {
    return this.state.withFfiMap(block);
  }
}

/** Which features `MapController.queryRenderedFeatures()` finds. */
export interface RenderedFeatureQueryOptions {
  /**
   * How far from the point, in vp, features count as under it: the query
   * covers a square of this many vp on each side of the point. Finite and at
   * least 0; 0 by default, which covers the point alone.
   */
  hitPadding?: number;
  /** The IDs of the layers to query. Every layer by default. */
  layers?: string[];
  /** Which features count: those for which it's true. Every feature by default. */
  filter?: Expression;
}

/**
 * A feature that a layer drew, as `MapController.queryRenderedFeatures()`
 * finds it. The map creates it; fields may be added in later releases.
 */
export interface RenderedFeature {
  /** The feature, with the geometry as the layer drew it. */
  feature: GeoJsonFeature;
  /** The ID of the layer that drew the feature. */
  layerId: string;
  /** The ID of the feature's source. */
  sourceId: string;
  /** The layer of a vector source that the feature is in, or undefined for a source without layers. */
  sourceLayer?: string;
  /** The feature's state, by name. Empty for a feature without state. */
  state: Record<string, Object>;
}

/** Which features `MapController.querySourceFeatures()` finds. */
export interface SourceFeatureQueryOptions {
  /** The layers of a vector source to query. A vector source finds features only in those named here. */
  sourceLayers?: string[];
  /** Which features count: those for which it's true. Every feature by default. */
  filter?: Expression;
}

/**
 * A feature of a source, as `MapController.querySourceFeatures()` finds it.
 * The map creates it; fields may be added in later releases.
 */
export interface SourceFeature {
  /** The feature, with the geometry as its tiles hold it. */
  feature: GeoJsonFeature;
  /** The layer of a vector source that the feature is in, or undefined for a source without layers. */
  sourceLayer?: string;
}

// The start camera, with MapLibre's defaults for the fields that `update`
// leaves out, and its padding in vp. Without a UI context, the default
// display converts it.
function startCamera(update: CameraUpdate | undefined): CameraPosition {
  const camera = checkCamera(update ?? {});
  const padding = camera.padding === undefined ? NO_INSETS : paddingInVp(camera.padding, {
    px: (px: number) => px / display.getDefaultDisplaySync().densityPixels,
    fp: (fp: number) => {
      const screen = display.getDefaultDisplaySync();
      return fp * screen.scaledDensity / screen.densityPixels;
    },
  });
  return {
    center: camera.center ?? { latitude: 0, longitude: 0 },
    zoom: camera.zoom ?? 0,
    bearing: camera.bearing ?? 0,
    pitch: camera.pitch ?? 0,
    padding: { top: padding.top, left: padding.left, bottom: padding.bottom, right: padding.right },
  };
}
