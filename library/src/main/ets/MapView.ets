// The map behind a MapLibreMap and the XComponent surface it renders to. It
// creates the FFI map when the component appears, attaches a render session to
// each surface the XComponent reports, and disposes everything when the
// component disappears. From FFI's examples/arkui map/MapController.ets.

import {
  BoundOptions,
  Camera as CameraPosition,
  CameraBounds,
  CameraDelta,
  CameraFitOptions,
  CameraOptions,
  CameraQueryResult,
  CameraTransitionOutcome,
  CameraUpdateMode,
  CommandCompletion,
  EdgeInsets,
  LatLng,
  LogicalSize,
  MapHandle,
  MapMode,
  MapProjectionHandle,
  MapView as FrameView,
  RenderDriverKind,
  RenderResult,
  RenderSessionHandle,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeEventType,
  RuntimeHandle,
  StyleSourceInfo,
} from '@maplibre/native-ffi';
import geoLocationManager from '@ohos.geoLocationManager';

import { ContentReconciler, loadStyle, MapContent } from './Content';
import { GESTURE_ANIMATION_MS, GestureTarget, MapGestures, snapBearing } from './gestures';
import { FOLLOW_MS, UserLocationLayer } from './location';
import { logError } from './log';
import { FitCameraOptions, MapController } from './MapController';
import { addInsets, NO_INSETS, sameInsets, subtractInsets, withoutInsets, withPadding } from './padding';
import {
  addRuntimeEventListener,
  addRuntimeMap,
  getDefaultRuntime,
  getFramePacer,
  removeRuntimeEventListener,
  removeRuntimeMap,
  runtimeEventMask,
} from './runtime';

// The map events that the view handles.
const HANDLED_EVENTS: RuntimeEventFlag = RuntimeEventFlag.mapLoadingFailed |
  RuntimeEventFlag.mapRenderError |
  RuntimeEventFlag.mapCameraDidChange |
  RuntimeEventFlag.mapSourceChanged;

// What the view reports to its component.
export interface MapViewEvents {
  onStyleLoaded: () => void;
  onCameraIdle: (camera: CameraPosition) => void;
  onMapError: (error: Error) => void;
  onGestureStart: () => void;
  onGestureEnd: () => void;
}

export class MapView extends XComponentController implements GestureTarget {
  runtime: RuntimeHandle | undefined = undefined;
  // The map once it's ready. Before then, its snapshot isn't readable.
  map: MapHandle | undefined = undefined;
  session: RenderSessionHandle | undefined = undefined;
  // The input that moves the map, which the component binds.
  readonly gestures: MapGestures = new MapGestures(this);

  private readonly context: UIContext;
  private readonly events: MapViewEvents;
  // Takes the events that this view's map raises.
  private readonly listener = (event: RuntimeEvent): void => {
    if (event.source === this.map?.id) {
      this.onEvent(event);
    }
  };
  private controller: MapController | undefined = undefined;
  private disposed: boolean = false;
  // How many times the app has moved the camera, which ends a gesture's say.
  private cameraTakeovers: number = 0;
  // The map from when it's created, which the view disposes.
  private created: MapHandle | undefined = undefined;
  private style: string = '';
  private content: MapContent | undefined = undefined;
  private reconciler: ContentReconciler | undefined = undefined;
  // The style that the map loads, until another replaces it.
  private loading: Promise<CommandCompletion> | undefined = undefined;
  private bounds: BoundOptions | undefined = undefined;
  // The limits a new map has, which apply again when the app removes its own.
  private defaultBounds: BoundOptions | undefined = undefined;
  private userLocation: geoLocationManager.Location | undefined = undefined;
  private userHeading: number | undefined = undefined;
  private readonly locationLayer: UserLocationLayer;
  // The component's viewportInsets, which the map's camera padding includes on
  // top of the app's.
  private insets: EdgeInsets = NO_INSETS;

  // The component's latest size, its latest surface, and the surface that the
  // session renders to. A surface ID is the one the component reports.
  private size: LogicalSize | undefined = undefined;
  private surface: bigint | undefined = undefined;
  private target: bigint | undefined = undefined;
  // Target changes run one at a time, in the order the component reports them.
  private targets: Promise<void> = Promise.resolve();
  // The view of the last frame shown, as JSON, to skip frames that only
  // redraw it.
  private frameView: string = '';

