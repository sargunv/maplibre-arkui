import { LatLng, MapLibreMap, MapMarker, MapScaleBar, ScaleBarUnits } from '@maplibre/arkui';

import { testMap } from '../TestMaps';

@Entry
@ComponentV2
struct Index {
  aboutToAppear(): void {
    testMap.context = this.getUIContext();
  }

  // A box whose bottom center the map pins to the coordinate.
  @Builder
  marker(coordinate: LatLng) {
    MapMarker({ controller: testMap.controller, coordinate: coordinate }) {
      Column()
        .id('marker')
        .width(20)
        .height(10)
        .backgroundColor(Color.Red)
    }
  }

  // It reads the units itself, since a builder's arguments don't update it.
  @Builder
  scaleBar() {
    MapScaleBar({ controller: testMap.controller, units: testMap.scaleBar ?? ScaleBarUnits.metric })
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
        } else {
          this.map()
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
      cameraBounds: testMap.cameraBounds,
      gestures: testMap.gestures,
      onStyleLoaded: () => {
        testMap.styleLoads++;
      },
      onMapError: (error: Error) => {
        testMap.errors.push(error.message);
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
    }
  }
}
