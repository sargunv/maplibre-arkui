// The map that the test page shows, which the cases read and change, and the
// waits that poll it once a frame.

import {
  BoundOptions,
  CameraUpdateMode,
  LatLng,
  MapContent,
  MapController,
  MapGestureOptions,
  ScaleBarUnits,
} from '@maplibre/arkui';
import { FrameCallback } from '@ohos.arkui.UIContext';
import geoLocationManager from '@ohos.geoLocationManager';

// How long a wait polls before it fails.
export const WAIT_MS = 15000;

// A style without network requests: a background of `color`.
export function backgroundStyle(color: string): string {
  return '{"version":8,"sources":{},"layers":[{"id":"background","type":"background",' +
    `"paint":{"background-color":"${color}"}}]}`;
}

export const STYLE = backgroundStyle('#4a90d9');

function noop(): void {
}

@ObservedV2
export class TestMap {
  // The map is on the page while this is true. The suites that need no map
  // leave it off.
  @Trace shown: boolean = false;
  @Trace style: string = STYLE;
  @Trace cameraBounds: BoundOptions | undefined = undefined;
  // A scale bar in these units, and a marker at this coordinate. Content that
  // moves with the camera, the compass too, makes the emulator's llvmpipe
  // crash more often, so only the cases that need them turn them on.
  @Trace scaleBar: ScaleBarUnits | undefined = undefined;
  @Trace marker: LatLng | undefined = undefined;
  @Trace compass: boolean = false;
  @Trace gestures: MapGestureOptions = {};
  @Trace userLocation: geoLocationManager.Location | undefined = undefined;
  // The map is 300 vp tall at the top of a Scroll while this is true, and fills
  // the page otherwise.
  @Trace inScroll: boolean = false;
  @Trace content: MapContent | undefined = undefined;
  // What the map's events reported.
  styleLoads: number = 0;
  errors: string[] = [];
  gestureStarts: number = 0;
  gestureEnds: number = 0;
  // What a case does as a gesture starts or ends, as an app would.
  onGestureStart: () => void = noop;
  onGestureEnd: () => void = noop;
  controller: MapController = new MapController({ camera: { zoom: 1 } });
  scroller: Scroller = new Scroller();
  // The page's UI context, once the page appears.
  context: UIContext | undefined = undefined;

  /**
   * Shows the map with `style`, alone on the page or in the Scroll, with every
   * flag off. The style loads afresh, without what a case added to it, and the
   * camera rests at the origin at zoom 1, facing north.
   */
  async reset(style: string = STYLE, inScroll: boolean = false): Promise<void> {
    const controller = this.controller;
    controller.stopFollowingUserLocation();
    this.onGestureStart = noop;
    this.onGestureEnd = noop;
    this.cameraBounds = undefined;
    this.scaleBar = undefined;
    this.marker = undefined;
    this.compass = false;
    this.gestures = {};
    this.userLocation = undefined;
    this.content = undefined;
    const loads = this.styleLoads;
    this.shown = true;
    this.inScroll = inScroll;
    // The map loads a style that differs from the one it shows, and JSON
    // doesn't mind the space.
    this.style = this.style === style ? `${style} ` : style;
    await until('the map loads the style', () => this.styleLoads > loads && controller.styleLoaded);
    this.errors = [];
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    await controller.updateCamera({
      mode: CameraUpdateMode.jump,
      camera: {
        center: { latitude: 0, longitude: 0 },
        zoom: 1,
        bearing: 0,
        pitch: 0,
        padding: { top: 0, left: 0, bottom: 0, right: 0 },
      },
    });
  }
}

export const testMap: TestMap = new TestMap();

class Poll extends FrameCallback {
  private readonly check: () => void;

  constructor(check: () => void) {
    super();
    this.check = check;
  }

  onFrame(frameTimeInNano: number): void {
    this.check();
  }
}

// Resolves on the next frame. The waits below poll with it rather than with
// timers: OpenHarmony's main thread can lose a timer's wakeup while nothing
// else wakes its event loop.
export function nextFrame(): Promise<void> {
  const context = testMap.context;
  if (context === undefined) {
    return Promise.reject(new Error('The test page has not appeared'));
  }
  return new Promise<void>((resolve) => {
    context.postFrameCallback(new Poll(() => resolve()));
  });
}

// Waits for `count` frames.
export async function frames(count: number): Promise<void> {
  for (let i = 0; i < count; i++) {
    await nextFrame();
  }
}

// Waits for `condition`, checking it each frame, and fails after `timeoutMs`.
export async function until(what: string, condition: () => boolean, timeoutMs: number = WAIT_MS): Promise<void> {
  const start = Date.now();
  while (!condition()) {
    if (Date.now() - start > timeoutMs) {
      throw new Error(`Timed out waiting until ${what}`);
    }
    await nextFrame();
  }
}

// Waits for `attempt` to return a value, trying it once a frame, and fails
// after `timeoutMs`. For a condition that only an asynchronous call can check,
// such as a feature query.
export async function eventually<T>(what: string, attempt: () => Promise<T | undefined>,
  timeoutMs: number = WAIT_MS): Promise<T> {
  const start = Date.now();
  for (;;) {
    const value = await attempt();
    if (value !== undefined) {
      return value;
    }
    if (Date.now() - start > timeoutMs) {
      throw new Error(`Timed out waiting until ${what}`);
    }
    await nextFrame();
  }
}
