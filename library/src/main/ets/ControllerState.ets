// The state behind a MapController, which the map that shows it reads and
// changes. Internal: a MapController keeps one, and the MaplibreMap finds it
// through `controllerState()`. Neither it nor what it reaches refers back to
// the controller, so a controller that the app drops can go.

import {
  AnimationOptions,
  CameraFitOptions,
  CameraOptions,
  CameraTransitionEnd,
  CameraTransitionOutcome,
  MapHandle,
  RenderSessionHandle,
} from '@maplibre/native-ffi';
import geoLocationManager from '@ohos.geoLocationManager';

import { CameraPosition } from './CameraPosition';
import { CheckedCamera, CheckedFit, CheckedTransition } from './FfiValues';
import { ScreenPoint } from './Geometry';
import { FollowBearing, FollowUserLocationOptions, course } from './location';
import { MapView } from './MapView';
import {
  queryRendered,
  querySource,
  RenderedFeature,
  RenderedFeatureQueryOptions,
  SourceFeature,
  SourceFeatureQueryOptions,
} from './Queries';
import { FrameViewport } from './Viewport';

// A camera move that waits for a map to show the controller at its size.
interface WaitingMove {
  start: (view: MapView) => Promise<boolean>;
  resolve: (completed: boolean) => void;
  reject: (error: Error) => void;
}

@ObservedV2
export class ControllerState {
  @Trace camera: CameraPosition;
  @Trace viewport: FrameViewport | undefined = undefined;
  @Trace styleLoaded: boolean = false;
  @Trace attributions: string[] = [];
  @Trace followingUserLocation: boolean = false;
  // The map that shows the controller, and whether it has shown a frame at its
  // size, from which camera moves go to it.
  view: MapView | undefined = undefined;
  private sized: boolean = false;
  // Counts the batches of moves that waited for a map, and whether the latest
  // is still running, which holds the camera's following until it ends.
  private settles: number = 0;
  private settling: boolean = false;
  private waiting: WaitingMove[] = [];
  private followOptions: FollowUserLocationOptions = {};
  // The zoom that the next move to follow the location takes.
  private followZoom: number | undefined = undefined;
  // How many times the app has moved the camera, so a fit that's still
  // finding its camera gives way.
  private moves: number = 0;

  constructor(camera: CameraPosition) {
    this.camera = camera;
  }

  // Whether camera moves go to the map now.
  get ready(): boolean {
    return this.view !== undefined && this.sized;
  }

  // Whether the camera may move to follow the user's location now: once the
  // moves that waited for the map end.
  get followReady(): boolean {
    return this.ready && !this.settling;
  }

  // A map takes the controller from any map that had it.
  attach(view: MapView): void {
    this.view = view;
    this.sized = false;
    this.settles++;
    this.settling = false;
    this.styleLoaded = false;
    this.attributions = [];
    this.showFrame(undefined);
  }

  // The map leaves, with the camera where it left it, if it had one.
  detach(view: MapView, camera: CameraPosition | undefined): void {
    if (this.view !== view) {
      return;
    }
    if (camera !== undefined) {
      this.camera = camera;
    }
    this.view = undefined;
    this.sized = false;
    this.settles++;
    this.settling = false;
    this.styleLoaded = false;
    this.attributions = [];
    this.showFrame(undefined);
  }

  // The map that shows the controller drew a frame, or shows none. Its first
  // frame is at its size, and the moves that wait go to it, then the camera
  // catches up with the user's location.
  showFrame(viewport: FrameViewport | undefined): void {
    this.viewport?.retire();
    this.viewport = viewport;
    const view = this.view;
    if (viewport === undefined || view === undefined || this.sized) {
      return;
    }
    this.sized = true;
    const waiting = this.waiting;
    this.waiting = [];
    if (waiting.length === 0) {
      view.followUserLocation();
      return;
    }
    // Following starts once the moves that waited for the map end, so a fit
    // that's still finding its camera can't move it away afterwards.
    const settle = ++this.settles;
    this.settling = true;
    const ended = waiting.map((move: WaitingMove) => this.start(view, move.start).then(
      (completed: boolean) => move.resolve(completed), (error: Error) => move.reject(error)));
    Promise.all(ended).then(() => {
      if (this.settles !== settle) {
        return;
      }
      this.settling = false;
      if (this.view === view) {
        view.followUserLocation();
      }
    });
  }

  updateCamera(camera: CheckedCamera, transition: CheckedTransition): Promise<boolean> {
    return this.move((view: MapView) => this.transition(view, transition,
      (map: MapHandle, animation: AnimationOptions) =>
        view.moveCamera(map, view.resolveCamera(camera), transition, animation)));
  }

