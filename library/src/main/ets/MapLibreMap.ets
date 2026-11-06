import { BoundOptions, Camera as CameraPosition, EdgeInsets, RuntimeHandle } from '@maplibre/native-ffi';
import geoLocationManager from '@ohos.geoLocationManager';

import { MapInteractionOptions, TAP_SLOP } from './gestures';
import { MapClickEvent, MapContent } from './Content';
import { MapController } from './MapController';
import { noContent } from './MapMarker';
import { MapView } from './MapView';
import { MapAttribution, MapCompass, MapScaleBar, MapZoomButtons } from './Ornaments';
import { NO_INSETS } from './padding';

// Where the ornaments go in the map. ets-loader rejects `layoutGravity`, so
// they align in a RelativeContainer.
const CONTAINER = '__container__';
const TOP_START: LocalizedAlignRuleOptions = {
  top: { anchor: CONTAINER, align: VerticalAlign.Top },
  start: { anchor: CONTAINER, align: HorizontalAlign.Start },
};
const TOP_END: LocalizedAlignRuleOptions = {
  top: { anchor: CONTAINER, align: VerticalAlign.Top },
  end: { anchor: CONTAINER, align: HorizontalAlign.End },
};
const CENTER_END: LocalizedAlignRuleOptions = {
  center: { anchor: CONTAINER, align: VerticalAlign.Center },
  end: { anchor: CONTAINER, align: HorizontalAlign.End },
};
const BOTTOM_END: LocalizedAlignRuleOptions = {
  bottom: { anchor: CONTAINER, align: VerticalAlign.Bottom },
  end: { anchor: CONTAINER, align: HorizontalAlign.End },
};

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
 * consumes it. While `gestures.zoom` is on, a tap clicks once 300 ms pass
 * without a second tap, so a double tap zooms without clicking.
 *
 * ```ets
 * private map: MapController = new MapController({
 *   camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 15 },
 * });
 *
 * build() {
 *   MapLibreMap({
 *     controller: this.map,
 *     style: 'https://tiles.openfreemap.org/styles/liberty',
 *     onMapError: (error: Error) => console.error(error.message),
 *   }) {
 *     MapMarker({ controller: this.map, coordinate: { latitude: 48.8584, longitude: 2.2945 } }) {
 *       Text('Eiffel Tower')
 *     }
 *   }
 * }
 * ```
 *
 * Its `overlays`, the ArkUI content in the trailing closure, lie over the map
 * in a `Stack` of the map's size, under the map's ornaments. Pin them to
 * coordinates with `MapMarker`. What the map itself draws, such as GeoJSON in
 * layers, is its `content`.
 */
