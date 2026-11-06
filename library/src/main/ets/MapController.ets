import {
  AnimationOptions,
  Camera as CameraPosition,
  CameraFitOptions,
  CameraOptions,
  cameraToOptions,
  CameraTransitionEnd,
  CameraTransitionOutcome,
  CameraUpdate,
  CameraUpdateMode,
  EdgeInsets,
  LatLng,
  LatLngBounds,
  MapHandle,
  MapProjectionHandle,
  MapView as FrameView,
  RenderSessionHandle,
  RuntimeHandle,
  ScreenPoint,
} from '@maplibre/native-ffi';
import geoLocationManager from '@ohos.geoLocationManager';

import { GeoJsonGeometry } from './GeoJson';
import { FollowBearing, FollowUserLocationOptions, course } from './location';
import { logError } from './log';
import { MapView } from './MapView';

/** Options for a new `MapController`. */
export interface MapControllerOptions {
  /** Where the camera starts. Fields it leaves out keep the map's defaults. */
  camera?: CameraOptions;
}

/**
 * How `fitCameraToLatLngBounds()` and the other fit methods of `MapController`
 * move the camera.
 */
export interface FitCameraOptions {
  /** Whether the camera jumps, eases, or flies. Jumps by default. */
  mode?: CameraUpdateMode;
  /** How long the camera takes, its curve, and its end handler, unless it jumps. */
  animation?: AnimationOptions;
  /** The bearing of the camera, in degrees. Keeps the map's by default. */
  bearing?: number;
  /** The pitch of the camera, in degrees. Keeps the map's by default. */
  pitch?: number;
  /**
   * Space, in vp, to keep between what the camera fits and the edges of the
   * part of the map that the viewport insets and the camera padding leave.
   * The camera keeps it only for the fit; it doesn't stay in the camera's
   * padding.
   */
  fitPadding?: EdgeInsets;
  /**
   * The padding of the camera after the fit, which stays as `updateCamera()`
   * sets it. Keeps the camera's padding by default.
   */
  cameraPadding?: EdgeInsets;
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
 * camera moves. The camera methods need a map on screen whose FFI map is ready,
 * and reject without one.
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
  private readonly startCamera: CameraOptions | undefined;
  private followOptions: FollowUserLocationOptions = {};
  // The zoom that the next move to follow the location takes.
  private followZoom: number | undefined = undefined;
  // How many times the app has moved the camera, and how the last move ends
  // the one before, so a fit that's still finding its camera gives way.
  private moves: number = 0;
  private lastMove: CameraTransitionOutcome = CameraTransitionOutcome.replaced;

  constructor(options?: MapControllerOptions) {
    this.startCamera = options?.camera;
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
    return camera === undefined || this.view === undefined ? camera : this.view.appCamera(camera);
  }

  /**
   * Where `coordinate` is in the frame on screen, in vp from the map's top-left
   * corner, as FFI's `MapProjectionHandle.pixelForLatLng()` finds it. The point
   * can be outside the map. Undefined until the map shows a frame. Observable,
   * as `frameCamera` is, so content placed with it follows the map.
   */
  pixelForLatLng(coordinate: LatLng): ScreenPoint | undefined {
    return this.frameProjection()?.pixelForLatLng(coordinate);
  }