  // Finds the camera for a fit, then moves it there, unless the map leaves, or
  // the app or the user moves the camera first.
  fit(options: CheckedFit, query: (map: MapHandle, fit: CameraFitOptions) => Promise<CameraOptions>): Promise<boolean> {
    return this.move(async (view: MapView) => {
      this.takeOverCamera(view);
      const moves = this.moves;
      const gestures = view.gestureStarts;
      const camera = await view.fitCamera(options, query);
      if (camera === undefined || this.view !== view || this.moves !== moves || view.gestureStarts !== gestures) {
        return false;
      }
      return this.transition(view, options.transition, (map: MapHandle, animation: AnimationOptions) =>
        view.moveCamera(map, camera, options.transition, animation));
    });
  }

  cancelCameraTransitions(): void {
    const waiting = this.waiting;
    this.waiting = [];
    waiting.forEach((move: WaitingMove) => move.resolve(false));
    this.moves++;
    const view = this.view;
    if (view !== undefined) {
      view.takeOverCamera();
      view.map?.discarding.cancelCameraTransitions();
    }
  }

  followUserLocation(options: FollowUserLocationOptions | undefined): void {
    this.followOptions = options ?? {};
    this.followZoom = options?.zoom;
    this.followingUserLocation = true;
    const view = this.view;
    if (view !== undefined && this.ready) {
      this.takeOverCamera(view);
      view.followUserLocation();
    }
  }

  // Where the map moves the camera for `location` and `heading`, or undefined
  // while the camera doesn't follow them. A new heading alone, which
  // `headingChanged` says, moves the camera only while it turns with the
  // heading.
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

  // Undefined while no map shows a frame, or once the map that answers goes.
  async queryRenderedFeatures(point: ScreenPoint, hitPadding: number,
    options: RenderedFeatureQueryOptions | undefined): Promise<RenderedFeature[] | undefined> {
    const session = this.frameSession();
    if (session === undefined) {
      return undefined;
    }
    try {
      const features = await queryRendered(session, point, hitPadding, options?.layers, options?.filter);
      return this.frameSession() === session ? features : undefined;
    } catch (error) {
      if (this.frameSession() !== session) {
        return undefined;
      }
      throw error as Error;
    }
  }

  async querySourceFeatures(sourceId: string,
    options: SourceFeatureQueryOptions | undefined): Promise<SourceFeature[] | undefined> {
    const session = this.frameSession();
    if (session === undefined) {
      return undefined;
    }
    try {
      const features = await querySource(session, sourceId, options);
      return this.frameSession() === session ? features : undefined;
    } catch (error) {
      if (this.frameSession() !== session) {
        return undefined;
      }
      throw error as Error;
    }
  }

  withFfiMap<T>(block: (map: MapHandle, session: RenderSessionHandle | undefined) => T): T | undefined {
    const view = this.view;
    const map = view?.map;
    return view === undefined || map === undefined ? undefined : block(map, view.session);
  }

  // The session of the map that shows a frame.
  private frameSession(): RenderSessionHandle | undefined {
    return this.viewport === undefined ? undefined : this.view?.session;
  }

  // Starts `start` on the map once it shows the controller at its size, after
  // the moves that wait for it.
  private move(start: (view: MapView) => Promise<boolean>): Promise<boolean> {
    const view = this.view;
    if (view !== undefined && this.sized && this.waiting.length === 0) {
      return this.start(view, start);
    }
    return new Promise<boolean>((resolve, reject) => {
      this.waiting.push({ start: start, resolve: resolve, reject: reject });
    });
  }

  private start(view: MapView, start: (view: MapView) => Promise<boolean>): Promise<boolean> {
    try {
      return start(view);
    } catch (error) {
      return Promise.reject(error as Error);
    }
  }

  // The app's camera change takes over from a gesture's momentum, and from a
  // fit that's still finding its camera.
  private takeOverCamera(view: MapView): void {
    view.takeOverCamera();
    this.moves++;
  }

  // Starts a camera change whose animation ends with FFI's end handler, and
  // resolves whether it completed. A jump runs the handler as soon as the
  // camera moves. A map that went first ends the change.
  private transition(view: MapView, transition: CheckedTransition,
    start: (map: MapHandle, animation: AnimationOptions) => void): Promise<boolean> {
    const map = view.map;
    if (map === undefined || this.view !== view) {
      return Promise.resolve(false);
    }
    this.takeOverCamera(view);
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
}
