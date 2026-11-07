import { CameraFitOptions, CameraOptions, MapHandle, RenderSessionHandle } from '@maplibre/native-ffi';
import display from '@ohos.display';

import { CameraPosition, CameraTransitionOptions, CameraUpdate, FitCameraOptions } from './CameraPosition';
import { ControllerState } from './ControllerState';
import {
  checkBounds,
  checkCamera,
  checkCoordinates,
  checkFit,
  checkGeometry,
  checkTransition,
} from './FfiValues';
import { GeoJsonGeometry } from './GeoJson';
import { LatLng, LatLngBounds, ScreenPoint } from './Geometry';
import { NO_INSETS, paddingInVp } from './Insets';
import { FollowUserLocationOptions } from './location';
import {
  checkHitPadding,
  RenderedFeature,
  RenderedFeatureQueryOptions,
  SourceFeature,
  SourceFeatureQueryOptions,
} from './Queries';
import { Viewport } from './Viewport';

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

// Each controller's state, which only the library reaches.
const states: WeakMap<MapController, ControllerState> = new WeakMap<MapController, ControllerState>();

// Internal: the state of `controller`, which the map that shows it changes.
export function controllerState(controller: MapController): ControllerState {
  return states.get(controller)!;
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
 * they change; only the map and the controller's methods change them.
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
    states.set(this, this.state);
  }

  /**
   * Where the camera last came to rest: after a jump, once an animation or a
   * gesture ends, or where the last map left it. Before a map shows the
   * controller, it's the start camera of `MapControllerOptions`, with
   * MapLibre's defaults for the fields it leaves out. Observable.
   */
  get camera(): CameraPosition {
    return this.state.camera;
  }

  /**
   * The latest frame that the map drew, with its camera and projection.
   * Undefined while no map shows a frame. Observable: it changes with every
   * frame that the view changes in, so read it in `@Computed` getters of the
   * components that follow the map. Read `viewport?.camera ?? camera` for
   * where the camera is now; it can trail a move by a frame.
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
   * order the style lists them. Empty until the style loads. Show it, or a
   * `MapAttributionButton` in the map's overlay, as the sources' terms
   * require. Observable.
   */
  get attributions(): string[] {
    return this.state.attributions;
  }

  /**
   * Whether the camera follows the map's `userLocation`. Only
   * `followUserLocation()` and `stopFollowingUserLocation()` set it; the
   * user's input doesn't, so an app stops following where it chooses, such as
   * in the `onStart` of the map's `interactions.pan`. Observable.
   */
  get followingUserLocation(): boolean {
    return this.state.followingUserLocation;
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
   * density stopped it first. Once the camera stops, `camera` holds where it
   * rests. It rejects when the map rejects the move.
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
    checkBounds(bounds);
    return this.state.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForLatLngBounds(bounds, fit));
  }

  /**
   * Moves the camera so `coordinates` fit, as `fitCameraToBounds()` does. It
   * throws an `Error` for an empty array, or a coordinate that `updateCamera()`
   * would throw for as a `center`.
   */
  fitCameraToCoordinates(coordinates: LatLng[], options?: FitCameraOptions): Promise<boolean> {
    checkCoordinates(coordinates);
    return this.state.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForLatLngs(coordinates, fit));
  }

  /**
   * Moves the camera so `geometry` fits, as `fitCameraToBounds()` does. It
   * throws an `Error` for a geometry with no position, or with a position
   * whose longitude isn't finite or whose latitude is outside -90 to 90.
   */
  fitCameraToGeometry(geometry: GeoJsonGeometry, options?: FitCameraOptions): Promise<boolean> {
    checkGeometry(geometry);
    return this.state.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions): Promise<CameraOptions> => map.cameraForGeometry(geometry, fit));
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
   * and to each new `userHeading` too while `options` follows the heading,
   * until the app calls `stopFollowingUserLocation()`. Without a location yet,
   * the camera moves once the map gets one, after the camera moves that wait
   * for the map. Each move eases the center, the first also the zoom that
   * `options` names, and each the bearing if `options` asks; the rest of the
   * camera stays as the app leaves it. A camera change that the app makes
   * while following lasts until the next location or heading.
   *
   * While it follows, the user's zoom and rotation keep the location at the
   * center, and two fingers don't pan. The camera waits for the user's input
   * to end, then catches up with the location, so a pan or a rotation away
   * from a followed bearing eases back unless the app stops following, or
   * follows without the bearing, in that movement's `onStart`:
   *
   * ```ets
   * this.controller.followUserLocation({ zoom: 16, bearing: FollowBearing.heading });
   *
   * MaplibreMap({
   *   style: STYLE,
   *   controller: this.controller,
   *   userLocation: this.location,
   *   interactions: {
   *     pan: { onStart: () => this.controller.stopFollowingUserLocation() },
   *     rotate: { onStart: () => this.controller.followUserLocation() },
   *   },
   * })
   * ```
   */
  followUserLocation(options?: FollowUserLocationOptions): void {
    this.state.followUserLocation(options);
  }

  /** Leaves the camera where it is when the map's `userLocation` changes. */
  stopFollowingUserLocation(): void {
    this.state.followingUserLocation = false;
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