  constructor(context: UIContext, events: MapViewEvents) {
    super();
    this.context = context;
    this.events = events;
    this.locationLayer = new UserLocationLayer(context.vp2px(1));
  }

  // The surface's size is in physical pixels, and the map's in virtual pixels.
  onSurfaceCreated(surfaceId: string): void {
    this.surface = BigInt(surfaceId);
    this.retarget();
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    this.size = {
      width: Math.max(1, Math.round(this.context.px2vp(rect.surfaceWidth))),
      height: Math.max(1, Math.round(this.context.px2vp(rect.surfaceHeight))),
    };
    if (this.session !== undefined && this.target !== undefined) {
      this.session.discarding.resize(this.size);
    } else {
      this.retarget();
    }
  }

  // The platform is destroying the surface. Release it from the session, and
  // keep the session and its tiles for the next surface.
  onSurfaceDestroyed(surfaceId: string): void {
    const surface = BigInt(surfaceId);
    if (this.surface === surface) {
      this.surface = undefined;
    }
    this.enqueue(async () => {
      if (this.target === surface) {
        this.target = undefined;
        await this.session?.releaseTarget();
      }
    });
  }

  start(controller: MapController, runtime: RuntimeHandle | undefined, style: string,
    content: MapContent | undefined, bounds: BoundOptions | undefined): void {
    this.controller = controller;
    this.style = style;
    this.content = content;
    this.bounds = bounds;
    const runtimeReady = runtime === undefined ? getDefaultRuntime() : Promise.resolve(runtime);
    runtimeReady.then((runtime: RuntimeHandle) => this.createMap(runtime)).catch((error: Error) => this.fail(error));
  }

  setStyle(style: string): void {
    this.style = style;
    this.applyStyle();
  }

  setContent(content: MapContent | undefined): void {
    this.content = content;
    this.reconciler?.setContent(content);
  }

  setBounds(bounds: BoundOptions | undefined): void {
    this.bounds = bounds;
    this.applyBounds();
  }

  // The map keeps the app's camera padding inside the new insets, and its
  // center, which moves to the middle of what they leave.
  setViewportInsets(insets: EdgeInsets): void {
    const previous = this.insets;
    if (sameInsets(previous, insets)) {
      return;
    }
    this.insets = insets;
    const map = this.map;
    if (map !== undefined) {
      const padding = subtractInsets(map.getSnapshot().view.camera.padding, previous);
      map.discarding.updateCamera({ mode: CameraUpdateMode.jump, camera: { padding: addInsets(insets, padding) } });
    }
  }

  // The map's camera as the app sees it, without the insets.
  appCamera(camera: CameraPosition): CameraPosition {
    return withoutInsets(camera, this.insets);
  }

  // The app's camera options as the map takes them, with the insets around the
  // app's padding. Options without padding keep the map's.
  mapCamera(camera: CameraOptions | undefined): CameraOptions | undefined {
    const padding = camera?.padding;
    return camera === undefined || padding === undefined ? camera : withPadding(camera, addInsets(this.insets, padding));
  }

  // The camera that fits what `query` finds, as the map takes it. FFI's fit
  // keeps its padding as the camera's, so the query fits inside the margin too,
  // and the camera then centers the same view inside the insets and the camera
  // padding alone. Undefined when the map leaves first.
  async fitCamera(options: FitCameraOptions,
    query: (map: MapHandle, fit: CameraFitOptions) => Promise<CameraOptions>): Promise<CameraOptions | undefined> {
    const map = this.map;
    if (map === undefined) {
      return undefined;
    }
    const cameraPadding = options.cameraPadding ?? subtractInsets(map.getSnapshot().view.camera.padding, this.insets);
    const fitPadding = addInsets(addInsets(this.insets, cameraPadding), options.fitPadding ?? NO_INSETS);
    const fitted = await query(map, { padding: fitPadding, bearing: options.bearing, pitch: options.pitch });
    if (this.map !== map) {
      return undefined;
    }
    // The insets as they are now, should they have changed during the query.
    const padding = addInsets(this.insets, cameraPadding);
    const view = map.getSnapshot().view;
    const projection = MapProjectionHandle.create(view);
    let center: LatLng;
    try {
      projection.setCamera(withPadding(fitted, fitPadding));
      center = projection.latLngForPixel({
        x: (view.extent.width + padding.left - padding.right) / 2,
        y: (view.extent.height + padding.top - padding.bottom) / 2,
      });
    } finally {
      projection.release();
    }
    return withPadding(fitted, padding, center);
  }

