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
        MapLibreMap({
          controller: testMap.controller,
          style: testMap.style,
          cameraBounds: testMap.cameraBounds,
          onStyleLoaded: () => {
            testMap.styleLoads++;
          },
          onMapError: (error: Error) => {
            testMap.errors.push(error.message);
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
    .id('map-host')
    .width('100%')
    .height('100%')
  }
}
