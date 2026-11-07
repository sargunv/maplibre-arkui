import { RuntimeHandle } from '@maplibre/native-ffi';
import geoLocationManager from '@ohos.geoLocationManager';

import { CameraBoundsOptions } from './CameraBounds';
import { CameraIdleEvent } from './CameraIdleEvent';
import { MapContent } from './Content';
import { InteractionOptions, TAP_SLOP } from './gestures';
import { callHandler, consumes } from './log';
import { MapClickEvent } from './MapClickEvent';
import { controllerState, MapController } from './MapController';
import { MapError } from './MapError';
import { UserLocationIndicatorOptions } from './location';
import { MapView } from './MapView';
import { defaultOverlay } from './Overlay';
import { Insets } from './Insets';
import { closeScope, MapScope, openScope } from './scope';

/**
 * A MapLibre map, which fills the size that its parent gives it.
 *
 * Touch, the mouse, a touchpad, and keys move the camera; `interactions`
 * chooses how. The map takes the drags that start on it from a scrolling
 * parent, unless `interactions.cooperative` leaves one-finger drags to the
 * parent. Content above the map that handles its own gestures keeps them.
 *
 * A tap is a click, and a long press or a right click is a long click.
 * `onMapClick` gets a click first, then the layers of `content` that handle
 * it, from the top layer down, then `onUnhandledClick`, until one of them
 * consumes it. While `interactions.zoom` is on, a tap clicks once 300 ms pass
 * without a second tap, so a double tap zooms without clicking.
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
 *     MapDefaultOverlay()
 *     MapPlacedAt({ coordinate: { latitude: 48.8584, longitude: 2.2945 } }) {
 *       Text('Eiffel Tower')
 *     }
 *   }
 * }
 * ```
 *
 * Its `overlays`, the ArkUI content in the trailing closure, lie over the map
 * in a `Stack` of the map's size. Without a trailing closure, the map draws
 * `MapDefaultOverlay`; an empty one draws nothing. The library's controls and
 * placements, such as `MapCompassButton` and `MapPlacedAt`, find the map
 * anywhere in the overlay. What the map itself draws, such as GeoJSON in
 * layers, is its `content`.
 *
 * The map calls each of its events on the UI thread. When a handler throws,
 * the map logs the exception and goes on: the other handlers still run, and a
 * click handler that throws doesn't consume the click.
 */