  setUserLocation(location: geoLocationManager.Location | undefined): void {
    this.userLocation = location;
    this.drawUserLocation(false);
  }

  // A compass reports many times a second, so a new heading moves the camera
  // only while it turns with the heading, and other camera changes last.
  setUserHeading(heading: number | undefined): void {
    this.userHeading = heading;
    this.drawUserLocation(true);
  }

  private drawUserLocation(headingChanged: boolean): void {
    const map = this.map;
    if (map !== undefined) {
      this.locationLayer.draw(map, this.userLocation, this.userHeading);
      this.followUserLocation(headingChanged);
    }
  }

  // Moves the camera to the user's location while the controller follows it.
  followUserLocation(headingChanged: boolean = false): void {
    const map = this.map;
    const location = this.userLocation;
    const controller = this.controller;
    if (map === undefined || location === undefined || controller === undefined || controller.map !== map) {
      return;
    }
    const camera = controller.followCamera(location, this.userHeading, headingChanged);
    if (camera !== undefined) {
      map.discarding.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: camera,
        animation: { durationMs: FOLLOW_MS },
      });
    }
  }

  // Gestures move the map once it's ready; input before then is dropped, and
  // an animated step ends at once, so the gestures don't wait for it.
  applyCameraDelta(delta: CameraDelta): void {
    const map = this.map;
    if (map === undefined) {
      delta.animation?.endHandler?.callback?.({ outcome: CameraTransitionOutcome.closed, generation: BigInt(0) });
      return;
    }
    map.discarding.applyCameraDelta(delta);
  }

  /** The app moves the camera, which takes over from the gestures. */
  takeOverCamera(): void {
    // After the stop, so the gesture that it ends sees the takeover too.
    this.gestures.stop();
    this.cameraTakeovers++;
  }

  // The user takes the camera from the location it follows.
  gestureStarted(): void {
    const controller = this.controller;
    if (controller !== undefined && controller.map === this.map) {
      controller.stopFollowingUserLocation();
    }
    this.events.onGestureStart();
  }

  // FFI raises no event as a gesture ends, so the view reads where the camera
  // came to rest, after the gesture's changes. A rotation that ends near north
  // eases to it first, unless input or the app moves the camera again: then
  // the camera rests when that ends.
  gestureEnded(rotated: boolean): void {
    // The app may move the camera as the gesture ends; then that move reports
    // where the camera rests, and nothing snaps it.
    const takeovers = this.cameraTakeovers;
    this.events.onGestureEnd();
    const map = this.map;
    if (map === undefined || this.disposed) {
      return;
    }
    map.getCamera().then((result: CameraQueryResult) => {
      if (this.map !== map || !this.gestures.idle || this.cameraTakeovers !== takeovers ||
        map.getSnapshot().transitionInProgress) {
        return;
      }
      const bearing = rotated ? snapBearing(result.camera.bearing) : undefined;
      if (bearing !== undefined) {
        map.discarding.updateCamera({
          mode: CameraUpdateMode.ease,
          camera: { bearing: bearing },
          animation: { durationMs: GESTURE_ANIMATION_MS },
        });
      } else {
        this.cameraIdle(result.camera);
      }
    }).catch((error: Error) => this.fail(error));
  }

  dispose(): void {
    this.disposed = true;
    this.gestures.dispose();
    const runtime = this.runtime;
    const map = this.created;
    const session = this.session;
    if (runtime !== undefined) {
      // The map goes first, so the mask change that the listener's removal
      // makes skips the map being released.
      if (map !== undefined) {
        removeRuntimeMap(runtime, map);
      }
      removeRuntimeEventListener(runtime, this.listener);
    }
    this.controller?.detach(this);
    this.reconciler?.styleUnloaded();
    this.reconciler = undefined;
    this.runtime = undefined;
    this.created = undefined;
    this.map = undefined;
    this.session = undefined;
    this.target = undefined;
    // After any target change in flight, release the session, and only then
    // the map it renders. The runtime outlives its maps.
    this.targets = this.targets.then(async () => {
      await session?.release();
      map?.dispose();
    }).catch((error: Error) => logError(error.message));
  }

  private async createMap(runtime: RuntimeHandle): Promise<void> {
    const controller = this.controller;
    if (this.disposed || controller === undefined) {
      return;
    }
    // The view's listener asks for the events it handles, so the map reports
    // them with those the app's listeners ask for.
    this.runtime = runtime;
    addRuntimeEventListener(runtime, this.listener, HANDLED_EVENTS);
    const map = runtime.createMap({
      initialExtent: {
        width: this.size?.width ?? 1,
        height: this.size?.height ?? 1,
        scaleFactor: this.context.vp2px(1),
      },
      mapMode: MapMode.continuous,
      eventMask: runtimeEventMask(runtime),
    });
    this.created = map;
    await map.ready;
    if (this.disposed) {
      return;
    }
    this.map = map;
    this.reconciler = new ContentReconciler(map, (error: Error) => this.fail(error));
    this.reconciler.setContent(this.content);
    this.defaultBounds = boundOptions(map.getSnapshot().bounds);
    addRuntimeMap(runtime, map, (error: Error) => this.fail(error));
    // The controller takes camera changes from here on, and the map runs
    // commands in order, so they follow the starting camera.
    // The insets go around the start camera's padding, or the map's, which is
    // none.
    const startCamera: CameraOptions = controller.attach(this) ?? {};
    map.discarding.updateCamera({
      mode: CameraUpdateMode.jump,
      camera: withPadding(startCamera, addInsets(this.insets, startCamera.padding ?? NO_INSETS)),
    });
    this.applyBounds();
    this.applyStyle();
    this.retarget();
    this.followUserLocation();
  }

  private onEvent(event: RuntimeEvent): void {
    const map = this.map;
    if (map === undefined) {
      return;
    }
    // The controller's state is this map's only while the controller shows it.
    const controller = this.controller?.map === map ? this.controller : undefined;
    if (event.type === RuntimeEventType.mapCameraDidChange) {
      // The camera changes at the end of each jump and animation. Report it
      // once nothing moves it any more.
      const snapshot = map.getSnapshot();
      if (!snapshot.transitionInProgress && !snapshot.gestureInProgress && this.gestures.idle) {
        this.cameraIdle(snapshot.view.camera);
      }
    } else if (event.type === RuntimeEventType.mapSourceChanged) {
      // A source's attribution can arrive after the style, with its TileJSON.
      if (controller !== undefined && controller.styleLoaded) {
        this.readAttributions(map, controller);
      }
    } else if (event.type === RuntimeEventType.mapLoadingFailed ||
      event.type === RuntimeEventType.mapRenderError) {
      this.fail(new Error(event.message));
    }
  }

  private readAttributions(map: MapHandle, controller: MapController): void {
    map.listStyleSources().then((sources: readonly StyleSourceInfo[]) => {
      const attributions: string[] = [];
      for (const source of sources) {
        const attribution = source.attribution.trim();
        if (attribution !== '' && !attributions.includes(attribution)) {
          attributions.push(attribution);
        }
      }
      // Sources change often, as their data does, so keep an unchanged list.
      if (controller.map === map && controller.styleLoaded &&
        JSON.stringify(attributions) !== JSON.stringify(controller.attributions)) {
        controller.attributions = attributions;
      }
    }).catch((error: Error) => this.fail(error));
  }

  private cameraIdle(mapCamera: CameraPosition): void {
    const camera = this.appCamera(mapCamera);
    const controller = this.controller;
    if (controller !== undefined && controller.map === this.map) {
      controller.camera = camera;
    }
    this.events.onCameraIdle(camera);
  }

  private applyStyle(): void {
    const map = this.map;
    if (map === undefined) {
      return;
    }
    const controller = this.controller;
    if (controller !== undefined && controller.map === map) {
      controller.styleLoaded = false;
      controller.attributions = [];
    }
    this.locationLayer.styleChanging();
    this.reconciler?.styleUnloaded();
    // Before the new load, which can throw, so no earlier load still counts.
    this.loading = undefined;
    let loading: Promise<CommandCompletion>;
    try {
      loading = loadStyle(map, this.style);
    } catch (error) {
      this.fail(error as Error);
      return;
    }
    this.loading = loading;
    // The style is loaded once its document parses, unless another has
    // replaced it by then. The content goes on before the app hears of it.
    const current = (): boolean => this.loading === loading && this.map === map;
    loading.then(async () => {
      if (current()) {
        await this.reconciler?.styleLoaded();
      }
      if (current()) {
        if (controller !== undefined && controller.map === map) {
          controller.styleLoaded = true;
          this.readAttributions(map, controller);
        }
        this.events.onStyleLoaded();
        // Above what the content and the app added as the style loaded.
        this.locationLayer.styleLoaded(map, this.userLocation, this.userHeading);
      }
    }, () => {
      // A style that fails to load reports mapLoadingFailed.
    }).catch((error: Error) => logError(error.message));
  }

  // The limits that the app leaves out keep the map's defaults, not the app's
  // earlier limits.
  private applyBounds(): void {
    const map = this.map;
    if (map === undefined || this.defaultBounds === undefined) {
      return;
    }
    map.discarding.setBounds(this.defaultBounds);
    if (this.bounds !== undefined) {
      map.discarding.setBounds(this.bounds);
    }
  }

  // Gives the session the component's latest surface, attaching the session
  // first if there is none.
  private retarget(): void {
    this.enqueue(async () => {
      // The component can report its surface before the map is ready, which
      // retargets once it is.
      const map = this.map;
      const size = this.size;
      const surface = this.surface;
      if (map === undefined || size === undefined || surface === undefined ||
        surface === this.target) {
        return;
      }
      this.target = surface;
      if (this.session === undefined) {
        // The session renders on a library thread, in a graphics context that
        // the library makes for the window.
        const session = map.attachOhosSurface({ logicalSize: size, surfaceId: surface }, undefined, {
          driver: RenderDriverKind.coreWorker,
          frameWake: { callback: () => this.drainFrameResults() },
        });
        this.session = session;
        session.setFramePacer(getFramePacer());
        await session.ready;
      } else {
        await this.session.setOhosSurfaceTarget({ logicalSize: size, surfaceId: surface });
      }
    });
  }

  private enqueue(change: () => Promise<void>): void {
    this.targets = this.targets
      .then(() => this.disposed ? undefined : change())
      .catch((error: Error) => this.fail(error));
  }

  // The pacer demands the frames, and the frame wake reports how they went.
  private drainFrameResults(): void {
    const session = this.session;
    if (session === undefined) {
      return;
    }
    const results = session.drainFrameResults();
    if (results.some((result) => result.disposition === RenderResult.failed)) {
      this.fail(new Error(`The map failed to render a frame: ${session.getFailure()}`));
    }
    // Overlays follow the view of the latest frame drawn.
    let view: FrameView | undefined = undefined;
    for (const result of results) {
      if (result.disposition === RenderResult.rendered) {
        view = result.view;
      }
    }
    const json = view === undefined ? '' : JSON.stringify(view);
    const controller = this.controller;
    if (view !== undefined && json !== this.frameView && controller !== undefined &&
      controller.map === this.map) {
      this.frameView = json;
      controller.showFrame(view);
    }
  }

  // An error handler that throws doesn't reach ArkUI, which would end the app,
  // or the map's own callbacks.
  private fail(error: Error): void {
    logError(error.message);
    if (this.disposed) {
      return;
    }
    try {
      this.events.onMapError(error);
    } catch (thrown) {
      logError(`onMapError threw: ${(thrown as Error).message}`);
    }
  }
}

function boundOptions(bounds: CameraBounds): BoundOptions {
  return {
    bounds: bounds.unbounded ? undefined : bounds.bounds,
    unbounded: bounds.unbounded,
    minZoom: bounds.minZoom,
    maxZoom: bounds.maxZoom,
    minPitch: bounds.minPitch,
    maxPitch: bounds.maxPitch,
  };
}