  /**
   * The coordinate at `point`, in vp from the map's top-left corner, in the
   * frame on screen. Undefined until the map shows a frame. Observable, as
   * `frameCamera` is.
   */
  latLngForPixel(point: ScreenPoint): LatLng | undefined {
    return this.frameProjection()?.latLngForPixel(point);
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
   * Moves the camera, at once or with an animation, as FFI's
   * `MapHandle.updateCamera()` does. A `padding` replaces the camera's
   * padding, inside the map's `viewportInsets`; without one, the camera keeps
   * its padding. A `center` goes to the middle of what they leave.
   *
   * Resolves once the camera stops: with `CameraTransitionOutcome.completed`
   * when it got there, `cancelled` or `replaced` when
   * `cancelCameraTransitions()`, a gesture, or a later camera change stopped
   * it first, or `closed` when the map left the screen first. It rejects when
   * the map rejects the change.
   */
  updateCamera(update: CameraUpdate): Promise<CameraTransitionOutcome> {
    return this.transition(update.animation, (map: MapHandle, animation: AnimationOptions) => this.view!.updateCamera(map, {
      mode: update.mode,
      camera: update.camera,
      gesturePhase: update.gesturePhase,
      animation: animation,
    }));
  }

  /**
   * Moves the camera so `bounds` fits in the part of the map that the
   * `viewportInsets`, the camera's padding, and `options.fitPadding` leave, as
   * FFI's `MapHandle.cameraForLatLngBounds()` finds it. Resolves as
   * `updateCamera()` does, and rejects when the padding leaves no room.
   *
   * ```ets
   * controller.fitCameraToLatLngBounds(bounds, {
   *   mode: CameraUpdateMode.ease,
   *   fitPadding: { top: 24, left: 24, bottom: 24, right: 24 },
   * });
   * ```
   */
  fitCameraToLatLngBounds(bounds: LatLngBounds, options?: FitCameraOptions): Promise<CameraTransitionOutcome> {
    return this.fit(options ?? {},
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForLatLngBounds(bounds, fit));
  }

  /**
   * Moves the camera so `coordinates` fit, as `fitCameraToLatLngBounds()`
   * does, by FFI's `MapHandle.cameraForLatLngs()`. `coordinates` must not be
   * empty.
   */
  fitCameraToLatLngs(coordinates: LatLng[], options?: FitCameraOptions): Promise<CameraTransitionOutcome> {
    return this.fit(options ?? {},
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForLatLngs(coordinates, fit));
  }

  /**
   * Moves the camera so `geometry` fits, as `fitCameraToLatLngBounds()` does,
   * by FFI's `MapHandle.cameraForGeometry()`. `geometry` is a GeoJSON geometry
   * with at least one position, not a feature.
   */
  fitCameraToGeometry(geometry: GeoJsonGeometry, options?: FitCameraOptions): Promise<CameraTransitionOutcome> {
    return this.fit(options ?? {},
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForGeometry(geometry, fit));
  }

  /** Stops every camera animation where it is, and a gesture's momentum. */
  async cancelCameraTransitions(): Promise<void> {
    const map = this.requireMap();
    this.takeOverCamera(CameraTransitionOutcome.cancelled);
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
    this.takeOverCamera(CameraTransitionOutcome.replaced);
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
  attach(view: MapView): CameraOptions | undefined {
    this.view = view;
    return this.camera !== undefined ? cameraToOptions(this.camera) : this.startCamera;
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
  private takeOverCamera(outcome: CameraTransitionOutcome): void {
    this.view?.takeOverCamera();
    this.moves++;
    this.lastMove = outcome;
  }

  // Finds the camera for a fit, then moves it there, unless the map leaves, or
  // the app or the user moves the camera first.
  private async fit(options: FitCameraOptions,
    query: (map: MapHandle, fit: CameraFitOptions) => Promise<CameraOptions>): Promise<CameraTransitionOutcome> {
    this.requireMap();
    const view = this.view!;
    this.takeOverCamera(CameraTransitionOutcome.replaced);
    const moves = this.moves;
    const gestures = view.gestureStarts;
    const camera = await view.fitCamera(options, query);
    if (camera === undefined || this.view !== view) {
      return endEarly(options, CameraTransitionOutcome.closed);
    }
    if (this.moves !== moves) {
      return endEarly(options, this.lastMove);
    }
    if (view.gestureStarts !== gestures) {
      return endEarly(options, CameraTransitionOutcome.cancelled);
    }
    return this.transition(options.animation, (map: MapHandle, animation: AnimationOptions) => view.updateCamera(map, {
      mode: options.mode,
      camera: camera,
      animation: animation,
    }));
  }

  // Starts a camera change whose animation ends with FFI's end handler, and
  // resolves with how it ended. A jump runs the handler as soon as the camera
  // moves.
  private async transition(options: AnimationOptions | undefined,
    start: (map: MapHandle, animation: AnimationOptions) => void): Promise<CameraTransitionOutcome> {
    const map = this.requireMap();
    this.takeOverCamera(CameraTransitionOutcome.replaced);
    return new Promise<CameraTransitionOutcome>((resolve, reject) => {
      const appHandler = options?.endHandler?.callback;
      const animation: AnimationOptions = {
        durationMs: options?.durationMs,
        velocity: options?.velocity,
        minZoom: options?.minZoom,
        easing: options?.easing,
        transitionId: options?.transitionId,
        endHandler: {
          // Settle first, so a throwing app handler can't leave it pending.
          callback: (end: CameraTransitionEnd) => {
            resolve(end.outcome);
            appHandler?.(end);
          },
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

// Ends a fit that never moved the camera as FFI ends a camera change: through
// the app's end handler, then the promise.
function endEarly(options: FitCameraOptions, outcome: CameraTransitionOutcome): CameraTransitionOutcome {
  try {
    options.animation?.endHandler?.callback?.({ outcome: outcome, generation: BigInt(0) });
  } catch (error) {
    logError(`A camera transition's end handler threw: ${(error as Error).message}`);
  }
  return outcome;
}
