import {
  AnimationOptions,
  CameraFitOptions,
  CameraOptions,
  CameraTransitionEnd,
  CameraTransitionOutcome,
  MapHandle,
  MapProjectionHandle,
  MapView as FrameView,
  RenderSessionHandle,
  RuntimeHandle,
} from '@maplibre/native-ffi';
import geoLocationManager from '@ohos.geoLocationManager';

import { CameraPosition, CameraTransitionOptions, CameraUpdate, FitCameraOptions } from './CameraPosition';
import {
  checkBounds,
  checkCamera,
  checkCoordinates,
  CheckedCamera,
  CheckedFit,
  CheckedTransition,
  checkFit,
  checkGeometry,
  checkTransition,
  toLatLng,
  toScreenPoint,
} from './FfiValues';
import { GeoJsonGeometry } from './GeoJson';
import { LatLng, LatLngBounds, ScreenPoint } from './Geometry';
import { FollowBearing, FollowUserLocationOptions, course } from './location';
import { MapView } from './MapView';

/** Options for a new `MapController`. */
export interface MapControllerOptions {
  /**
   * Where the camera starts. Fields it leaves out keep the map's defaults. The
   * constructor throws an `Error` for a camera that `updateCamera()` would
   * throw for.
   */
  camera?: CameraUpdate;
}

