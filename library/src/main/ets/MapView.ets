// The map behind a MapLibreMap and the XComponent surface it renders to. It
// creates the FFI map when the component appears, attaches a render session to
// each surface the XComponent reports, makes a new map and session when the
// display's density changes, and disposes everything when the component
// disappears. From FFI's examples/arkui map/MapController.ets.

import {
  BoundOptions,
  Camera as CameraPosition,
  CameraDelta,
  CameraFitOptions,
  CameraOptions,
  CameraQueryResult,
  CameraTransitionOutcome,
  CameraUpdate,
  CameraUpdateMode,
  cameraToOptions,
  CommandCompletion,
  EdgeInsets,
  LatLng,
  LogicalSize,
  MapHandle,
  MapMode,
  MapProjectionHandle,
  MapView as FrameView,
  RenderDriverKind,
  RenderedFeature,
  RenderedQueryGeometry,
  RenderResult,
  RenderSessionHandle,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeEventType,
  RuntimeHandle,
  ScreenPoint,
  StyleSourceInfo,
} from '@maplibre/native-ffi';
import { Configuration } from '@ohos.app.ability.Configuration';
import EnvironmentCallback from '@ohos.app.ability.EnvironmentCallback';
import observer from '@ohos.arkui.observer';
import geoLocationManager from '@ohos.geoLocationManager';

import { ContentReconciler, loadStyle, MapClickEvent, MapContent, MapLayer } from './Content';
import { fontScaleOf } from './fontScale';
import { GESTURE_ANIMATION_MS, GestureTarget, MapGestures, snapBearing } from './gestures';
import { playTick } from './haptics';
import { FOLLOW_MS, UserLocationIndicatorOptions, UserLocationLayer } from './location';
import { logError } from './log';
import { FitCameraOptions, MapController } from './MapController';
import { addInsets, NO_INSETS, sameInsets, withAppPadding, withPadding } from './padding';
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

// The limits that FFI gives a new map, from MapLibre Native's defaults, which
// apply again when the app removes its own.
const DEFAULT_BOUNDS: BoundOptions = { unbounded: true, minZoom: 0, maxZoom: 22, minPitch: 0, maxPitch: 60 };

// What the view reports to its component.
export interface MapViewEvents {
  onStyleLoaded: () => void;
  onCameraIdle: (camera: CameraPosition) => void;
  onMapError: (error: Error) => void;
  onGestureStart: () => void;
  onGestureEnd: () => void;
  onMapClick: (event: MapClickEvent) => boolean;
  onMapLongClick: (event: MapClickEvent) => boolean;
  onUnhandledClick: (event: MapClickEvent) => void;
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
  // FFI fixes a map's scale factor for its life, so a new density takes a new
  // map.
  private readonly densityListener = (info: observer.DensityInfo): void => {
    if (this.created !== undefined && info.density !== this.scaleFactor) {
      this.recreateMap();
    }
  };
  // The user's font size setting reaches the app as a configuration change.
  private readonly environmentCallback: EnvironmentCallback = {
    onConfigurationUpdated: (config: Configuration): void => {
      this.reconciler?.setFontScale(fontScaleOf(this.context));
    },
    onMemoryLevel: (): void => {
    },
  };
  private environmentCallbackId: number | undefined = undefined;
  private controller: MapController | undefined = undefined;
  private disposed: boolean = false;
  // How many times the app has moved the camera, which ends a gesture's say.
  private cameraTakeovers: number = 0;
  // How many gestures the user has started, which end a fit's say.
  gestureStarts: number = 0;
  // The map from when it's created, which the view disposes, and its scale
  // factor: the density it was created at.
  private created: MapHandle | undefined = undefined;
  private scaleFactor: number = 1;
  private style: string = '';
  private content: MapContent | undefined = undefined;
  private reconciler: ContentReconciler | undefined = undefined;
  // The style that the map loads, until another replaces it.
  private loading: Promise<CommandCompletion> | undefined = undefined;
  private bounds: BoundOptions | undefined = undefined;
  private userLocation: geoLocationManager.Location | undefined = undefined;
  private userHeading: number | undefined = undefined;
  private indicatorOptions: UserLocationIndicatorOptions = {};
  // The location indicator, drawn at the map's scale factor.
  private locationLayer: UserLocationLayer;
  // The component's viewportInsets, which the map's camera padding includes on
  // top of the app's.
  private insets: EdgeInsets = NO_INSETS;
  // The app's camera padding, which only the app's camera changes set: the
  // map's padding is the insets around it, and the camera the app reads has
  // it.
  private padding: EdgeInsets = NO_INSETS;

