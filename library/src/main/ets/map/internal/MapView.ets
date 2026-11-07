// The map behind a MaplibreMap and the XComponent surface it renders to. It
// creates the FFI map when the component appears, attaches a render session to
// each surface the XComponent reports, makes a new map and session when the
// display's density changes, and disposes everything when the component
// disappears. From FFI's examples/arkui map/MapController.ets.

import {
  AnimationOptions,
  BoundOptions,
  Camera as FfiCamera,
  CameraDelta,
  CameraFitOptions,
  CameraOptions,
  CameraQueryResult,
  CameraTransitionOutcome,
  CameraUpdateMode,
  CommandCompletion,
  FramePacerHandle,
  LatLng as FfiLatLng,
  LogicalSize,
  MapHandle,
  MapMode,
  MapProjectionHandle,
  MapView as FrameView,
  ohosFramePacerCreate,
  RenderDriverKind,
  RenderResult,
  RenderSessionHandle,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeEventType,
  RuntimeHandle,
  ScreenPoint as FfiScreenPoint,
} from '@maplibre/native-ffi';
import geoLocationManager from '@ohos.geoLocationManager';
import { Configuration } from '@ohos.app.ability.Configuration';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import EnvironmentCallback from '@ohos.app.ability.EnvironmentCallback';
import observer from '@ohos.arkui.observer';

import { CameraIdleEvent } from '../../camera/CameraIdleEvent';
import { CameraPosition } from '../../camera/CameraPosition';
import {
  checkCamera,
  CheckedCamera,
  CheckedFit,
  CheckedTransition,
  toBoundOptions,
  toCameraPosition,
  toFfiCamera,
} from '../../camera/internal/FfiCamera';
import { FrameViewport } from '../../camera/internal/FrameViewport';
import {
  addInsets,
  contextScales,
  Insets,
  NO_INSETS,
  paddingInVp,
  paddingInVpOrZero,
  sameInsets,
} from '../../camera/internal/Insets';
import { ContentReconciler, featureClickEvent, hitPaddingOf } from '../../content/internal/ContentReconciler';
import { MapContent } from '../../content/MapContent';
import { LayerPredicate, StyleLayer } from '../../content/StyleLayer';
import { fontScaleOf } from '../../expression/internal/FontScale';
import { toLatLng } from '../../geometry/internal/FfiGeometry';
import { playTick } from '../../interaction/internal/Haptics';
import { GestureTarget, MapGestures } from '../../interaction/internal/MapGestures';
import { FOLLOW_MS, UserLocationLayer } from '../../location/internal/UserLocationLayer';
import { UserLocationIndicatorOptions } from '../../location/UserLocationIndicatorOptions';
import { consumes, logError } from '../../runtime/internal/Log';
import { RuntimeState, RuntimeUser } from '../../runtime/internal/RuntimeRegistry';
import { LoadedStyle } from '../../style/internal/LoadedStyle';
import { CameraBoundsOptions } from '../CameraBoundsOptions';
import { MapClickEvent } from '../MapClickEvent';
import { RenderedFeature } from '../MapController';
import { MapError, StyleLoadError } from '../MapError';
import { styleAttributions } from './Attributions';
import { ControllerState } from './ControllerState';
import { queryRendered } from './Queries';
import { loadStyle } from './StyleLoading';

// One pacer serves every session. It follows the display's VSync, so the
// sessions need no redraw wake.
let framePacer: FramePacerHandle | undefined = undefined;

function getFramePacer(): FramePacerHandle {
  if (framePacer === undefined) {
    framePacer = ohosFramePacerCreate();
  }
  return framePacer;
}

// The map events that the view handles, the only ones its map reports.
const HANDLED_EVENTS: RuntimeEventFlag = RuntimeEventFlag.mapLoadingFailed |
  RuntimeEventFlag.mapRenderError |
  RuntimeEventFlag.mapCameraDidChange |
  RuntimeEventFlag.mapSourceChanged;

// What the view reports to its component, whose handlers don't throw.
export interface MapViewEvents {
  onStyleLoaded: () => void;
  onCameraIdle: (event: CameraIdleEvent) => void;
  onError: (error: MapError) => void;
  // The viewport insets in vp changed, as the view resolved them.
  onViewportInsets: (insets: Insets) => void;
  onGestureStart: () => void;
  onGestureEnd: () => void;
  onMapClick: (event: MapClickEvent) => boolean;
  onMapLongClick: (event: MapClickEvent) => boolean;
  onUnhandledClick: (event: MapClickEvent) => void;
}

