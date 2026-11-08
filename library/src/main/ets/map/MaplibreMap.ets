import geoLocationManager from '@ohos.geoLocationManager';

import { CameraIdleEvent } from '../camera/CameraIdleEvent';
import { CameraMoveStartEvent } from '../camera/CameraMoveStartEvent';
import { Insets } from '../camera/internal/Insets';
import { MapContent } from '../content/MapContent';
import { ResolvedStyleImage } from '../content/StyleImage';
import { InteractionOptions } from '../interaction/InteractionOptions';
import { TAP_SLOP } from '../interaction/internal/MapGestures';
import { UserLocationIndicatorOptions } from '../location/UserLocationIndicatorOptions';
import { defaultOverlay } from '../overlay/internal/DefaultOverlay';
import { callHandler, consumes } from '../runtime/internal/Log';
import { runtimeState } from '../runtime/internal/RuntimeRegistry';
import { MapRuntime } from '../runtime/MapRuntime';
import { CameraBoundsOptions } from './CameraBoundsOptions';
import { FrameRenderedEvent } from './FrameRenderedEvent';
import { controllerState } from './internal/ControllerState';
import { closeScope, MapScope, openScope } from './internal/MapScope';
import { MapView } from './internal/MapView';
import { MapClickEvent } from './MapClickEvent';
import { MapController } from './MapController';
import { MapError } from './MapError';
import { StyleImageMissingEvent } from './StyleImageMissingEvent';

// The default of onFrameRendered, with which the map doesn't report frames.
const IGNORE_FRAMES = (event: FrameRenderedEvent) => {
};

/**
 * A MapLibre map. It fills the size that its parent gives it.
 *
 * ```ets
 * private map: MapController = new MapController({
 *   camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 15 },
 * });
 *
 * build() {
 *   MaplibreMap({
 *     style: 'https://tiles.openfreemap.org/styles/liberty',
 *     controller: this.map,
 *     onError: (error: MapError) => console.error(error.message),
 *   }) {
 *     DefaultControls()
 *     Marker({ coordinate: { latitude: 48.8584, longitude: 2.2945 } }) {
 *       Text('Eiffel Tower')
 *     }
 *   }
 * }
 * ```
 *
 * A tap is a click, and a long press or right click is a long click. A click
 * goes to `onMapClick`, then to the layers of `content` from the top down, then
 * to `onUnhandledClick`, until one consumes it.
 *
 * The map calls its events on the UI thread. When a handler throws, the map
 * logs the error and continues, and a click handler that throws doesn't
 * consume the click.
 */
