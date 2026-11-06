import { MapController, MapLibreMap } from '@maplibre/arkui';

import { DEMOTILES, LIBERTY } from './common';

// Two maps on one page, which share the default runtime and frame pacer.
@ComponentV2
export struct TwoMaps {
  private london: MapController = new MapController({
    camera: { center: { latitude: 51.5072, longitude: -0.1276 }, zoom: 11 },
  });
  private world: MapController = new MapController({
    camera: { center: { latitude: 20, longitude: 0 }, zoom: 1 },
  });

  build() {
    NavDestination() {
      Column({ space: 4 }) {
        MapLibreMap({ controller: this.london, style: LIBERTY })
          .layoutWeight(1)
        MapLibreMap({ controller: this.world, style: DEMOTILES })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
    .title('Two maps')
  }
}
