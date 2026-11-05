import { LatLng, ScreenPoint } from '@maplibre/native-ffi';

import { MapController } from './MapController';

@Builder
function noContent() {
}

/**
 * ArkUI content pinned to a coordinate, which follows the map as its camera
 * moves. Place it in a `MapLibreMap`'s content, or anywhere else that has the
 * map's size and top-left corner:
 *
 * ```ets
 * MapLibreMap({ controller: this.map, style: STYLE }) {
 *   MapMarker({ controller: this.map, coordinate: { latitude: 48.8566, longitude: 2.3522 } }) {
 *     Text('Paris')
 *   }
 * }
 * ```
 *
 * It fills its parent and passes touches outside its content through to the
 * map. It hides until the map shows a frame. The content moves in the ArkUI
 * frame after the map draws, so it can trail the map by a frame.
 */
@ComponentV2
export struct MapMarker {
  /** The controller of the map that the content is on. */
  @Require @Param controller: MapController;
  /** Where the content goes. A new value moves it. */
  @Require @Param coordinate: LatLng;
  /**
   * The point of the content that sits on the coordinate, from its top-left
   * corner. Percentages are of the content's size. The default is the middle
   * of its bottom edge, for a pin.
   */
  @Param anchor: Position = { x: '50%', y: '100%' };
  /** The content, in the trailing closure. */
  @BuilderParam content: () => void = noContent;

  @Computed
  get point(): ScreenPoint | undefined {
    return this.controller.pixelForLatLng(this.coordinate);
  }

  build() {
    Stack() {
      Stack() {
        this.content()
      }
      .position({ x: this.point?.x ?? 0, y: this.point?.y ?? 0 })
      .markAnchor(this.anchor)
      .visibility(this.point === undefined ? Visibility.Hidden : Visibility.Visible)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
