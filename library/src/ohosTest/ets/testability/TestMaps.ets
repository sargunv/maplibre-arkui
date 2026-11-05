// The map that the test page shows, which the cases read and change.

import { BoundOptions, LatLng, MapController, MapGestureOptions, ScaleBarUnits } from '@maplibre/arkui';

// A style without network requests.
export const STYLE =
  '{"version":8,"sources":{},"layers":[{"id":"background","type":"background","paint":{"background-color":"#4a90d9"}}]}';

@ObservedV2
export class TestMap {
  // The map is on the page while this is true.
  @Trace shown: boolean = true;
  @Trace style: string = STYLE;
  @Trace cameraBounds: BoundOptions | undefined = undefined;
  // The ornament cases turn these on: a scale bar in these units, and a
  // marker at this coordinate. Content that moves with the camera makes the
  // emulator's llvmpipe crash more often, so other cases go without.
  @Trace scaleBar: ScaleBarUnits | undefined = undefined;
  @Trace marker: LatLng | undefined = undefined;
  @Trace gestures: MapGestureOptions = {};
  // The map is 300 vp tall at the top of a Scroll while this is true, and fills
  // the page otherwise.
  @Trace inScroll: boolean = false;
  // What the map's events reported.
  styleLoads: number = 0;
  errors: string[] = [];
  gestureStarts: number = 0;
  gestureEnds: number = 0;
  // What a case does as a gesture starts, as an app would.
  onGestureStart: () => void = () => {
  };
  controller: MapController = new MapController({ camera: { zoom: 1 } });
  scroller: Scroller = new Scroller();
  // The page's UI context, once the page appears.
  context: UIContext | undefined = undefined;
}

export const testMap: TestMap = new TestMap();
