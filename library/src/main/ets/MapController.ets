import {
  AnimationOptions,
  Camera as CameraPosition,
  CameraFitUpdate,
  CameraOptions,
  cameraToOptions,
  CameraTransitionEnd,
  CameraTransitionOutcome,
  CameraUpdate,
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

import { FollowLocationOptions, followCamera } from './location';
import { MapView } from './MapView';

/** Options for a new `MapController`. */
export interface MapControllerOptions {
  /** Where the camera starts. Fields it leaves out keep the map's defaults. */
  camera?: CameraOptions;
}

/**
 * Reads and moves the camera of a `MapLibreMap`, from inside or outside the
 * component, as a `Scroller` does for a list.
 *
 * Create one, pass it to a `MapLibreMap`, and keep it. It shows in one map at a
 * time. When the map leaves the screen and comes back, such as after a
 * navigation, the new map starts where the old one left the camera.
 *
 * Its `camera`, `styleLoaded`, and `attributions` are observable, so a
 * component that reads them updates when they change. The map sets them; apps
 * only read them. `frameCamera` and the projection methods, such as
 * `pixelForLatLng()`, are observable too, and change with every frame the
 * camera moves. The camera methods need a map on screen whose FFI map is ready,
 * and reject without one.
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
   * `MapLibreMap` with `attributionEnabled`, as the sources' terms require.
   */
  @Trace attributions: string[] = [];
  /**
   * Whether the camera follows the map's `userLocation`. Only
   * `followUserLocation()`, `stopFollowingUserLocation()`, and the map set it:
   * the map stops following as the user starts a gesture.
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
  private followOptions: FollowLocationOptions = {};
  // The zoom that the next move to follow the location takes.
  private followZoom: number | undefined = undefined;

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
   * in `onStyleLoaded`. A feature state change draws only from the next frame,
   * so request one on an idle map (see the README). Don't release it; the
   * `MapLibreMap` that created it does. Change the style through the map's
   * `style` param, not this handle's style setters, so that the map adds its
   * `content` and fires `onStyleLoaded`.
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
    const map = this.view?.map;
    return map === undefined ? this.camera : map.getSnapshot().view.camera;
  }

  /**
   * The camera of the frame on screen, which changes with each frame of an
   * animation or a gesture. Undefined until the map shows a frame. It's
   * observable, so a component that reads it updates every frame the camera
   * moves; read `camera` to update only when the camera comes to rest.
   */
  get frameCamera(): CameraPosition | undefined {
    return this.frame?.camera;
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
   * `MapHandle.updateCamera()` does.
   *
   * Resolves once the camera stops: with `CameraTransitionOutcome.completed`
   * when it got there, `cancelled` or `replaced` when
   * `cancelCameraTransitions()`, a gesture, or a later camera change stopped
   * it first, or `closed` when the map left the screen first. It rejects when
   * the map rejects the change.
   */
  updateCamera(update: CameraUpdate): Promise<CameraTransitionOutcome> {
    return this.transition(update.animation, (map: MapHandle, animation: AnimationOptions) => map.updateCamera({
      mode: update.mode,
      camera: update.camera,
      gesturePhase: update.gesturePhase,
      animation: animation,
    }));
  }

  /**
   * Moves the camera so `bounds` fits in the map, as FFI's
   * `MapHandle.fitCameraToLatLngBounds()` does. `update.fit.padding` keeps
   * space between the bounds and the map's edges. Resolves as
   * `updateCamera()` does.
   */
  fitCameraToLatLngBounds(bounds: LatLngBounds, update: CameraFitUpdate): Promise<CameraTransitionOutcome> {
    return this.transition(update.animation,
      (map: MapHandle, animation: AnimationOptions) => map.fitCameraToLatLngBounds(bounds, {
        mode: update.mode,
        fit: update.fit,
        animation: animation,
      }));
  }

  /** Stops every camera animation where it is, and a gesture's momentum. */
  async cancelCameraTransitions(): Promise<void> {
    const map = this.requireMap();
    this.view?.takeOverCamera();
    await map.cancelCameraTransitions();
  }

  /**
   * Moves the camera to the map's `userLocation`, and then to each new one,
   * until the user starts a gesture or the app calls
   * `stopFollowingUserLocation()`. Without a location yet, the camera moves
   * once the map gets one. Each move eases the center, the first also the
   * zoom that `options` names, and each the bearing if `options` asks; the
   * rest of the camera stays as the app leaves it. A camera change that the
   * app makes while following lasts until the next location.
   */
  followUserLocation(options?: FollowLocationOptions): void {
    this.followOptions = options ?? {};
    this.followZoom = options?.zoom;
    this.followingUserLocation = true;
    this.view?.gestures.stop();
    this.view?.followUserLocation();
  }

  /** Leaves the camera where it is when the map's `userLocation` changes. */
  stopFollowingUserLocation(): void {
    this.followingUserLocation = false;
  }

  /**
   * Internal: where the map moves the camera for `location`, or undefined
   * while the camera doesn't follow it.
   */
  followCamera(location: geoLocationManager.Location): CameraOptions | undefined {
    if (!this.followingUserLocation) {
      return undefined;
    }
    const zoom = this.followZoom;
    this.followZoom = undefined;
    return followCamera(location, this.followOptions, zoom);
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
      this.camera = map.getSnapshot().view.camera;
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

  // Starts a camera change whose animation ends with FFI's end handler, and
  // resolves with how it ended. A jump runs the handler as soon as the camera
  // moves.
  private transition(options: AnimationOptions | undefined,
    start: (map: MapHandle, animation: AnimationOptions) => Promise<Object>): Promise<CameraTransitionOutcome> {
    const map = this.view?.map;
    if (map === undefined) {
      return Promise.reject(new Error('No MapLibreMap shows this MapController'));
    }
    // The app's camera change takes over from a gesture's momentum.
    this.view?.takeOverCamera();
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
      start(map, animation).catch((error: Error) => reject(error));
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
