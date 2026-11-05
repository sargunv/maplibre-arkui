// The map that the test page shows, which the cases read and change.

import { BoundOptions, LatLng, MapController } from '@maplibre/arkui';

// A style without network requests.
export const STYLE =
  '{"version":8,"sources":{},"layers":[{"id":"background","type":"background","paint":{"background-color":"#4a90d9"}}]}';

@ObservedV2
export class TestMap {
  // The map is on the page while this is true.
  @Trace shown: boolean = true;
  @Trace style: string = STYLE;
  @Trace cameraBounds: BoundOptions | undefined = undefined;
  // The ornament cases turn these on. Content that moves with the camera
  // makes the emulator's llvmpipe crash more often, so other cases go
  // without.
  @Trace scaleBar: boolean = false;
  @Trace marker: LatLng | undefined = undefined;
  // What the map's events reported.
  styleLoads: number = 0;
  errors: string[] = [];
  controller: MapController = new MapController({ camera: { zoom: 1 } });
  // The page's UI context, once the page appears.
  context: UIContext | undefined = undefined;
}

export const testMap: TestMap = new TestMap();