@ComponentV2
export struct MaplibreMap {
  /**
   * The style to show: a URL, or a style document. A new value loads the new
   * style; a document with the same JSON as the previous one doesn't reload. A
   * style that fails to load is reported to `onError` as a `StyleLoadError`.
   */
  @Require @Param style: string | Record<string, Object>;
  /** Reads and moves the camera. A new controller by default. */
  @Param @Once controller: MapController = new MapController();
  /**
   * The runtime whose cache and request handling the map uses.
   * `MapRuntime.getDefault()` by default.
   */
  @Param @Once runtime: MapRuntime = MapRuntime.getDefault();
  /**
   * Sources and layers to draw over the style, in every style the map loads.
   * Pass a new value to change them. One that the map rejects is reported to
   * `onError` as a `ContentError`. None by default.
   */
  @Param content: MapContent = {};
  /**
   * Limits on where the camera can go. Invalid limits are reported to
   * `onError`, and the map keeps its previous limits. No limits by default.
   */
  @Param cameraBounds: CameraBoundsOptions = {};
  /**
   * The edges of the map that the app's UI covers, such as a bottom sheet.
   * Camera moves center in the area they leave, and the control presets stay
   * clear of them. They don't appear in the camera that `controller` reports.
   * None by default.
   *
   * Each side is at least 0, not a percentage. An invalid side is reported to
   * `onError` and taken as 0.
   */
  @Param viewportInsets: Padding | LocalizedPadding = {};
  /**
   * Which camera movements the user can make, and how input makes them. Every
   * movement is on by default.
   */
  @Param interactions: InteractionOptions = {};
  /**
   * The user's location, which the map shows as a dot inside a circle of its
   * accuracy, with an arrow for its heading or course. None by default.
   */
  @Param userLocation: geoLocationManager.Location | undefined = undefined;
  /**
   * The direction that the device faces, in degrees clockwise from north. While
   * it's set, the location's arrow points this way. None by default.
   */
  @Param userHeading: number | undefined = undefined;
  /**
   * How the map draws `userLocation`. By default, a blue dot with an arrow and
   * a shadow, above every layer.
   */
  @Param userLocationIndicator: UserLocationIndicatorOptions = {};
  /**
   * Called when the style has loaded and the map has added `content` to it.
   * Changes made through `controller.style` last until the next style.
   */
  @Event onStyleLoaded: () => void = () => {
  };
  /**
   * Called when the style uses an image that it doesn't have. Resolve the image
   * for `event.id` to add it to the style, or undefined to leave it out. The
   * map asks for each ID at most once per style, and copies a pixel map's
   * pixels when the promise resolves. An image that the map can't draw is
   * reported to `onError`. Resolves undefined by default.
   */
  @Event onStyleImageMissing: (event: StyleImageMissingEvent) => Promise<ResolvedStyleImage | undefined> =
    (event: StyleImageMissingEvent) => Promise.resolve(undefined);
  /**
   * Called each time the map has drawn everything in view and has nothing left
   * to load, animate, or draw.
   */
  @Event onMapIdle: () => void = () => {
  };
  /**
   * Called after each frame that the map draws, with measurements of it. A map
   * without a handler doesn't measure its frames.
   */
  @Event onFrameRendered: (event: FrameRenderedEvent) => void = IGNORE_FRAMES;
  /**
   * Called when the camera starts to move. A jump starts and ends at once.
   */
  @Event onCameraMoveStart: (event: CameraMoveStartEvent) => void = (event: CameraMoveStartEvent) => {
  };
  /**
   * Called when the camera comes to rest, once for each `onCameraMoveStart`.
   */
  @Event onCameraIdle: (event: CameraIdleEvent) => void = (event: CameraIdleEvent) => {
  };
  /**
   * Called when something fails with no call to reject, such as a style that
   * fails to load, rejected `content`, or an invalid parameter. The map also
   * logs each error.
   */
  @Event onError: (error: MapError) => void = (error: MapError) => {
  };
  /**
   * Called when the user starts a gesture that moves the camera.
   */
  @Event onGestureStart: () => void = () => {
  };
  /**
   * Called when the user's gesture stops moving the camera, after its momentum
   * and snap, once for each `onGestureStart`.
   */
  @Event onGestureEnd: () => void = () => {
  };
  /**
   * Called when the user clicks the map, before the layers of `content` get the
   * click. Return `true` to consume the click, or `false` to pass it on.
   */
  @Event onMapClick: (event: MapClickEvent) => boolean = (event: MapClickEvent) => false;
  /**
   * Called when the user long presses or right clicks the map, before the
   * layers of `content` get the long click. Return `true` to consume it, or
   * `false` to pass it on.
   */
  @Event onMapLongClick: (event: MapClickEvent) => boolean = (event: MapClickEvent) => false;
  /**
   * Called for a click that neither `onMapClick` nor a layer consumed. Long
   * clicks don't come here.
   */
  @Event onUnhandledClick: (event: MapClickEvent) => void = (event: MapClickEvent) => {
  };
  /**
   * ArkUI content above the map, laid out in a `Stack` of the map's size.
   * `DefaultControls` by default; an empty closure shows nothing.
   */
  @BuilderParam overlays: () => void = defaultOverlay;

  // What the controls and markers in the overlay find the map by.
  private scope: MapScope = openScope();

  // The app's handlers, which never throw into the view.
  private view: MapView = new MapView(this.getUIContext(), {
    onStyleLoaded: () => callHandler('onStyleLoaded', () => this.onStyleLoaded()),
    onStyleImageMissing: (event: StyleImageMissingEvent): Promise<ResolvedStyleImage | undefined> =>
      this.onStyleImageMissing(event),
    onMapIdle: () => callHandler('onMapIdle', () => this.onMapIdle()),
    onFrameRendered: (event: FrameRenderedEvent) => callHandler('onFrameRendered', () => this.onFrameRendered(event)),
    onCameraMoveStart: (event: CameraMoveStartEvent) =>
      callHandler('onCameraMoveStart', () => this.onCameraMoveStart(event)),
    onCameraIdle: (event: CameraIdleEvent) => callHandler('onCameraIdle', () => this.onCameraIdle(event)),
    onError: (error: MapError) => callHandler('onError', () => this.onError(error)),
    onViewportInsets: (insets: Insets) => {
      this.scope.insets = insets;
    },
    onGestureStart: () => {
      this.scope.gesturing = true;
      callHandler('onGestureStart', () => this.onGestureStart());
    },
    onGestureEnd: () => {
      this.scope.gesturing = false;
      callHandler('onGestureEnd', () => this.onGestureEnd());
    },
    onMapClick: (event: MapClickEvent): boolean => consumes('onMapClick', () => this.onMapClick(event)),
    onMapLongClick: (event: MapClickEvent): boolean => consumes('onMapLongClick', () => this.onMapLongClick(event)),
    onUnhandledClick: (event: MapClickEvent) => callHandler('onUnhandledClick', () => this.onUnhandledClick(event)),
  });

