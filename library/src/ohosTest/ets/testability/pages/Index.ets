import {
  CameraPosition,
  LatLng,
  MapCompass,
  MapLibreMap,
  MapMarker,
  MapScaleBar,
  ScaleBarUnits,
} from '@maplibre/arkui';

import { STYLE, testMap } from '../TestMaps';

@Entry
@ComponentV2
struct Index {
  aboutToAppear(): void {
    testMap.context = this.getUIContext();
  }

  // A box whose bottom center the map pins to the coordinate, unless a case
  // sets its anchor.
  @Builder
  marker(coordinate: LatLng) {
    if (testMap.markerAnchor === undefined) {
      MapMarker({ controller: testMap.controller, coordinate: coordinate }) {
        this.markerBox()
      }
    } else {
      MapMarker({ controller: testMap.controller, coordinate: coordinate, anchor: testMap.markerAnchor }) {
        this.markerBox()
      }
    }
  }

  @Builder
  markerBox() {
    Column()
      .id('marker')
      .width(20)
      .height(10)
      .backgroundColor(Color.Red)
  }

  // It reads the units itself, since a builder's arguments don't update it.
  @Builder
  scaleBar() {
    if (testMap.scaleBarMaxWidth === undefined) {
      MapScaleBar({ controller: testMap.controller, units: testMap.scaleBar ?? ScaleBarUnits.metric })
    } else {
      MapScaleBar({
        controller: testMap.controller,
        units: testMap.scaleBar ?? ScaleBarUnits.metric,
        maxWidth: testMap.scaleBarMaxWidth,
      })
    }
  }

  @Builder
  alwaysShownCompass() {
    MapCompass({ controller: testMap.controller, alwaysShown: true })
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
    MapLibreMap({
      controller: testMap.controller,
      style: testMap.style,
      content: testMap.content,
      cameraBounds: testMap.cameraBounds,
      runtime: testMap.runtime,
      gestures: testMap.gestures,
      userLocation: testMap.userLocation,
      userHeading: testMap.userHeading,
      compassEnabled: testMap.compass,
      scaleBarEnabled: testMap.scaleBarEnabled,
      zoomButtonsEnabled: testMap.zoomButtons,
      attributionEnabled: testMap.attribution,
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
    }) {
      if (testMap.scaleBar !== undefined) {
        this.scaleBar()
      }
      if (testMap.marker !== undefined) {
        this.marker(testMap.marker)
      }
      if (testMap.alwaysShownCompass) {
        this.alwaysShownCompass()
      }
    }
  }

  // The second map shows the same controller, without ornaments.
  @Builder
  secondMap() {
    MapLibreMap({
      controller: testMap.controller,
      style: STYLE,
      compassEnabled: false,
      attributionEnabled: false,
    })
  }
}