/**
 * Reads and moves the camera of a `MapLibreMap`, from inside or outside the
 * component, as a `Scroller` does for a list.
 *
 * Create one, pass it to a `MapLibreMap`, and keep it. It shows in one map at a
 * time. When the map leaves the screen and comes back, such as after a
 * navigation, the new map starts where the old one left the camera.
 *
 * Its `camera`, `styleLoaded`, `attributions`, and `followingUserLocation`
 * are observable, so a component that reads them updates when they change.
 * The map and the follow methods set them; apps only read them. `frameCamera` and the projection methods, such as
 * `pixelForLatLng()`, are observable too, and change with every frame the
 * camera moves. The camera methods check their arguments first, and throw an
 * `Error` for an invalid one; then they need a map on screen whose FFI map is
 * ready, and reject without one.
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
  /**
   * Where the camera last came to rest: after a jump, once an animation ends,
   * or where the map left it. Undefined until the map first shows. Read
   * `getCamera()` for where the camera is right now, such as during an
   * animation. Only the map sets it; assigning it doesn't move the camera.
   */
  @Trace camera: CameraPosition | undefined = undefined;
  /** Whether the map's style has loaded, so its layers and sources exist, with the map's content. */
  @Trace styleLoaded: boolean = false;
  /**
   * The attribution of the style's sources, as HTML, without repeats, in the
   * order the style lists them. Empty until the style loads. Show it, or a
   * `MapAttributionButton` in the map's overlay, as the sources' terms
   * require.
   */
  @Trace attributions: string[] = [];
  /**
   * Whether the camera follows the map's `userLocation`. Only
   * `followUserLocation()` and `stopFollowingUserLocation()` set it; the
   * user's input doesn't, so an app stops following where it chooses, such as
   * in the `onStart` of the map's `interactions.pan`.
   */
  @Trace followingUserLocation: boolean = false;

  // The camera and size of the frame on screen. The map sets it each time it
  // shows a frame whose view changed, so reads of the frame's projection
  // update with each frame.
  @Trace private frame: FrameView | undefined = undefined;
  // The projection of `frame`, made when first read.
  private projection: MapProjectionHandle | undefined = undefined;
  private view: MapView | undefined = undefined;
  private readonly startCamera: CheckedCamera | undefined;
  private followOptions: FollowUserLocationOptions = {};
  // The zoom that the next move to follow the location takes.
  private followZoom: number | undefined = undefined;
  // How many times the app has moved the camera, so a fit that's still
  // finding its camera gives way.
  private moves: number = 0;

  constructor(options?: MapControllerOptions) {
    const camera = options?.camera;
    this.startCamera = camera === undefined ? undefined : checkCamera(camera);
  }

  /**
   * The FFI runtime of the map on screen. Maps share the library's default
   * runtime unless the app passes `MapLibreMap` its own.
   */
  get runtime(): RuntimeHandle | undefined {
    return this.view?.runtime;
  }

  /**
   * The FFI map on screen, for its style API (sources, layers, images, and
   * feature state) and what else this library doesn't wrap. A new style
   * starts without the sources, layers, and images the app added, so add them
   * in `onStyleLoaded`. When the display's density changes, the map replaces
   * this handle and its render session with new ones at the new density,
   * keeping the camera, and loads the style again. A feature state change draws only from the next frame,
   * so request one on an idle map (see the style API guide). Don't release it; the
   * `MapLibreMap` that created it does. Change the style through the map's
   * `style` param, not this handle's style setters, so that the map adds its
   * `content` and fires `onStyleLoaded`. Camera padding set through this
   * handle bypasses the controller: the camera that it reports keeps the
   * padding that `updateCamera()` or a fit last set, and the next viewport
   * inset change puts that back on the map.
   */
  get map(): MapHandle | undefined {
    return this.view?.map;
  }

  /**
   * The FFI render session that draws the map, while the map has a surface,
   * for feature queries. Its screen points are in vp from the map's top-left
   * corner, as an ArkUI `ClickEvent`'s `x` and `y` are. Don't release it or
   * change its target.
   */
  get renderSession(): RenderSessionHandle | undefined {
    return this.view?.session;
  }

  /**
   * Reads the camera where it is now. Without a map on screen, it's where the
   * camera last came to rest.
   */
  getCamera(): CameraPosition | undefined {
    const view = this.view;
    const map = view?.map;
    return view === undefined || map === undefined ? this.camera : view.appCamera(map.getSnapshot().view.camera);
  }

  /**
   * The camera of the frame on screen, which changes with each frame of an
   * animation or a gesture. Undefined until the map shows a frame. It's
   * observable, so a component that reads it updates every frame the camera
   * moves; read `camera` to update only when the camera comes to rest.
   */
  get frameCamera(): CameraPosition | undefined {
    const camera = this.frame?.camera;
    return camera === undefined || this.view === undefined ? undefined : this.view.appCamera(camera);
  }

  /**
   * Where `coordinate` is in the frame on screen. The point can be outside the
   * map. Undefined until the map shows a frame. Observable, as `frameCamera`
   * is, so content placed with it follows the map.
   */
  pixelForLatLng(coordinate: LatLng): ScreenPoint | undefined {
    const point = this.frameProjection()?.pixelForLatLng(coordinate);
    return point === undefined ? undefined : toScreenPoint(point);
  }

  /**
   * The coordinate at `point` in the frame on screen. Undefined until the map
   * shows a frame. Observable, as `frameCamera` is.
   */
  latLngForPixel(point: ScreenPoint): LatLng | undefined {
    const coordinate = this.frameProjection()?.latLngForPixel(point);
    return coordinate === undefined ? undefined : toLatLng(coordinate);
  }

  /**
   * How many meters one vp covers at `latitude`, at the zoom of the frame on
   * screen, ignoring pitch. Undefined until the map shows a frame. Observable,
   * as `frameCamera` is.
   */
  metersPerPixelAtLatitude(latitude: number): number | undefined {
    return this.frameProjection()?.metersPerPixelAtLatitude(latitude);
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
   * below 0. Otherwise it resolves `true` once the camera gets there, or
   * `false` when `cancelCameraTransitions()`, the user's input, a later camera
   * change, or the map leaving the screen stopped it first. It rejects without
   * a map on screen.
   */
  updateCamera(update: CameraUpdate, options?: CameraTransitionOptions): Promise<boolean> {
    const camera = checkCamera(update);
    const transition = checkTransition(options);
    return this.transition(transition, (map: MapHandle, animation: AnimationOptions) => {
      const view = this.view!;
      view.moveCamera(map, view.resolveCamera(camera), transition, animation);
    });
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
   * or pitch that isn't finite. Otherwise it resolves as `updateCamera()`
   * does, and also rejects when the padding leaves no room.
   */
  fitCameraToBounds(bounds: LatLngBounds, options?: FitCameraOptions): Promise<boolean> {
    checkBounds(bounds);
    return this.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForLatLngBounds(bounds, fit));
  }

  /**
   * Moves the camera so `coordinates` fit, as `fitCameraToBounds()` does. It
   * throws an `Error` for an empty array, or a coordinate that `updateCamera()`
   * would throw for as a `center`.
   */
  fitCameraToCoordinates(coordinates: LatLng[], options?: FitCameraOptions): Promise<boolean> {
    checkCoordinates(coordinates);
    return this.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForLatLngs(coordinates, fit));
  }

  /**
   * Moves the camera so `geometry` fits, as `fitCameraToBounds()` does. It
   * throws an `Error` for a geometry with no position, or with a position
   * whose longitude isn't finite or whose latitude is outside -90 to 90.
   */
  fitCameraToGeometry(geometry: GeoJsonGeometry, options?: FitCameraOptions): Promise<boolean> {
    checkGeometry(geometry);
    return this.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForGeometry(geometry, fit));
  }

  /** Stops every camera animation where it is, and a gesture's momentum. */
  async cancelCameraTransitions(): Promise<void> {
    const map = this.requireMap();
    this.takeOverCamera();
    await map.cancelCameraTransitions();
  }

  /**
   * Moves the camera to the map's `userLocation`, and then to each new one,
   * and to each new `userHeading` too while `options` follows the heading,
   * until the app calls `stopFollowingUserLocation()`. Without a location yet,
   * the camera moves once the map gets one. Each move eases the center, the
   * first also the zoom that `options` names, and each the bearing if
   * `options` asks; the rest of the camera stays as the app leaves it. A
   * camera change that the app makes while following lasts until the next
   * location or heading.
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
   * MapLibreMap({
   *   controller: this.controller,
   *   style: STYLE,
   *   userLocation: this.location,
   *   interactions: {
   *     pan: { onStart: () => this.controller.stopFollowingUserLocation() },
   *     rotate: { onStart: () => this.controller.followUserLocation() },
   *   },
   * })
   * ```
   */
  followUserLocation(options?: FollowUserLocationOptions): void {
    this.followOptions = options ?? {};
    this.followZoom = options?.zoom;
    this.followingUserLocation = true;
    this.takeOverCamera();
    this.view?.followUserLocation();
  }

  /** Leaves the camera where it is when the map's `userLocation` changes. */
  stopFollowingUserLocation(): void {
    this.followingUserLocation = false;
  }

  /**
   * Internal: where the map moves the camera for `location` and `heading`, or
   * undefined while the camera doesn't follow them. A new heading alone, which
   * `headingChanged` says, moves the camera only while it turns with the
   * heading.
   */
  followCamera(location: geoLocationManager.Location, heading: number | undefined,
    headingChanged: boolean): CameraOptions | undefined {
    const follow = this.followOptions.bearing;
    if (!this.followingUserLocation || (headingChanged && follow !== FollowBearing.heading)) {
      return undefined;
    }
    const zoom = this.followZoom;
    this.followZoom = undefined;
    return {
      center: { latitude: location.latitude, longitude: location.longitude },
      zoom: zoom,
      bearing: follow === FollowBearing.course ? course(location) :
        follow === FollowBearing.heading ? heading : undefined,
    };
  }

  /**
   * Internal: the MapLibreMap that shows this controller calls it. Returns
   * where its map's camera starts.
   */
  attach(view: MapView): CheckedCamera | undefined {
    this.view = view;
    return this.camera !== undefined ? checkCamera(this.camera) : this.startCamera;
  }

  /**
   * Internal: that MapLibreMap calls it as it leaves, so the camera rests where
   * that map left it, and the next map starts there.
   */
  detach(view: MapView): void {
    if (this.view !== view) {
      return;
    }
    const map = view.map;
    if (map !== undefined) {
      this.camera = view.appCamera(map.getSnapshot().view.camera);
    }
    this.view = undefined;
    this.styleLoaded = false;
    this.attributions = [];
    this.showFrame(undefined);
  }

  /**
   * Internal: the MapLibreMap that shows this controller calls it with the
   * view of each frame it shows, or undefined once it shows none.
   */
  showFrame(frame: FrameView | undefined): void {
    this.projection?.release();
    this.projection = undefined;
    this.frame = frame;
  }

  private frameProjection(): MapProjectionHandle | undefined {
    const frame = this.frame;
    if (frame !== undefined && this.projection === undefined) {
      this.projection = MapProjectionHandle.create(frame);
    }
    return this.projection;
  }

  // The app's camera change takes over from a gesture's momentum, and from a
  // fit that's still finding its camera.
  private takeOverCamera(): void {
    this.view?.takeOverCamera();
    this.moves++;
  }

  // Finds the camera for a fit, then moves it there, unless the map leaves, or
  // the app or the user moves the camera first.
  private async fit(options: CheckedFit,
    query: (map: MapHandle, fit: CameraFitOptions) => Promise<CameraOptions>): Promise<boolean> {
    this.requireMap();
    const view = this.view!;
    this.takeOverCamera();
    const moves = this.moves;
    const gestures = view.gestureStarts;
    const camera = await view.fitCamera(options, query);
    if (camera === undefined || this.view !== view || this.moves !== moves || view.gestureStarts !== gestures) {
      return false;
    }
    return this.transition(options.transition, (map: MapHandle, animation: AnimationOptions) =>
      view.moveCamera(map, camera, options.transition, animation));
  }

  // Starts a camera change whose animation ends with FFI's end handler, and
  // resolves whether it completed. A jump runs the handler as soon as the
  // camera moves.
  private async transition(transition: CheckedTransition,
    start: (map: MapHandle, animation: AnimationOptions) => void): Promise<boolean> {
    const map = this.requireMap();
    this.takeOverCamera();
    return new Promise<boolean>((resolve, reject) => {
      const animation: AnimationOptions = {
        durationMs: transition.durationMs,
        endHandler: {
          callback: (end: CameraTransitionEnd) => resolve(end.outcome === CameraTransitionOutcome.completed),
        },
      };
      try {
        start(map, animation);
      } catch (error) {
        reject(error as Error);
      }
    });
  }

  private requireMap(): MapHandle {
    const map = this.view?.map;
    if (map === undefined) {
      throw new Error('No MapLibreMap shows this MapController');
    }
    return map;
  }
}
