import { MapLibreMap } from '@maplibre/arkui';

import { testMap } from '../TestMaps';

@Entry
@ComponentV2
struct Index {
  aboutToAppear(): void {
    testMap.context = this.getUIContext();
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
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
