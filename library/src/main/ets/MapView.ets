// The map behind a MapLibreMap and the XComponent surface it renders to. It
// creates the FFI map when the component appears, attaches a render session to
// each surface the XComponent reports, and disposes everything when the
// component disappears. From FFI's examples/arkui map/MapController.ets.

import {
  BoundOptions,
  Camera as CameraPosition,
  CameraBounds,
  CameraUpdateMode,
  LogicalSize,
  MapHandle,
  MapMode,
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

import { MapController } from './MapController';
import { addRuntimeEventListener, getDefaultRuntime, getFramePacer, removeRuntimeEventListener } from './runtime';

// What the view reports to its component.
export interface MapViewEvents {
  onStyleLoaded: () => void;
  onCameraIdle: (camera: CameraPosition) => void;
  onMapError: (error: Error) => void;
}

export class MapView extends XComponentController {
  runtime: RuntimeHandle | undefined = undefined;
  // The map once it's ready. Before then, its snapshot isn't readable.
  map: MapHandle | undefined = undefined;
  session: RenderSessionHandle | undefined = undefined;

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
  // The map from when it's created, which the view disposes.
  private created: MapHandle | undefined = undefined;
  private style: string = '';
  private bounds: BoundOptions | undefined = undefined;
  // The limits a new map has, which apply again when the app removes its own.
  private defaultBounds: BoundOptions | undefined = undefined;

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
    bounds: BoundOptions | undefined): void {
    this.controller = controller;
    this.style = style;
    this.bounds = bounds;
    const runtimeReady = runtime === undefined ? getDefaultRuntime() : Promise.resolve(runtime);
    runtimeReady.then((runtime: RuntimeHandle) => this.createMap(runtime)).catch((error: Error) => this.fail(error));
  }

  setStyle(style: string): void {
    this.style = style;
    this.applyStyle();
  }

  setBounds(bounds: BoundOptions | undefined): void {
    this.bounds = bounds;
    this.applyBounds();
  }

  dispose(): void {
    this.disposed = true;
    const runtime = this.runtime;
    const map = this.created;
    const session = this.session;
    if (runtime !== undefined) {
      removeRuntimeEventListener(runtime, this.listener);
    }
    this.controller?.detach(this);
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
    }).catch((error: Error) => console.error(`MapLibre: ${error.message}`));
  }

  private async createMap(runtime: RuntimeHandle): Promise<void> {
    const controller = this.controller;
    if (this.disposed || controller === undefined) {
      return;
    }
    const map = runtime.createMap({
      initialExtent: {
        width: this.size?.width ?? 1,
        height: this.size?.height ?? 1,
        scaleFactor: this.context.vp2px(1),
      },
      mapMode: MapMode.continuous,
      eventMask: RuntimeEventFlag.mapStyleLoaded |
        RuntimeEventFlag.mapLoadingFailed |
        RuntimeEventFlag.mapRenderError |
        RuntimeEventFlag.mapCameraDidChange |
        RuntimeEventFlag.mapSourceChanged,
    });
    this.runtime = runtime;
    this.created = map;
    await map.ready;
    if (this.disposed) {
      return;
    }
    this.map = map;
    this.defaultBounds = boundOptions(map.getSnapshot().bounds);
    addRuntimeEventListener(runtime, this.listener);
    // The controller takes camera changes from here on, and the map runs
    // commands in order, so they follow the starting camera.
    const startCamera = controller.attach(this);
    if (startCamera !== undefined) {
      map.discarding.updateCamera({ mode: CameraUpdateMode.jump, camera: startCamera });
    }
    this.applyBounds();
    this.applyStyle();
    this.retarget();
  }

  private onEvent(event: RuntimeEvent): void {
    const map = this.map;
    if (map === undefined) {
      return;
    }
    // The controller's state is this map's only while the controller shows it.
    const controller = this.controller?.map === map ? this.controller : undefined;
    if (event.type === RuntimeEventType.mapStyleLoaded) {
      if (controller !== undefined) {
        controller.styleLoaded = true;
        this.readAttributions(map, controller);
      }
      this.events.onStyleLoaded();
    } else if (event.type === RuntimeEventType.mapCameraDidChange) {
      // The camera changes at the end of each jump and animation. Report it
      // once nothing moves it any more.
      const snapshot = map.getSnapshot();
      if (!snapshot.transitionInProgress && !snapshot.gestureInProgress) {
        if (controller !== undefined) {
          controller.camera = snapshot.view.camera;
        }
        this.events.onCameraIdle(snapshot.view.camera);
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

  // A style that fails to load reports mapLoadingFailed.
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
    try {
      loadStyle(map, this.style);
    } catch (error) {
      this.fail(error as Error);
    }
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

  private fail(error: Error): void {
    console.error(`MapLibre: ${error.message}`);
    if (!this.disposed) {
      this.events.onMapError(error);
    }
  }
}

// A style that starts with `{` is a style document, and anything else is its
// URL. It throws when the document isn't JSON.
export function loadStyle(map: MapHandle, style: string): void {
  const trimmed = style.trim();
  if (trimmed.startsWith('{')) {
    map.discarding.setStyleJson(JSON.parse(trimmed));
  } else {
    map.discarding.setStyleUrl(trimmed);
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