@ComponentV2
export struct MapLibreMap {
  /** Reads and moves the camera. Without one, the map keeps its own. */
  @Param @Once controller: MapController = new MapController();
  /** The style's URL, or a style document as JSON. */
  @Require @Param style: string;
  /**
   * Sources, layers, and images to draw over the style, in each style the map
   * loads. Give the map a new value to change them, such as from a `@Computed`
   * getter; it changes only what differs. A source or layer that the map
   * rejects is reported to `onMapError` and left out until it changes.
   */
  @Param content: MapContent | undefined = undefined;
  /**
   * Limits on the camera: an area that its center stays within, and zoom and
   * pitch ranges. Limits it leaves out keep the map's defaults.
   */
  @Param cameraBounds: BoundOptions | undefined = undefined;
  /**
   * The FFI runtime that creates the map. Without one, maps share the
   * library's default runtime. The map sets the runtime's event handler, so
   * listen with `addRuntimeEventListener()` instead of setting one.
   */
  @Param @Once runtime: RuntimeHandle | undefined = undefined;
  /**
   * How the user moves the map: which camera movements input makes, and what
   * the app does as each starts. Every movement is on by default.
   */
  @Param interactions: MapInteractionOptions = {};
  /**
   * Whether the map shows a `MapCompass` at its top end, which shows while the
   * map is rotated or tilted.
   */
  @Param compassEnabled: boolean = true;
  /** Whether the map shows a `MapScaleBar` at its top start. */
  @Param scaleBarEnabled: boolean = false;
  /** Whether the map shows `MapZoomButtons` in the middle of its end edge. */
  @Param zoomButtonsEnabled: boolean = false;
  /**
   * Whether the map shows a `MapAttribution` at its bottom end. Most sources'
   * terms require their attribution, so show it elsewhere without one.
   */
  @Param attributionEnabled: boolean = true;
  /**
   * The edges of the map, in vp, that the app's own UI covers, such as a
   * bottom sheet. The map's ornaments stay clear of them, and they add to the
   * camera's padding, so a camera move centers its target in the part of the
   * map that the user sees. They never show in the camera that `controller`
   * reports. When they change, the camera's center moves to the middle of
   * what they leave.
   *
   * ```ets
   * MapLibreMap({
   *   controller: this.map,
   *   style: STYLE,
   *   viewportInsets: { top: 0, left: 0, bottom: this.sheetHeight, right: 0 },
   * })
   * ```
   */
  @Param viewportInsets: EdgeInsets = NO_INSETS;
  /**
   * ArkUI content over the map, in a `Stack` of its size, from the trailing
   * closure. `content` is what the map draws itself.
   */
  @BuilderParam overlays: () => void = noContent;
  /**
   * The user's location, which the map shows as a dot in a circle of its
   * `accuracy`, with an arrow for `userHeading`, or for the course while it
   * moves. Pass each location that Location Kit reports; the app requests the
   * permission and the updates. The dot eases to each new location.
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
   * The style has loaded, so its layers and sources exist, and the map has
   * added `content` to it. Each style starts from its own document, without
   * what the app added through `controller.map`.
   */
  @Event onStyleLoaded: () => void = () => {
  };
  /** The camera has come to rest, after a jump or once an animation ends. */
  @Event onCameraIdle: (camera: CameraPosition) => void = (camera: CameraPosition) => {
  };
  /** The style failed to load, the map failed to render, or it rejected part of `content`. */
  @Event onMapError: (error: Error) => void = (error: Error) => {
  };
  /**
   * The user started to move the camera, such as to stop following a
   * location.
   */
  @Event onGestureStart: () => void = () => {
  };
  /**
   * The user's input stopped moving the camera, after any momentum. A rotation
   * that ends near north may still ease to it.
   */
  @Event onGestureEnd: () => void = () => {
  };
  /**
   * The user clicked the map, before the layers of `content` get the click.
   * Return `true` to consume it, so they don't, or `false` to pass it on.
   */
  @Event onMapClick: (event: MapClickEvent) => boolean = (event: MapClickEvent) => false;
  /**
   * The user long pressed or right clicked the map, before the layers of
   * `content` get the long click. Return `true` to consume it.
   */
  @Event onMapLongClick: (event: MapClickEvent) => boolean = (event: MapClickEvent) => false;
  /**
   * Neither `onMapClick` nor a layer consumed a click, such as one beside the
   * app's features, which may clear a selection.
   */
  @Event onUnhandledClick: (event: MapClickEvent) => void = (event: MapClickEvent) => {
  };

  private view: MapView = new MapView(this.getUIContext(), {
    onStyleLoaded: () => this.onStyleLoaded(),
    onCameraIdle: (camera: CameraPosition) => this.onCameraIdle(camera),
    onMapError: (error: Error) => this.onMapError(error),
    onGestureStart: () => this.onGestureStart(),
    onGestureEnd: () => this.onGestureEnd(),
    onMapClick: (event: MapClickEvent): boolean => this.onMapClick(event),
    onMapLongClick: (event: MapClickEvent): boolean => this.onMapLongClick(event),
    onUnhandledClick: (event: MapClickEvent) => this.onUnhandledClick(event),
  });

  aboutToAppear(): void {
    this.view.gestures.options = this.interactions;
    this.view.setUserLocation(this.userLocation);
    this.view.setUserHeading(this.userHeading);
    this.view.setViewportInsets(this.viewportInsets);
    this.view.start(this.controller, this.runtime, this.style, this.content, this.cameraBounds);
  }

  aboutToDisappear(): void {
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
      RelativeContainer() {
        if (this.scaleBarEnabled) {
          MapScaleBar({ controller: this.controller })
            .margin(8)
            .alignRules(TOP_START)
        }
        if (this.compassEnabled) {
          MapCompass({ controller: this.controller })
            .margin(8)
            .alignRules(TOP_END)
        }
        if (this.zoomButtonsEnabled) {
          MapZoomButtons({ controller: this.controller })
            .margin(8)
            .alignRules(CENTER_END)
        }
        if (this.attributionEnabled) {
          MapAttribution({ controller: this.controller })
            .margin(8)
            .alignRules(BOTTOM_END)
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.viewportInsets.top,
        left: this.viewportInsets.left,
        bottom: this.viewportInsets.bottom,
        right: this.viewportInsets.right,
      })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  private panFingers(): number {
    return this.interactions.pan?.enabled !== false && this.interactions.cooperative !== true ? 1 : 2;
  }
}