  aboutToAppear(): void {
    this.scope.controller = this.controller;
    this.view.gestures.options = this.interactions;
    this.view.setUserLocationIndicator(this.userLocationIndicator);
    this.view.setUserLocation(this.userLocation);
    this.view.setUserHeading(this.userHeading);
    this.view.setViewportInsets(this.viewportInsets);
    this.view.frameEvents = this.onFrameRendered !== IGNORE_FRAMES;
    this.view.start(controllerState(this.controller), runtimeState(this.runtime), this.style, this.content, this.cameraBounds);
  }

  aboutToDisappear(): void {
    closeScope(this.scope);
    this.view.dispose();
  }

  @Monitor('style')
  styleChanged(): void {
    this.view.setStyle(this.style);
  }

  @Monitor('content')
  contentChanged(): void {
    this.view.setContent(this.content);
  }

  @Monitor('cameraBounds')
  cameraBoundsChanged(): void {
    this.view.setBounds(this.cameraBounds);
  }

  @Monitor('interactions')
  interactionsChanged(): void {
    this.view.gestures.options = this.interactions;
  }

  @Monitor('viewportInsets')
  viewportInsetsChanged(): void {
    this.view.setViewportInsets(this.viewportInsets);
  }

  @Monitor('userLocation')
  userLocationChanged(): void {
    this.view.setUserLocation(this.userLocation);
  }

  @Monitor('userLocationIndicator')
  userLocationIndicatorChanged(): void {
    this.view.setUserLocationIndicator(this.userLocationIndicator);
  }

  @Monitor('userHeading')
  userHeadingChanged(): void {
    this.view.setUserHeading(this.userHeading);
  }

  // ArkUI's gestures decide whether the map owns a touch, against a scrolling
  // parent and content above the map, and MapGestures moves the camera from the
  // raw touches once one of them starts. The pan needs two fingers when one
  // finger shouldn't move the map, so a parent scrolls instead. Taps zoom, and
  // MapGestures decides which taps click. The mouse's right button, the wheel,
  // the touchpad, and keys come through their own events.
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      XComponent({ type: XComponentType.SURFACE, controller: this.view })
        .width('100%')
        .height('100%')
        .focusable(true)
        .focusOnTouch(true)
        .onTouch((event: TouchEvent) => this.view.gestures.onTouch(event))
        .onAxisEvent((event: AxisEvent) => this.view.gestures.onAxis(event))
        .onMouse((event: MouseEvent) => this.view.gestures.onMouse(event))
        .onKeyEvent((event: KeyEvent): boolean => this.view.gestures.onKey(event))
        .onBlur(() => this.view.gestures.blur())
        .gesture(GestureGroup(GestureMode.Parallel,
          PanGesture({ fingers: this.panFingers() })
            .onActionStart((event: GestureEvent) => {
              this.view.gestures.claim();
              this.view.gestures.onPan(event);
            })
            .onActionUpdate((event: GestureEvent) => this.view.gestures.onPan(event))
            .onActionEnd(() => this.view.gestures.onPanEnd())
            .onActionCancel(() => this.view.gestures.onPanEnd()),
          PinchGesture()
            .onActionStart(() => this.view.gestures.claim())
            .onActionUpdate((event: GestureEvent) => this.view.gestures.onPinch(event))
            .onActionEnd((event: GestureEvent) => this.view.gestures.onPinchEnd(event))
            .onActionCancel(() => this.view.gestures.pinchCancelled()),
          RotationGesture()
            .onActionStart(() => this.view.gestures.claim()),
          LongPressGesture()
            .onAction(() => this.view.gestures.longPress()),
          TapGesture({ count: 2, distanceThreshold: TAP_SLOP })
            .onAction((event: GestureEvent) => {
              const finger = event.fingerList[0];
              this.view.gestures.doubleTap(finger.localX, finger.localY);
            }),
          TapGesture({ fingers: 2, distanceThreshold: TAP_SLOP })
            .onAction((event: GestureEvent) => {
              const fingers = event.fingerList;
              const x = fingers.reduce((sum: number, finger: FingerInfo) => sum + finger.localX, 0);
              const y = fingers.reduce((sum: number, finger: FingerInfo) => sum + finger.localY, 0);
              this.view.gestures.twoFingerTap(x / fingers.length, y / fingers.length);
            })))
      this.overlays()
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .id(this.scope.key)
  }

  private panFingers(): number {
    return this.interactions.pan?.enabled !== false && this.interactions.cooperative !== true ? 1 : 2;
  }
}
