import {
  CameraPosition,
  LatLng,
  MapAttributionButton,
  MapAttributionOnlyOverlay,
  MapClickEvent,
  MapCompassButton,
  MapDefaultOverlay,
  MapDisappearingCompassButton,
  MapDisappearingScaleBar,
  MapFullOverlay,
  MapLibreMap,
  MapPlacedAt,
  MapPlacedTowards,
  MapPointerPinButton,
  MapScaleBar,
  MapZoomButtons,
  ScaleBarUnits,
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
      MapPlacedAt({ coordinate: testMap.placedAt! }) {
        this.box('placed-at')
      }
    } else {
      MapPlacedAt({ coordinate: testMap.placedAt!, alignment: testMap.placedAtAlignment }) {
        this.box('placed-at')
      }
    }
  }

  @Builder
  placedTowards() {
    MapPlacedTowards({
      coordinate: testMap.placedTowards!,
      onAngleChange: (angle: number) => {
        testMap.placedTowardsAngles.push(angle);
      },
    }) {
      this.box('placed-towards')
    }
  }

  @Builder
  pointerPin() {
    MapPointerPinButton({
      coordinate: testMap.pointerPin!,
      onTap: () => {
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
      MapScaleBar({ units: testMap.scaleBar ?? ScaleBarUnits.metric })
    } else {
      MapScaleBar({ units: testMap.scaleBar ?? ScaleBarUnits.metric, maxWidth: testMap.scaleBarMaxWidth })
    }
  }

  @Builder
  disappearingScaleBar() {
    MapDisappearingScaleBar({ units: ScaleBarUnits.metric, visibilityDurationMs: testMap.disappearingScaleBarMs ?? 3000 })
  }

  @Builder
  compass() {
    if (testMap.compassMs === undefined) {
      MapDisappearingCompassButton()
    } else {
      MapDisappearingCompassButton({ visibilityDurationMs: testMap.compassMs })
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
        MapZoomButtons()
      }
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .hitTestBehavior(HitTestMode.Transparent)
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (testMap.attribution) {
        MapAttributionButton()
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
      MapDefaultOverlay()
    } else if (testMap.overlay === 'full') {
      MapFullOverlay()
    } else if (testMap.overlay === 'attributionOnly') {
      MapAttributionOnlyOverlay()
    }
  }

  @Builder
  overlays() {
    this.preset()
    this.controls()
    Column() {
      if (testMap.scaleBar !== undefined) {
        this.scaleBar()
      }
      if (testMap.disappearingScaleBarMs !== undefined) {
        this.disappearingScaleBar()
      }
      if (testMap.alwaysShownCompass) {
        MapCompassButton()
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
  }

  build() {
    Column() {
      if (testMap.bareSurfaceShown) {
        XComponent({ type: XComponentType.SURFACE, controller: testMap.bareSurface })
          .width('100%')
          .height(300)
      }
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
      MapLibreMap({
        controller: testMap.controller,
        style: testMap.style,
        viewportInsets: testMap.viewportInsets,
        onStyleLoaded: () => {
          testMap.styleLoads++;
        },
      })
    } else {
      MapLibreMap({
        controller: testMap.controller,
        style: testMap.style,
        content: testMap.content,
        cameraBounds: testMap.cameraBounds,
        runtime: testMap.runtime,
        interactions: testMap.interactions,
        userLocation: testMap.userLocation,
        userHeading: testMap.userHeading,
        viewportInsets: testMap.viewportInsets,
        onStyleLoaded: () => {
          testMap.styleLoads++;
        },
        onCameraIdle: (camera: CameraPosition) => {
          testMap.cameraIdles.push(camera);
        },
        onMapError: (error: Error) => {
          testMap.errors.push(error.message);
          if (testMap.throwOnError) {
            throw new Error('the app handler failed');
          }
        },
        onGestureStart: () => {
          testMap.gestureStarts++;
          testMap.onGestureStart();
        },
        onGestureEnd: () => {
          testMap.gestureEnds++;
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
    MapLibreMap({ controller: testMap.controller, style: STYLE }) {
    }
  }
}