// A style's URL, or its document.
type StyleInput = string | Record<string, Object>;

export class MapView extends XComponentController implements GestureTarget, RuntimeUser {
  // The runtime that the view's maps are on, and its FFI runtime once open.
  private runtime: RuntimeState | undefined = undefined;
  private handle: RuntimeHandle | undefined = undefined;
  // The map once it's ready. Before then, its snapshot isn't readable.
  map: MapHandle | undefined = undefined;
  session: RenderSessionHandle | undefined = undefined;
  // The input that moves the map, which the component binds.
  readonly gestures: MapGestures = new MapGestures(this);

  private readonly context: UIContext;
  private readonly events: MapViewEvents;
  // Takes the events that this view's map raises.
  private readonly listener = (event: RuntimeEvent): void => this.onEvent(event);
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
      // fp insets follow the font scale.
      this.applyViewportInsets((error: Error) => this.fail(error));
      // A color resource can have another value in dark mode.
      if (config.colorMode !== undefined && config.colorMode !== this.colorMode) {
        this.colorMode = config.colorMode;
        this.locationLayer.colorModeChanged(this.map);
      }
    },
    onMemoryLevel: (): void => {
    },
  };
  private environmentCallbackId: number | undefined = undefined;
  // The color mode of the last configuration change.
  private colorMode: ConfigurationConstant.ColorMode | undefined = undefined;
  // The state of the controller that the component binds.
  private state: ControllerState | undefined = undefined;
  private disposed: boolean = false;
  // How many times the app has moved the camera, which ends a gesture's say.
  private cameraTakeovers: number = 0;
  // How many gestures the user has started, which end a fit's say.
  gestureStarts: number = 0;
  // The map from when it's created, which the view disposes, and its scale
  // factor: the density it was created at.
  private created: MapHandle | undefined = undefined;
  private scaleFactor: number = 1;
  private style: StyleInput = '';
  // The style as JSON, which a new value must change to load again.
  private styleJson: string = '""';
  private content: MapContent = {};
  private reconciler: ContentReconciler | undefined = undefined;
  // The style that the map loads, until another replaces it.
  private loading: Promise<CommandCompletion> | undefined = undefined;
  // The last valid camera bounds, as FFI takes them, and as JSON.
  private bounds: BoundOptions = toBoundOptions({});
  private boundsJson: string = JSON.stringify(this.bounds);
  private userLocation: geoLocationManager.Location | undefined = undefined;
  private userHeading: number | undefined = undefined;
  private indicatorOptions: UserLocationIndicatorOptions = {};
  // The location indicator, drawn at the map's scale factor.
  private locationLayer: UserLocationLayer;
  // The component's viewportInsets as it gives them, and as JSON, which the
  // view resolves again at each new density.
  private viewportInsets: Padding | LocalizedPadding = {};
  private viewportInsetsJson: string = '{}';
  // The viewport insets in vp, which the map's camera padding includes on top
  // of the app's.
  private insets: Insets = NO_INSETS;
  // The app's camera padding in vp, which only the app's camera changes set:
  // the map's padding is the insets around it, and the camera the app reads
  // has it.
  private padding: Insets = NO_INSETS;

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

  start(state: ControllerState, runtime: RuntimeState, style: StyleInput, content: MapContent,
    bounds: CameraBoundsOptions): void {
    this.state = state;
    this.style = style;
    this.styleJson = JSON.stringify(style);
    this.content = content;
    this.setBounds(bounds);
    this.context.getUIObserver().on('densityUpdate', this.densityListener);
    this.environmentCallbackId = this.context.getHostContext()?.getApplicationContext()
      .on('environment', this.environmentCallback);
    this.runtime = runtime;
    runtime.addUser(this);
    runtime.open().then((handle: RuntimeHandle) => {
      if (this.disposed || runtime.released) {
        return;
      }
      this.handle = handle;
      return this.createMap(true, undefined);
    }).catch((error: Error) => this.fail(error));
  }

  // The app released the runtime, so the view shows no map from now on.
  runtimeReleased(): void {
    this.fail(new MapError('The map\'s runtime was released'));
    this.releaseMap();
    this.handle = undefined;
  }

  // A style document that an app writes in `build()` is a new value each
  // time, so only a change of its JSON loads it again.
  setStyle(style: StyleInput): void {
    const json = JSON.stringify(style);
    if (json === this.styleJson) {
      return;
    }
    this.style = style;
    this.styleJson = json;
    this.applyStyle();
  }

  setContent(content: MapContent): void {
    this.content = content;
    this.reconciler?.setContent(content);
  }

  // Invalid limits are reported, and the map keeps its last limits. Only a
  // change of their JSON applies them.
  setBounds(options: CameraBoundsOptions): void {
    let bounds: BoundOptions;
    try {
      bounds = toBoundOptions(options);
    } catch (error) {
      this.fail(error as Error);
      return;
    }
    const json = JSON.stringify(bounds);
    if (json === this.boundsJson) {
      return;
    }
    this.bounds = bounds;
    this.boundsJson = json;
    this.applyBounds();
  }

  // Options that an app writes in `build()` are a new value each time, so
  // only a change of their JSON resolves the insets again.
  setViewportInsets(insets: Padding | LocalizedPadding): void {
    const json = JSON.stringify(insets);
    if (json === this.viewportInsetsJson) {
      return;
    }
    this.viewportInsets = insets;
    this.viewportInsetsJson = json;
    this.applyViewportInsets((error: Error) => this.fail(error));
  }

  // Resolves the viewport insets at the current density, with an invalid side
  // reported to `report` and taken as 0. The map keeps the app's camera padding
  // inside the new insets, and its center, which moves to the middle of what
  // they leave.
  private applyViewportInsets(report: (error: Error) => void): void {
    const insets = paddingInVpOrZero(this.viewportInsets, 'viewportInsets', contextScales(this.context), report);
    if (sameInsets(this.insets, insets)) {
      return;
    }
    this.insets = insets;
    this.events.onViewportInsets(insets);
    this.map?.discarding.updateCamera({
      mode: CameraUpdateMode.jump,
      camera: { padding: addInsets(insets, this.padding) },
    });
  }

  // The map's camera as the app sees it, with the app's padding.
  appCamera(camera: FfiCamera): CameraPosition {
    return toCameraPosition(camera, this.padding);
  }

  // `camera` as FFI takes it, with its padding, if any, in vp.
  resolveCamera(camera: CheckedCamera): CameraOptions {
    const padding = camera.padding;
    return toFfiCamera(camera, padding === undefined ? undefined : paddingInVp(padding, contextScales(this.context)));
  }

  // Sends the app's camera change, with the insets around its padding. FFI
  // checks the change as it takes it and throws if it rejects it, so the
  // padding becomes the app's only once the map has taken it.
  moveCamera(map: MapHandle, camera: CameraOptions, transition: CheckedTransition, animation: AnimationOptions): void {
    const padding = camera.padding;
    map.discarding.updateCamera({
      mode: transition.mode,
      camera: padding === undefined ? camera : withPadding(camera, addInsets(this.insets, padding)),
      animation: animation,
    });
    if (padding !== undefined) {
      // A copy, since FFI's camera can change later.
      this.padding = addInsets(NO_INSETS, padding);
    }
  }

  // The camera that fits what `query` finds, for `moveCamera()`. FFI's fit
  // keeps its padding as the camera's, so the query fits inside the margin too,
  // and the camera then centers the same view inside the insets and the camera
  // padding alone. Undefined when the map leaves first.
  async fitCamera(options: CheckedFit,
    query: (map: MapHandle, fit: CameraFitOptions) => Promise<CameraOptions>): Promise<CameraOptions | undefined> {
    const map = this.map;
    if (map === undefined) {
      return undefined;
    }
    const scales = contextScales(this.context);
    const cameraPadding = options.cameraPadding === undefined ? this.padding :
      paddingInVp(options.cameraPadding, scales);
    const margin = options.fitPadding === undefined ? NO_INSETS : paddingInVp(options.fitPadding, scales);
    // A layout change during the query leaves a different part of the map to
    // fit in, so the fit asks again.
    let insets: Insets;
    let fitPadding: Insets;
    let fitted: CameraOptions;
    do {
      insets = this.insets;
      fitPadding = addInsets(addInsets(insets, cameraPadding), margin);
      fitted = await query(map, { padding: fitPadding, bearing: options.bearing, pitch: options.pitch });
      if (this.map !== map) {
        return undefined;
      }
    } while (this.insets !== insets);
    const padding = addInsets(insets, cameraPadding);
    const view = map.getSnapshot().view;
    const projection = MapProjectionHandle.create(view);
    let center: FfiLatLng;
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

  // Options that an app writes in `build()` are a new value each time, which
  // the indicator compares with the last.
  setUserLocationIndicator(options: UserLocationIndicatorOptions): void {
    this.indicatorOptions = options;
    this.locationLayer.setOptions(this.map, options);
  }

  private newLocationLayer(scaleFactor: number): UserLocationLayer {
    return new UserLocationLayer(scaleFactor, this.indicatorOptions,
      () => this.reconciler?.applied ?? Promise.resolve(),
      (below: string | LayerPredicate) => this.reconciler?.layerBelow(below, 'userLocationIndicator.below') ?? '',
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
  // and returns whether it did. It waits for the camera moves that wait for
  // the map. A move would stop the user's input, so it waits for the input to
  // end.
  followUserLocation(headingChanged: boolean = false): boolean {
    const map = this.map;
    const location = this.userLocation;
    const state = this.state;
    if (map === undefined || location === undefined || state === undefined || state.view !== this ||
      !state.followReady || !this.gestures.idle) {
      return false;
    }
    const camera = state.followCamera(location, this.userHeading, headingChanged);
    if (camera === undefined) {
      return false;
    }
    map.discarding.updateCamera({
      mode: CameraUpdateMode.ease,
      camera: camera,
      animation: { durationMs: FOLLOW_MS },
    });
    return true;
  }

  // Gestures move the map once it's ready; input before then is dropped, and
  // an animated step ends as the map would end it, after the call, so the
  // gestures don't wait for it.
  applyCameraDelta(delta: CameraDelta): void {
    const map = this.map;
    if (map === undefined) {
      const ended = delta.animation?.endHandler?.callback;
      if (ended !== undefined) {
        Promise.resolve().then(() => ended({
          outcome: CameraTransitionOutcome.closed,
          generation: BigInt(0),
          velocity: { pan: { x: 0, y: 0 }, zoom: 0, bearing: 0, pitch: 0 },
        }));
      }
      return;
    }
    map.discarding.applyCameraDelta(delta);
  }

  cancelTransitions(transitionId: bigint): void {
    this.map?.discarding.cancelCameraTransitionsWithId(transitionId);
  }

  readBearing(read: (bearing: number | undefined) => void): void {
    const map = this.map;
    if (map === undefined) {
      read(undefined);
      return;
    }
    map.getCamera().then((result: CameraQueryResult) => read(this.map === map ? result.camera.bearing : undefined),
      (error: Error) => {
        this.fail(error);
        read(undefined);
      });
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
    return this.shownState()?.followingUserLocation === true;
  }

  // A pan stops following, a rotation keeps the bearing that the user leaves,
  // and a zoom keeps the zoom that the user leaves.
  panned(): void {
    this.shownState()?.stopFollowingUserLocation();
  }

  rotated(): void {
    this.shownState()?.dropFollowedBearing();
  }

  zoomed(): void {
    this.shownState()?.dropFollowZoom();
  }

  // The controller's state while it shows this map.
  private shownState(): ControllerState | undefined {
    const state = this.state;
    return state !== undefined && state.view === this ? state : undefined;
  }

  // FFI raises no event as a gesture ends, so the view reads where the camera
  // came to rest, after the gesture's changes. A camera that follows the
  // location catches up with it, as it waited for the gesture. A map that
  // leaves reports no end.
  gestureEnded(): void {
    if (this.disposed) {
      return;
    }
    // The app may move the camera as the gesture ends; then that move reports
    // where the camera rests.
    const takeovers = this.cameraTakeovers;
    this.events.onGestureEnd();
    const map = this.map;
    if (map === undefined) {
      return;
    }
    map.getCamera().then((result: CameraQueryResult) => {
      if (this.map !== map || !this.gestures.idle || this.cameraTakeovers !== takeovers ||
        map.getSnapshot().transitionInProgress) {
        return;
      }
      if (!this.followUserLocation()) {
        this.cameraIdle(result.camera);
      }
    }).catch((error: Error) => this.fail(error));
  }

  // The coordinate is the one under the click as it happens, before the
  // queries that the layers need.
  clicked(point: FfiScreenPoint, long: boolean): void {
    const map = this.map;
    if (map === undefined || this.disposed) {
      return;
    }
    const projection = MapProjectionHandle.create(map.getSnapshot().view);
    let event: MapClickEvent;
    try {
      event = {
        coordinate: toLatLng(projection.latLngForPixelUnwrapped(point)),
        point: { x: point.x, y: point.y },
      };
    } finally {
      projection.release();
    }
    this.clicks = this.clicks
      .then(() => this.dispatchClick(map, event, long))
      .catch((error: Error) => logError(`A click handler threw: ${error.message}`));
  }

  // The map's handler first, then the layers' from the top down, then the
  // unhandled click. A click whose map or style went away during the query is
  // dropped. A layer's handler that throws doesn't consume the click.
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
        const features = hits.filter((hit: RenderedFeature) => hit.layerId === layer.id)
          .map((hit: RenderedFeature) => hit.feature);
        if (handler !== undefined && features.length > 0 && consumes(`The click handler of layer ${layer.id}`,
          () => handler(featureClickEvent(event, features)))) {
          return;
        }
      }
    }
    if (!long) {
      this.events.onUnhandledClick(event);
    }
  }

  // The features of the layers under the click, with one query for each
  // hitPadding, or undefined if a query fails. Each layer is in one query, so
  // no feature comes twice.
  private async queryClick(layers: StyleLayer[], event: MapClickEvent): Promise<RenderedFeature[] | undefined> {
    const session = this.session;
    if (session === undefined) {
      return [];
    }
    const byPadding = new Map<number, string[]>();
    for (const layer of layers) {
      const padding = hitPaddingOf(layer);
      const ids = byPadding.get(padding) ?? [];
      ids.push(layer.id);
      byPadding.set(padding, ids);
    }
    const queries: Promise<RenderedFeature[]>[] = [];
    byPadding.forEach((ids: string[], padding: number) => {
      queries.push(queryRendered(session, event.point, padding, ids, undefined));
    });
    try {
      const results = await Promise.all(queries);
      let hits: RenderedFeature[] = [];
      for (const result of results) {
        hits = hits.concat(result);
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
    this.runtime?.removeUser(this);
    this.releaseMap();
    this.handle = undefined;
  }

  // Replaces the map and its session with new ones at the new density. The
  // new map starts where the old one left the camera, shows the controller if
  // the old one did, and loads the style and content again.
  private recreateMap(): void {
    const old = this.map;
    const camera = old === undefined ? undefined : this.appCamera(old.getSnapshot().view.camera);
    // A map that isn't ready yet hasn't taken the controller, and its
    // replacement takes it as the map would have.
    const attach = old === undefined || this.state?.view === this;
    this.releaseMap();
    this.createMap(attach, camera).catch((error: Error) => this.fail(error));
  }

  // Releases the map and its session, with the controller keeping the map's
  // camera.
  private releaseMap(): void {
    const map = this.created;
    const session = this.session;
    if (map !== undefined) {
      this.runtime?.removeMap(map);
    }
    const current = this.map;
    this.state?.detach(this, current === undefined ? undefined : this.appCamera(current.getSnapshot().view.camera));
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
    // the map it renders. The runtime closes only after its maps.
    this.targets = this.targets.then(async () => {
      await session?.release();
      map?.dispose();
    }).catch((error: Error) => logError(error.message));
    this.runtime?.track(this.targets);
  }

  // Creates the map at the current density. It takes the controller if
  // `attach`, and its camera starts at `camera` or, without one, at the
  // controller's camera.
  private async createMap(attach: boolean, camera: CameraPosition | undefined): Promise<void> {
    const state = this.state;
    const runtime = this.runtime;
    const handle = this.handle;
    if (this.disposed || state === undefined || runtime === undefined || handle === undefined || runtime.released) {
      return;
    }
    const scaleFactor = this.context.vp2px(1);
    const size = this.logicalSize();
    const map = handle.createMap({
      initialExtent: {
        width: size?.width ?? 1,
        height: size?.height ?? 1,
        scaleFactor: scaleFactor,
      },
      mapMode: MapMode.continuous,
      eventMask: HANDLED_EVENTS,
    });
    runtime.addMap(map, this.listener);
    this.created = map;
    this.scaleFactor = scaleFactor;
    // Insets in px, fp, or lpx change with the density. An invalid side was
    // reported as the component set it.
    this.applyViewportInsets(() => {
    });
    this.locationLayer = this.newLocationLayer(scaleFactor);
    await map.ready;
    if (this.disposed || this.created !== map) {
      return;
    }
    this.map = map;
    this.reconciler = new ContentReconciler(map, (error: Error) => this.fail(error), scaleFactor);
    this.reconciler.setContent(this.content);
    this.reconciler.setFontScale(fontScaleOf(this.context));
    // The controller's camera moves go to the map once it shows a frame, and
    // the map runs commands in order, so they follow the starting camera. The
    // insets go around the start camera's padding.
    if (attach) {
      state.attach(this);
    }
    const startCamera = this.resolveCamera(checkCamera(camera ?? state.camera));
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
    const state = this.state?.view === this ? this.state : undefined;
    if (event.type === RuntimeEventType.mapCameraDidChange) {
      // The camera changes at the end of each jump and animation. Report it
      // once nothing moves it any more.
      const snapshot = map.getSnapshot();
      if (!snapshot.transitionInProgress && !snapshot.gestureInProgress && this.gestures.idle) {
        this.cameraIdle(snapshot.view.camera);
      }
    } else if (event.type === RuntimeEventType.mapSourceChanged) {
      // A source's attribution can arrive after the style, with its TileJSON.
      if (state !== undefined && state.styleLoaded) {
        this.readAttributions(map, state);
      }
    } else if (event.type === RuntimeEventType.mapLoadingFailed) {
      this.fail(new StyleLoadError(event.message));
    } else if (event.type === RuntimeEventType.mapRenderError) {
      this.fail(new MapError(event.message));
    }
  }

  private readAttributions(map: MapHandle, state: ControllerState): void {
    styleAttributions(map).then((attributions: string[]) => {
      // Sources change often, as their data does, so keep an unchanged list.
      if (state.view === this && this.map === map && state.styleLoaded &&
        JSON.stringify(attributions) !== JSON.stringify(state.attributions)) {
        state.attributions = attributions;
      }
    }).catch((error: Error) => this.fail(error));
  }

  private cameraIdle(mapCamera: FfiCamera): void {
    this.events.onCameraIdle({ camera: this.appCamera(mapCamera) });
  }

  private applyStyle(): void {
    const map = this.map;
    if (map === undefined) {
      return;
    }
    const state = this.state;
    if (state !== undefined && state.view === this) {
      state.styleLoaded = false;
      state.loadedStyle = undefined;
      state.attributions = [];
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
      const reconciler = this.reconciler;
      if (current() && reconciler !== undefined) {
        if (state !== undefined && state.view === this) {
          state.styleLoaded = true;
          state.loadedStyle = new LoadedStyle(map, reconciler);
          this.readAttributions(map, state);
        }
        this.events.onStyleLoaded();
        // Above what the content and the app added as the style loaded.
        this.locationLayer.styleLoaded(map, this.userLocation, this.userHeading);
      }
    }, () => {
      // A style that fails to load reports mapLoadingFailed.
    }).catch((error: Error) => logError(error.message));
  }

  // Every limit at once, so those that the app leaves out take their defaults.
  private applyBounds(): void {
    this.map?.discarding.setBounds(this.bounds);
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
    const state = this.state;
    if (view !== undefined && json !== this.frameView && state !== undefined && state.view === this) {
      this.frameView = json;
      state.showFrame(new FrameViewport(view, this.padding));
    }
  }

  // Each failure reaches the app as a MapError.
  fail(error: Error): void {
    logError(error.message);
    if (!this.disposed) {
      this.events.onError(error instanceof MapError ? error : new MapError(error.message));
    }
  }
}

// `camera` with `padding`, and with `center` when it's given.
function withPadding(camera: CameraOptions, padding: Insets | undefined, center?: FfiLatLng): CameraOptions {
  return {
    center: center ?? camera.center,
    centerAltitude: camera.centerAltitude,
    padding: padding,
    anchor: camera.anchor,
    zoom: camera.zoom,
    bearing: camera.bearing,
    pitch: camera.pitch,
    roll: camera.roll,
    fieldOfView: camera.fieldOfView,
  };
}
