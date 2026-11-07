import {
  AttributionButton,
  AttributionControls,
  AttributionText,
  CameraIdleEvent,
  CameraMoveStartEvent,
  CompassButton,
  DefaultControls,
  DisappearingCompassButton,
  DisappearingScaleBar,
  FrameRenderedEvent,
  FullControls,
  MapClickEvent,
  MapError,
  MaplibreMap,
  MapRuntime,
  Marker,
  OffscreenMarker,
  OffscreenMarkerAngleEvent,
  PointerPinButton,
  ResolvedStyleImage,
  ScaleBar,
  ScaleBarUnits,
  StyleImageMissingEvent,
  ZoomButtons,
} from '@maplibre/arkui';

import { STYLE, testMap } from '../TestMaps';

@Entry
@ComponentV2
struct Index {
  aboutToAppear(): void {
    testMap.context = this.getUIContext();
  }

  // A box at the coordinate, by its center unless a case sets the alignment.
  // The builders read the test map themselves, since a builder's arguments
  // don't update it.
  @Builder
  placedAt() {
    if (testMap.placedAtAlignment === undefined) {
      Marker({ coordinate: testMap.placedAt! }) {
        this.box('placed-at')
      }
    } else {
      Marker({ coordinate: testMap.placedAt!, alignment: testMap.placedAtAlignment }) {
        this.box('placed-at')
      }
    }
  }

  @Builder
  placedTowards() {
    OffscreenMarker({
      coordinate: testMap.placedTowards!,
      onAngleChange: (event: OffscreenMarkerAngleEvent) => {
        testMap.placedTowardsAngles.push(event.angle);
      },
    }) {
      this.box('placed-towards')
    }
  }

  @Builder
  pointerPin() {
    PointerPinButton({
      coordinate: testMap.pointerPin!,
      label: 'Pin',
      onPinClick: () => {
        testMap.pointerPinTaps++;
      },
    }) {
      Column()
        .id('pin-content')
        .width(24)
        .height(24)
        .backgroundColor(Color.Red)
    }
  }

  @Builder
  clickableMarker() {
    Marker({ coordinate: testMap.clickableMarker! }) {
      Column()
        .id('clickable-marker')
        .width(20)
        .height(10)
        .backgroundColor(Color.Red)
        .onClick(() => {
          testMap.markerClicks++;
        })
    }
  }

  @Builder
  box(id: string) {
    Column()
      .id(id)
      .width(20)
      .height(10)
      .backgroundColor(Color.Red)
  }

  @Builder
  scaleBar() {
    if (testMap.scaleBarMaxWidth === undefined) {
      ScaleBar({ units: testMap.scaleBar ?? ScaleBarUnits.METRIC })
    } else {
      ScaleBar({ units: testMap.scaleBar ?? ScaleBarUnits.METRIC, maxWidth: testMap.scaleBarMaxWidth })
    }
  }

  @Builder
  disappearingScaleBar() {
    DisappearingScaleBar({ units: ScaleBarUnits.METRIC, visibilityDurationMs: testMap.disappearingScaleBarMs ?? 3000 })
  }

  @Builder
  compass() {
    if (testMap.compassMs === undefined) {
      DisappearingCompassButton()
    } else {
      DisappearingCompassButton({ visibilityDurationMs: testMap.compassMs })
    }
  }

