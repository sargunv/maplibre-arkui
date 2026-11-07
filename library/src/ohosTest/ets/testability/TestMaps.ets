// The map that the test page shows, which the cases read and change, and the
// waits that poll it once a frame.

import {
  CameraBoundsOptions,
  CameraPosition,
  LatLng,
  MapClickEvent,
  MapContent,
  MapController,
  MapError,
  InteractionOptions,
  RuntimeHandle,
  UserLocationIndicatorOptions,
  ScaleBarUnits,
} from '@maplibre/arkui';
import { FrameCallback } from '@ohos.arkui.UIContext';
import geoLocationManager from '@ohos.geoLocationManager';
import window from '@ohos.window';

// How long a wait polls before it fails.
export const WAIT_MS = 15000;

// A style document from its JSON text, as a map takes it.
export function styleDocument(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

// A style without network requests, a background of `color`, as JSON text,
// which a resource provider serves.
export function backgroundStyleJson(color: string): string {
  return '{"version":8,"sources":{},"layers":[{"id":"background","type":"background",' +
    `"paint":{"background-color":"${color}"}}]}`;
}

// That style as a map takes it.
export function backgroundStyle(color: string): Record<string, Object> {
  return styleDocument(backgroundStyleJson(color));
}

export const STYLE_JSON = backgroundStyleJson('#4a90d9');
export const STYLE = styleDocument(STYLE_JSON);

// Whether a map shows the controller.
export function showsMap(controller: MapController): boolean {
  return controller.withFfiMap(() => true) ?? false;
}

export const NO_INSETS: Padding = { top: 0, left: 0, bottom: 0, right: 0 };

function noop(): void {
}

// What the test map draws over itself: see TestMap.overlay.
export type TestOverlay = 'none' | 'omitted' | 'default' | 'full' | 'attributionOnly';

@ObservedV2
export class TestMap {
  // The map is on the page while this is true. The suites that need no map
  // leave it off.
  @Trace shown: boolean = false;
  @Trace style: string | Record<string, Object> = STYLE;
  @Trace cameraBounds: CameraBoundsOptions = {};
  // Which overlay the map draws: none of its own but what the flags below
  // add, a preset in its block besides them, or, with 'omitted', no trailing
  // closure at all. Content that moves with the camera makes the emulator's
  // llvmpipe crash more often, so only the cases that need it turn it on.
  @Trace overlay: TestOverlay = 'none';
  // A ScaleBar in these units, with this maxWidth when a case sets it.
  @Trace scaleBar: ScaleBarUnits | undefined = undefined;
  @Trace scaleBarMaxWidth: number | undefined = undefined;
  // A DisappearingScaleBar, and how long it stays.
  @Trace disappearingScaleBarMs: number | undefined = undefined;
  // A DisappearingCompassButton at the overlay's top end, and how long it
  // stays when a case sets it.
  @Trace compass: boolean = false;
  @Trace compassMs: number | undefined = undefined;
  // A CompassButton at the overlay's top start.
  @Trace alwaysShownCompass: boolean = false;
  @Trace zoomButtons: boolean = false;
  @Trace attribution: boolean = false;
  // The attributions of an AttributionText in the overlay, if any.
  @Trace attributionText: string[] | undefined = undefined;
  @Trace viewportInsets: Padding | LocalizedPadding = NO_INSETS;
  @Trace interactions: InteractionOptions = {};
  // A box placed at this coordinate, by this alignment when a case sets it.
  @Trace placedAt: LatLng | undefined = undefined;
  @Trace placedAtAlignment: Alignment | undefined = undefined;
  // A box placed towards this coordinate, and the angles it reported.
  @Trace placedTowards: LatLng | undefined = undefined;
  placedTowardsAngles: number[] = [];
  // A PointerPinButton towards this coordinate, and how often it was tapped.
  @Trace pointerPin: LatLng | undefined = undefined;
  pointerPinTaps: number = 0;
  // A Marker at this coordinate whose content has an onClick, and how often
  // it was clicked.
  @Trace clickableMarker: LatLng | undefined = undefined;
  markerClicks: number = 0;
  // The padding of the Stack that holds the placements.
  @Trace placementPadding: number = 0;
  @Trace userLocation: geoLocationManager.Location | undefined = undefined;
  @Trace userHeading: number | undefined = undefined;
  @Trace userLocationIndicator: UserLocationIndicatorOptions = {};
  // The map is 300 vp tall at the top of a Scroll while this is true, and fills
  // the page otherwise.
  @Trace inScroll: boolean = false;
  // The map's height, while it isn't in the Scroll.
  @Trace height: Length = '100%';
  // A second map under the first, with the same controller, and whether the
  // first shows.
  @Trace secondMap: boolean = false;
  @Trace firstMap: boolean = true;
  @Trace content: MapContent = {};
  // The runtime that the map takes as it appears, or the default one.
  @Trace runtime: RuntimeHandle | undefined = undefined;
  // What the map's events reported.
  styleLoads: number = 0;
  errors: string[] = [];
  failures: MapError[] = [];
  cameraIdles: CameraPosition[] = [];
  // Whether onError and onCameraIdle throw after they record what they got.
  throwOnError: boolean = false;
  throwOnCameraIdle: boolean = false;
  gestureStarts: number = 0;
  gestureEnds: number = 0;
  // What a case does as a gesture starts or ends, as an app would.
  onGestureStart: () => void = noop;
  onGestureEnd: () => void = noop;
  // What got each click, in order, as 'click', 'long click', and 'unhandled'
  // for the map's events, and what the cases' layer handlers add, with the
  // events. The map's handlers consume the clicks while `consumeClicks` is on.
  clicks: string[] = [];
  clickEvents: MapClickEvent[] = [];
  consumeClicks: boolean = false;
  controller: MapController = new MapController({ camera: { zoom: 1 } });
  // Counts the styles that reset() loads, to name each.
  private resets: number = 0;
  scroller: Scroller = new Scroller();
  // The page's UI context, once the page appears, and the test ability's
  // window stage, which sets the page's density.
  context: UIContext | undefined = undefined;
  windowStage: window.WindowStage | undefined = undefined;

  /**
   * Shows the map with `style`, alone on the page or in the Scroll, with every
   * flag off. The style loads afresh, without what a case added to it, and the
   * camera rests at the origin at zoom 1, facing north.
   */
  async reset(style: Record<string, Object> = STYLE, inScroll: boolean = false): Promise<void> {
    const controller = this.controller;
    controller.stopFollowingUserLocation();
    // A map that took another runtime, or that another map shared the page
    // with, starts again.
    if (this.runtime !== undefined || this.secondMap || !this.firstMap || this.height !== '100%' ||
      this.overlay === 'omitted') {
      this.shown = false;
      await until('the map leaves', () => !showsMap(controller));
      this.runtime = undefined;
      this.secondMap = false;
      this.firstMap = true;
      this.height = '100%';
    }
    this.onGestureStart = noop;
    this.onGestureEnd = noop;
    this.consumeClicks = false;
    this.throwOnError = false;
    this.throwOnCameraIdle = false;
    this.cameraBounds = {};
    this.overlay = 'none';
    this.scaleBar = undefined;
    this.scaleBarMaxWidth = undefined;
    this.disappearingScaleBarMs = undefined;
    this.compass = false;
    this.compassMs = undefined;
    this.alwaysShownCompass = false;
    this.zoomButtons = false;
    this.attribution = false;
    this.attributionText = undefined;
    this.viewportInsets = NO_INSETS;
    this.interactions = {};
    this.placedAt = undefined;
    this.placedAtAlignment = undefined;
    this.placedTowards = undefined;
    this.placedTowardsAngles = [];
    this.pointerPin = undefined;
    this.pointerPinTaps = 0;
    this.clickableMarker = undefined;
    this.markerClicks = 0;
    this.placementPadding = 0;
    this.userLocation = undefined;
    this.userHeading = undefined;
    this.userLocationIndicator = {};
    this.content = {};
    const loads = this.styleLoads;
    this.shown = true;
    this.inScroll = inScroll;
    // The map loads a style whose JSON differs from the one it shows: the
    // same style with another name.
    const named = JSON.parse(JSON.stringify(style)) as Record<string, Object>;
    named['name'] = `reset ${++this.resets}`;
    this.style = named;
    await until('the map loads the style', () => this.styleLoads > loads && controller.styleLoaded);
    this.errors = [];
    this.failures = [];
    this.cameraIdles = [];
    this.clicks = [];
    this.clickEvents = [];
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    await controller.updateCamera({
      center: { latitude: 0, longitude: 0 },
      zoom: 1,
      bearing: 0,
      pitch: 0,
      padding: { top: 0, left: 0, bottom: 0, right: 0 },
    });
  }

  /** Records a click that `what` got, and returns whether it consumes it. */
  click(what: string, event: MapClickEvent, consume: boolean): boolean {
    this.clicks.push(what);
    this.clickEvents.push(event);
    return consume;
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
