import {
  AnimationOptions,
  Camera as CameraPosition,
  CameraFitUpdate,
  CameraOptions,
  cameraToOptions,
  CameraTransitionEnd,
  CameraTransitionOutcome,
  CameraUpdate,
  LatLngBounds,
  MapHandle,
  RenderSessionHandle,
  RuntimeHandle,
} from '@maplibre/native-ffi';

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
 * Its `camera` and `styleLoaded` are observable, so a component that reads them
 * updates when they change. The map sets them; apps only read them. The
 * camera methods need a map on screen whose FFI map is ready, and reject
 * without one.
 */
@ObservedV2
export class MapController {
  /**
   * Where the camera last came to rest, after a jump or once an animation
   * ends. Undefined until the map first shows. Read `getCamera()` for where
   * the camera is right now, such as during an animation.
   */
  @Trace camera: CameraPosition | undefined = undefined;
  /** Whether the map's style has loaded, so its layers and sources exist. */
  @Trace styleLoaded: boolean = false;

  private view: MapView | undefined = undefined;
  private startCamera: CameraOptions | undefined;

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
   * The FFI map on screen, for what this library doesn't wrap yet. Don't
   * release it; the `MapLibreMap` that created it does.
   */
  get map(): MapHandle | undefined {
    return this.view?.map;
  }

  /**
   * The FFI render session that draws the map, while the map has a surface.
   * Don't release it or change its target.
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
   * Moves the camera, at once or with an animation, as FFI's
   * `MapHandle.updateCamera()` does.
   *
   * Resolves once the camera stops: with `CameraTransitionOutcome.completed`
   * when it got there, or `cancelled` or `replaced` when
   * `cancelCameraTransitions()`, a gesture, or a later camera change stopped
   * it first. It rejects when the map rejects the change.
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

  /** Stops every camera animation where it is. */
  async cancelCameraTransitions(): Promise<void> {
    await this.requireMap().cancelCameraTransitions();
  }

  // Called by the MapLibreMap that shows this controller. Returns where its
  // map's camera starts.
  attach(view: MapView): CameraOptions | undefined {
    this.view = view;
    return this.startCamera;
  }

  // Called by that MapLibreMap as it leaves, so the next map starts where this
  // one left the camera.
  detach(view: MapView): void {
    if (this.view !== view) {
      return;
    }
    const map = view.map;
    if (map !== undefined) {
      this.startCamera = cameraToOptions(map.getSnapshot().view.camera);
    }
    this.view = undefined;
    this.styleLoaded = false;
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
    return new Promise<CameraTransitionOutcome>((resolve, reject) => {
      const appHandler = options?.endHandler?.callback;
      const animation: AnimationOptions = {
        durationMs: options?.durationMs,
        velocity: options?.velocity,
        minZoom: options?.minZoom,
        easing: options?.easing,
        transitionId: options?.transitionId,
        endHandler: {
          callback: (end: CameraTransitionEnd) => {
            appHandler?.(end);
            resolve(end.outcome);
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