  // The flags' controls: the compass at the top end, the zoom buttons in the
  // middle of the end edge, and the attribution at the bottom end.
  @Builder
  controls() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (testMap.compass) {
        this.compass()
      }
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .hitTestBehavior(HitTestMode.Transparent)
    Stack({ alignContent: Alignment.End }) {
      if (testMap.zoomButtons) {
        ZoomButtons()
      }
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .hitTestBehavior(HitTestMode.Transparent)
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (testMap.attribution) {
        AttributionButton()
      }
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  preset() {
    if (testMap.overlay === 'default') {
      DefaultControls()
    } else if (testMap.overlay === 'full') {
      FullControls()
    } else if (testMap.overlay === 'attributionOnly') {
      AttributionControls()
    }
  }

  @Builder
  overlays() {
    this.preset()
    this.controls()
    if (testMap.attributionText !== undefined) {
      AttributionText({ attributions: testMap.attributionText })
    }
    Column() {
      if (testMap.scaleBar !== undefined) {
        this.scaleBar()
      }
      if (testMap.disappearingScaleBarMs !== undefined) {
        this.disappearingScaleBar()
      }
      if (testMap.alwaysShownCompass) {
        CompassButton()
      }
    }
    .padding(8)
    .alignItems(HorizontalAlign.Start)
    .hitTestBehavior(HitTestMode.Transparent)
    Stack() {
      if (testMap.placedAt !== undefined) {
        this.placedAt()
      }
      if (testMap.placedTowards !== undefined) {
        this.placedTowards()
      }
      if (testMap.pointerPin !== undefined) {
        this.pointerPin()
      }
    }
    .width('100%')
    .height('100%')
    .padding(testMap.placementPadding)
    .hitTestBehavior(HitTestMode.Transparent)
    // Straight in the overlay, so its content keeps taps from the map.
    if (testMap.clickableMarker !== undefined) {
      this.clickableMarker()
    }
  }

  build() {
    Column() {
      if (testMap.shown) {
        if (testMap.inScroll) {
          Scroll(testMap.scroller) {
            Column() {
              Column() {
                this.map()
              }
              .height(300)

              Text('Below the map')
                .width('100%')
                .height(1000)
            }
          }
          .width('100%')
          .height('100%')
        } else if (testMap.firstMap) {
          Column() {
            this.map()
          }
          .width('100%')
          .height(testMap.secondMap ? '50%' : testMap.height)
        }
        if (testMap.secondMap) {
          Column() {
            this.secondMap()
          }
          .width('100%')
          .height('50%')
        }
      }
    }
    .id('map-host')
    .width('100%')
    .height('100%')
  }

  @Builder
  map() {
    if (testMap.overlay === 'omitted') {
      MaplibreMap({
        style: testMap.style,
        controller: testMap.controller,
        viewportInsets: testMap.viewportInsets,
        onStyleLoaded: () => {
          testMap.styleLoads++;
        },
      })
    } else {
      MaplibreMap({
        style: testMap.style,
        controller: testMap.controller,
        content: testMap.content,
        cameraBounds: testMap.cameraBounds,
        runtime: testMap.runtime ?? MapRuntime.getDefault(),
        interactions: testMap.interactions,
        userLocation: testMap.userLocation,
        userHeading: testMap.userHeading,
        userLocationIndicator: testMap.userLocationIndicator,
        viewportInsets: testMap.viewportInsets,
        onStyleLoaded: () => {
          testMap.styleLoads++;
          testMap.events.push('style loaded');
        },
        onStyleImageMissing: (event: StyleImageMissingEvent): Promise<ResolvedStyleImage | undefined> =>
          testMap.imageMissing(event),
        onMapIdle: () => testMap.mapIdled(),
        onFrameRendered: (event: FrameRenderedEvent) => testMap.frameRendered(event),
        onCameraMoveStart: (event: CameraMoveStartEvent) => testMap.cameraMoveStarted(event),
        onCameraIdle: (event: CameraIdleEvent) => {
          testMap.cameraIdled(event.camera);
          if (testMap.throwOnCameraIdle) {
            throw new Error('the app handler failed');
          }
        },
        onError: (error: MapError) => {
          testMap.errors.push(error.message);
          testMap.failures.push(error);
          if (testMap.throwOnError) {
            throw new Error('the app handler failed');
          }
        },
        onGestureStart: () => {
          testMap.gestureStarts++;
          testMap.events.push('gesture start');
          testMap.onGestureStart();
        },
        onGestureEnd: () => {
          testMap.gestureEnds++;
          testMap.events.push('gesture end');
          testMap.onGestureEnd();
        },
        onMapClick: (event: MapClickEvent): boolean => testMap.click('click', event, testMap.consumeClicks),
        onMapLongClick: (event: MapClickEvent): boolean => testMap.click('long click', event, testMap.consumeClicks),
        onUnhandledClick: (event: MapClickEvent) => {
          testMap.click('unhandled', event, false);
        },
      }) {
        this.overlays()
      }
    }
  }

  // The second map shows the same controller, without controls.
  @Builder
  secondMap() {
    MaplibreMap({ style: STYLE, controller: testMap.controller }) {
    }
  }
}