  // The component's latest size in px, its latest surface, and the surface
  // that the session renders to. A surface ID is the one the component
  // reports.
  private surfaceSize: SurfaceRect | undefined = undefined;
  private surface: bigint | undefined = undefined;
  private target: bigint | undefined = undefined;
  // Target changes run one at a time, in the order the component reports them.
  private targets: Promise<void> = Promise.resolve();
  // Clicks reach the app one at a time, in order, across their queries.
  private clicks: Promise<void> = Promise.resolve();
  // The view of the last frame shown, as JSON, to skip frames that only
  // redraw it.
  private frameView: string = '';

  constructor(context: UIContext, events: MapViewEvents) {
    super();
    this.context = context;
    this.events = events;
    this.locationLayer = this.newLocationLayer(context.vp2px(1));
  }

  onSurfaceCreated(surfaceId: string): void {
    this.surface = BigInt(surfaceId);
    this.retarget();
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    this.surfaceSize = rect;
    const size = this.logicalSize();
    if (this.session !== undefined && this.target !== undefined && size !== undefined) {
      this.session.discarding.resize(size);
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
    this.context.getUIObserver().on('densityUpdate', this.densityListener);
    this.environmentCallbackId = this.context.getHostContext()?.getApplicationContext()
      .on('environment', this.environmentCallback);
    const runtimeReady = runtime === undefined ? getDefaultRuntime() : Promise.resolve(runtime);
    runtimeReady.then((runtime: RuntimeHandle) => {
      if (this.disposed) {
        return;
      }
      // The view's listener asks for the events it handles, so the map reports
      // them with those the app's listeners ask for.
      this.runtime = runtime;
      addRuntimeEventListener(runtime, this.listener, HANDLED_EVENTS);
      return this.createMap(true, undefined);
    }).catch((error: Error) => this.fail(error));
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
    if (sameInsets(this.insets, insets)) {
      return;
    }
    this.insets = insets;
    this.map?.discarding.updateCamera({
      mode: CameraUpdateMode.jump,
      camera: { padding: addInsets(insets, this.padding) },
    });
  }

  // The map's camera as the app sees it, with the app's padding.
  appCamera(camera: CameraPosition): CameraPosition {
    return withAppPadding(camera, this.padding);
  }

  // Sends the app's camera change, with the insets around its padding. FFI
  // checks the change as it takes it and throws if it rejects it, so the
  // padding becomes the app's only once the map has taken it. FFI checks the
  // padding with the insets added, which can cover a negative one, so the
  // view checks the app's own first.
  updateCamera(map: MapHandle, update: CameraUpdate): void {
    const camera = update.camera;
    const padding = camera?.padding;
    if (camera === undefined || padding === undefined) {
      map.discarding.updateCamera(update);
      return;
    }
    const sides = [padding.top, padding.left, padding.bottom, padding.right];
    if (!sides.every((side: number) => Number.isFinite(side) && side >= 0)) {
      throw new Error(`Camera padding must be finite and at least 0: ${JSON.stringify(padding)}`);
    }
    map.discarding.updateCamera({
      mode: update.mode,
      camera: withPadding(camera, addInsets(this.insets, padding)),
      gesturePhase: update.gesturePhase,
      animation: update.animation,
    });
    // A copy, since the app can change its object later.
    this.padding = addInsets(NO_INSETS, padding);
  }

  // The camera that fits what `query` finds, for `updateCamera()`. FFI's fit
  // keeps its padding as the camera's, so the query fits inside the margin too,
  // and the camera then centers the same view inside the insets and the camera
  // padding alone. Undefined when the map leaves first.
  async fitCamera(options: FitCameraOptions,
    query: (map: MapHandle, fit: CameraFitOptions) => Promise<CameraOptions>): Promise<CameraOptions | undefined> {
    const map = this.map;
    if (map === undefined) {
      return undefined;
    }
    const cameraPadding = options.cameraPadding ?? this.padding;
    // A layout change during the query leaves a different part of the map to
    // fit in, so the fit asks again.
    let insets: EdgeInsets;
    let fitPadding: EdgeInsets;
    let fitted: CameraOptions;
    do {
      insets = this.insets;
      fitPadding = addInsets(addInsets(insets, cameraPadding), options.fitPadding ?? NO_INSETS);
      fitted = await query(map, { padding: fitPadding, bearing: options.bearing, pitch: options.pitch });
      if (this.map !== map) {
        return undefined;
      }
    } while (this.insets !== insets);
    const padding = addInsets(insets, cameraPadding);
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
    return withPadding(fitted, cameraPadding, center);
  }

  // Options that an app writes in `build()` are a new value each time, so
  // only a change of their JSON draws the indicator again.
  setUserLocationIndicator(options: UserLocationIndicatorOptions): void {
    if (JSON.stringify(options) === JSON.stringify(this.indicatorOptions)) {
      return;
    }
    this.indicatorOptions = options;
    this.locationLayer.setOptions(this.map, options);
    const map = this.map;
    if (map !== undefined) {
      this.locationLayer.draw(map, this.userLocation, this.userHeading);
    }
  }

  private newLocationLayer(scaleFactor: number): UserLocationLayer {
    return new UserLocationLayer(scaleFactor, this.indicatorOptions,
      () => this.reconciler?.applied ?? Promise.resolve(), (id: string) => this.reconciler?.hasLayer(id) ?? false,
      (error: Error) => this.fail(error));
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

  // Moves the camera to the user's location while the controller follows it,
  // and returns whether it did. A move would stop the user's input, so it
  // waits for the input to end; the camera turns to `snapBearing` when it
  // doesn't follow a bearing of its own.
  followUserLocation(headingChanged: boolean = false, snapBearing?: number): boolean {
    const map = this.map;
    const location = this.userLocation;
    const controller = this.controller;
    if (map === undefined || location === undefined || controller === undefined || controller.map !== map ||
      !this.gestures.idle) {
      return false;
    }
    const camera = controller.followCamera(location, this.userHeading, headingChanged);
    if (camera === undefined) {
      return false;
    }
    if (camera.bearing === undefined) {
      camera.bearing = snapBearing;
    }
    map.discarding.updateCamera({
      mode: CameraUpdateMode.ease,
      camera: camera,
      animation: { durationMs: FOLLOW_MS },
    });
    return true;
  }

  // Gestures move the map once it's ready; input before then is dropped, and
  // an animated step ends at once, so the gestures don't wait for it.
  applyCameraDelta(delta: CameraDelta): void {
    const map = this.map;
    if (map === undefined) {
      delta.animation?.endHandler?.callback?.({
        outcome: CameraTransitionOutcome.closed,
        generation: BigInt(0),
        velocity: { pan: { x: 0, y: 0 }, zoom: 0, bearing: 0, pitch: 0 },
      });
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

  getBearing(): number {
    return this.map?.getSnapshot().view.camera.bearing ?? 0;
  }

  hapticTick(): void {
    playTick();
  }

  gestureStarted(): void {
    this.gestureStarts++;
    this.events.onGestureStart();
  }

  // While the camera follows the location, which is at its center.
  keepsCenter(): boolean {
    const controller = this.controller;
    return controller !== undefined && controller.map === this.map && controller.followingUserLocation;
  }

  // FFI raises no event as a gesture ends, so the view reads where the camera
  // came to rest, after the gesture's changes. A rotation that ends near a
  // snap bearing eases to it first, unless input or the app moves the camera
  // again: then the camera rests when that ends. A camera that follows the
  // location catches up with it, as it waited for the gesture.
  gestureEnded(snapBearings: number[]): void {
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
      const bearing = snapBearing(result.camera.bearing, snapBearings);
      if (this.followUserLocation(false, bearing)) {
        return;
      }
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

  // The coordinate is the one under the click as it happens, before the
  // queries that the layers need.
  clicked(point: ScreenPoint, long: boolean): void {
    const map = this.map;
    if (map === undefined || this.disposed) {
      return;
    }
    const projection = MapProjectionHandle.create(map.getSnapshot().view);
    let event: MapClickEvent;
    try {
      event = { x: point.x, y: point.y, coordinate: projection.latLngForPixel(point) };
    } finally {
      projection.release();
    }
    this.clicks = this.clicks
      .then(() => this.dispatchClick(map, event, long))
      .catch((error: Error) => logError(`A click handler threw: ${error.message}`));
  }

  // The map's handler first, then the layers' from the top down, then the
  // unhandled click. A click whose map or style went away during the query is
  // dropped.
  private async dispatchClick(map: MapHandle, event: MapClickEvent, long: boolean): Promise<void> {
    const reconciler = this.reconciler;
    if (this.map !== map || reconciler === undefined) {
      return;
    }
    if (long ? this.events.onMapLongClick(event) : this.events.onMapClick(event)) {
      return;
    }
    const layers = reconciler.clickableLayers(long);
    if (layers.length > 0) {
      const generation = reconciler.styleGeneration;
      const hits = await this.queryClick(layers, event);
      if (this.map !== map || this.reconciler !== reconciler || reconciler.styleGeneration !== generation ||
        hits === undefined) {
        return;
      }
      for (const layer of layers) {
        const handler = long ? layer.onLongClick : layer.onClick;
        const features = hits.filter((hit: RenderedFeature) => hit.layerId === layer.id);
        if (handler !== undefined && features.length > 0 && handler(features, event)) {
          return;
        }
      }
    }
    if (!long) {
      this.events.onUnhandledClick(event);
    }
  }

  // The features of the layers under the click, with one query for each
  // hitPadding, or undefined if a query fails.
  private async queryClick(layers: MapLayer[], event: MapClickEvent): Promise<RenderedFeature[] | undefined> {
    const session = this.session;
    if (session === undefined) {
      return [];
    }
    const byPadding = new Map<number, string[]>();
    for (const layer of layers) {
      const padding = Math.max(0, layer.hitPadding ?? 0);
      const ids = byPadding.get(padding) ?? [];
      ids.push(layer.id);
      byPadding.set(padding, ids);
    }
    const queries: Promise<readonly RenderedFeature[]>[] = [];
    byPadding.forEach((ids: string[], padding: number) => {
      const geometry: RenderedQueryGeometry = padding === 0 ?
        { kind: 'point', value: { x: event.x, y: event.y } } :
        {
          kind: 'box',
          value: {
            min: { x: event.x - padding, y: event.y - padding },
            max: { x: event.x + padding, y: event.y + padding },
          },
        };
      queries.push(session.queryRenderedFeatures(geometry, { layerIds: ids }));
    });
    try {
      const results = await Promise.all(queries);
      let hits: RenderedFeature[] = [];
      for (const result of results) {
        hits = hits.concat(Array.from(result));
      }
      return hits;
    } catch (error) {
      this.fail(error as Error);
      return undefined;
    }
  }

  dispose(): void {
    this.disposed = true;
    this.context.getUIObserver().off('densityUpdate', this.densityListener);
    if (this.environmentCallbackId !== undefined) {
      this.context.getHostContext()?.getApplicationContext().off('environment', this.environmentCallbackId);
    }
    this.gestures.dispose();
    const runtime = this.runtime;
    // The map goes first, so the mask change that the listener's removal makes
    // skips the map being released.
    this.releaseMap();
    if (runtime !== undefined) {
      removeRuntimeEventListener(runtime, this.listener);
    }
    this.runtime = undefined;
  }

  // Replaces the map and its session with new ones at the new density. The
  // new map starts where the old one left the camera, shows the controller if
  // the old one did, and loads the style and content again.
  private recreateMap(): void {
    const old = this.map;
    const camera = old === undefined ? undefined : this.appCamera(old.getSnapshot().view.camera);
    // A map that isn't ready yet hasn't taken the controller, and its
    // replacement takes it as the map would have.
    const attach = old === undefined || this.controller?.map === old;
    this.releaseMap();
    this.createMap(attach, camera).catch((error: Error) => this.fail(error));
  }

  // Releases the map and its session, with the controller keeping the map's
  // camera.
  private releaseMap(): void {
    const runtime = this.runtime;
    const map = this.created;
    const session = this.session;
    if (runtime !== undefined && map !== undefined) {
      removeRuntimeMap(runtime, map);
    }
    this.controller?.detach(this);
    this.reconciler?.styleUnloaded();
    this.locationLayer.styleChanging();
    this.reconciler = undefined;
    this.created = undefined;
    this.map = undefined;
    this.session = undefined;
    this.target = undefined;
    this.loading = undefined;
    this.frameView = '';
    // After any target change in flight, release the session, and only then
    // the map it renders. The runtime outlives its maps.
    this.targets = this.targets.then(async () => {
      await session?.release();
      map?.dispose();
    }).catch((error: Error) => logError(error.message));
  }

  // Creates the map at the current density. It takes the controller if
  // `attach`, and its camera starts at `camera` or, without one, where the
  // controller says.
  private async createMap(attach: boolean, camera: CameraPosition | undefined): Promise<void> {
    const controller = this.controller;
    const runtime = this.runtime;
    if (this.disposed || controller === undefined || runtime === undefined) {
      return;
    }
    const scaleFactor = this.context.vp2px(1);
    const size = this.logicalSize();
    const map = runtime.createMap({
      initialExtent: {
        width: size?.width ?? 1,
        height: size?.height ?? 1,
        scaleFactor: scaleFactor,
      },
      mapMode: MapMode.continuous,
      eventMask: runtimeEventMask(runtime),
    });
    this.created = map;
    this.scaleFactor = scaleFactor;
    this.locationLayer = this.newLocationLayer(scaleFactor);
    await map.ready;
    if (this.disposed || this.created !== map) {
      return;
    }
    this.map = map;
    this.reconciler = new ContentReconciler(map, (error: Error) => this.fail(error));
    this.reconciler.setContent(this.content);
    this.reconciler.setFontScale(fontScaleOf(this.context));
    addRuntimeMap(runtime, map, (error: Error) => this.fail(error));
    // The controller takes camera changes from here on, and the map runs
    // commands in order, so they follow the starting camera.
    // The insets go around the start camera's padding, or the map's, which is
    // none.
    const attached = attach ? controller.attach(this) : undefined;
    const startCamera: CameraOptions = (camera !== undefined ? cameraToOptions(camera) : attached) ?? {};
    this.padding = addInsets(NO_INSETS, startCamera.padding ?? NO_INSETS);
    map.discarding.updateCamera({
      mode: CameraUpdateMode.jump,
      camera: withPadding(startCamera, addInsets(this.insets, this.padding)),
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
    if (map === undefined) {
      return;
    }
    map.discarding.setBounds(DEFAULT_BOUNDS);
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
      const size = this.logicalSize();
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
        try {
          await session.ready;
        } catch (error) {
          // A session that fails to attach takes no calls but its release,
          // which the view makes unless the map went and took it along. The
          // surface stays the target, so its changes don't attach again, and
          // the next surface gets a new session.
          if (this.session === session) {
            this.session = undefined;
            await session.release().catch((released: Error) => logError(released.message));
          }
          throw error as Error;
        }
      } else {
        await this.session.setOhosSurfaceTarget({ logicalSize: size, surfaceId: surface });
      }
    });
  }

  // The surface's size is in px, and the map's in vp at the current density.
  private logicalSize(): LogicalSize | undefined {
    const rect = this.surfaceSize;
    if (rect === undefined) {
      return undefined;
    }
    return {
      width: Math.max(1, Math.round(this.context.px2vp(rect.surfaceWidth))),
      height: Math.max(1, Math.round(this.context.px2vp(rect.surfaceHeight))),
    };
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