@ComponentV2
export struct MaplibreMap {
  /**
   * The style: a URL, or a style document as style-spec JSON. A string is
   * always a URL. A new value loads the new style; a document that has the
   * same JSON as the last one doesn't, so one that `build()` writes anew loads
   * once. A style that fails to load is reported to `onError` as a
   * `StyleLoadError`.
   */
  @Require @Param style: string | Record<string, Object>;
  /** Reads and moves the camera. Without one, the map keeps its own. */
  @Param @Once controller: MapController = new MapController();
  /**
   * The FFI runtime that creates the map. Without one, maps share the
   * library's default runtime. The map sets the runtime's event handler, so
   * listen with `addRuntimeEventListener()` instead of setting one.
   */
  @Param @Once runtime: RuntimeHandle | undefined = undefined;
  /**
   * Sources, layers, and images to draw over the style, in each style the map
   * loads. Give the map a new value to change them, such as from a `@Computed`
   * getter; it changes only what differs. A source, layer, or image that the
   * map rejects is reported to `onError` as a `ContentError` and left out
   * until it changes. None by default.
   */
  @Param content: MapContent = {};
  /**
   * Limits on the camera: an area that its center stays within, and zoom and
   * pitch ranges. Each limit left out takes its default. Invalid limits, such
   * as a minimum above its maximum or a value that isn't finite, are reported
   * to `onError`, and the map keeps its last limits. No limits by default.
   */
  @Param cameraBounds: CameraBoundsOptions = {};
  /**
   * The edges of the map that the app's own UI covers, such as a bottom
   * sheet. The overlay presets keep their controls clear of them, and they add
   * to the camera's padding, so a camera move centers its target in the part
   * of the map that the user sees. They never show in the camera that
   * `controller` reports. When they change, the camera's center moves to the
   * middle of what they leave. None by default.
   *
   * Each side is a length of at least 0, not a percentage; a side left out is
   * 0. An invalid side is reported to `onError` and taken as 0. A
   * `LocalizedPadding`'s `start` and `end` follow the app's language, not an
   * ancestor's `.direction()`.
   *
   * ```ets
   * MaplibreMap({
   *   style: STYLE,
   *   controller: this.map,
   *   viewportInsets: { bottom: this.sheetHeight },
   * })
   * ```
   */
  @Param viewportInsets: Padding | LocalizedPadding = {};
  /**
   * How the user moves the map: which camera movements input makes, and what
   * the app does as each starts. Every movement is on by default.
   */
  @Param interactions: InteractionOptions = {};
  /**
   * The user's location, which the map shows as a dot in a circle of its
   * `accuracy`, with an arrow for `userHeading`, or for the course while it
   * moves, as `userLocationIndicator` styles them. Pass each location that
   * Location Kit reports; the app requests the permission and the updates.
   * The dot eases to each new location.
   * `controller.followUserLocation()` moves the camera with it.
   */
  @Param userLocation: geoLocationManager.Location | undefined = undefined;
  /**
   * The direction that the device faces, in degrees clockwise from north,
   * which the arrow on `userLocation` points to while it's set, in place of
   * the course. Pass each heading that the compass reports, as for
   * `userLocation`.
   */
  @Param userHeading: number | undefined = undefined;
  /**
   * How the map draws `userLocation`: its colors, images of the style's own,
   * and the layer that it goes under. The default is a blue dot with an arrow
   * and a shadow, above every layer.
   */
  @Param userLocationIndicator: UserLocationIndicatorOptions = {};
  /**
   * The style has loaded, so its layers and sources exist, and the map has
   * added `content` to it. Each style starts from its own document, without
   * what the app added through `controller.withFfiMap()`. Called on the UI
   * thread; the map logs what it throws.
   */
  @Event onStyleLoaded: () => void = () => {
  };
  /**
   * The camera has come to rest, after a jump or once an animation or a
   * gesture ends. Called on the UI thread; the map logs what it throws.
   */
  @Event onCameraIdle: (event: CameraIdleEvent) => void = (event: CameraIdleEvent) => {
  };
  /**
   * Something failed while the map runs, such as a style that fails to load,
   * a frame that fails to render, part of `content` that the map rejects, or
   * an invalid `viewportInsets`, `cameraBounds`, or bearing of `interactions`.
   * See `MapError` for its kinds. The map also logs each. Called on the UI
   * thread; the map logs what it throws.
   */
  @Event onError: (error: MapError) => void = (error: MapError) => {
  };
  /**
   * The user started a gesture, which moves the camera. The `onStart` of
   * `interactions` tells which way, such as a pan that stops following the
   * user's location. `InteractionOptions` describes what a gesture is and the
   * order of the gesture events. Called on the UI thread; the map logs what
   * it throws, and the gesture goes on.
   */
  @Event onGestureStart: () => void = () => {
  };
  /**
   * The user's gesture stopped moving the camera, after its momentum and its
   * snap to a bearing of `interactions.rotate.snapBearings`, so the camera
   * comes to rest unless something else moves it. `InteractionOptions`
   * describes the order of the gesture events. Called on the UI thread; the
   * map logs what it throws.
   */
  @Event onGestureEnd: () => void = () => {
  };
  /**
   * The user clicked the map, before the layers of `content` get the click.
   * Return `true` to consume it, so they don't, or `false` to pass it on.
   * Called on the UI thread; the map logs what it throws, and passes the
   * click on.
   */
  @Event onMapClick: (event: MapClickEvent) => boolean = (event: MapClickEvent) => false;
  /**
   * The user long pressed or right clicked the map, before the layers of
   * `content` get the long click. Return `true` to consume it. Called on the
   * UI thread; the map logs what it throws, and passes the long click on.
   */
  @Event onMapLongClick: (event: MapClickEvent) => boolean = (event: MapClickEvent) => false;
  /**
   * Neither `onMapClick` nor a layer consumed a click, such as one beside the
   * app's features, which may clear a selection. It gets only clicks: a long
   * click that nothing consumes ends there. Called on the UI thread; the map
   * logs what it throws.
   */
  @Event onUnhandledClick: (event: MapClickEvent) => void = (event: MapClickEvent) => {
  };
  /**
   * ArkUI content over the map, in a `Stack` of its size, from the trailing
   * closure: by default, `MapDefaultOverlay`. `content` is what the map draws
   * itself.
   */
  @BuilderParam overlays: () => void = defaultOverlay;

  // What the controls and placements in the overlay find the map by.
  private scope: MapScope = openScope();

  // The app's handlers, which never throw into the view.
  private view: MapView = new MapView(this.getUIContext(), {
    onStyleLoaded: () => callHandler('onStyleLoaded', () => this.onStyleLoaded()),
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
    this.view.start(controllerState(this.controller), this.runtime, this.style, this.content, this.cameraBounds);
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
    .onAreaChange((old: Area, area: Area) => {
      this.scope.origin = { x: area.globalPosition.x as number, y: area.globalPosition.y as number };
    })
  }

  private panFingers(): number {
    return this.interactions.pan?.enabled !== false && this.interactions.cooperative !== true ? 1 : 2;
  }
}
