import { LatLng, ScreenPoint } from '../geometry/Geometry';
import { isRtl } from '../geometry/internal/Direction';
import { controlKey, findScope, MapScope } from '../map/internal/MapScope';
import { noContent } from './internal/NoContent';
import { Layout, LayoutReader, positionAt } from './internal/Placement';

// The point of content that `alignment` names, as fractions of its width and
// height from its top-left corner, with start and end in the app's direction.
function anchorOf(alignment: Alignment): ScreenPoint {
  const rtl = isRtl();
  const start = rtl ? 1 : 0;
  const end = rtl ? 0 : 1;
  switch (alignment) {
    case Alignment.TopStart:
      return { x: start, y: 0 };
    case Alignment.Top:
      return { x: 0.5, y: 0 };
    case Alignment.TopEnd:
      return { x: end, y: 0 };
    case Alignment.Start:
      return { x: start, y: 0.5 };
    case Alignment.End:
      return { x: end, y: 0.5 };
    case Alignment.BottomStart:
      return { x: start, y: 1 };
    case Alignment.Bottom:
      return { x: 0.5, y: 1 };
    case Alignment.BottomEnd:
      return { x: end, y: 1 };
    default:
      return { x: 0.5, y: 0.5 };
  }
}

/**
 * ArkUI content pinned to a coordinate, which follows the map as its camera
 * moves. Place it in a `MaplibreMap`'s overlay, its trailing closure:
 *
 * ```ets
 * MaplibreMap({ controller: this.map, style: STYLE }) {
 *   DefaultControls()
 *   Marker({ coordinate: { latitude: 48.8566, longitude: 2.3522 }, alignment: Alignment.Bottom }) {
 *     Text('Paris')
 *       .onClick(() => this.showParis())
 *   }
 * }
 * ```
 *
 * The marker is the size of its content, so taps beside the content reach
 * what's under it. Its parent, the overlay or a container in it, should cover
 * the map, as `.width('100%').height('100%')` does, because ArkUI doesn't
 * give a node the taps outside its parent. Chain universal attributes, such
 * as `.onClick()` and `.accessibilityText()`, on the content, not on the
 * marker: ArkUI puts a custom component's attributes on a node of their own,
 * which the parent lays out by its own rules, not where the marker puts the
 * content.
 *
 * Its content hides until the map shows a frame, and while it's entirely off
 * the map. It moves in the ArkUI frame after the map draws, so it can trail
 * the map by a frame. Anywhere but a map's overlay, it logs an error and draws
 * nothing.
 */
@ComponentV2
export struct Marker {
  /** Where the content goes. A new value moves it. */
  @Require @Param coordinate: LatLng;
  /**
   * The point of the content that sits on the coordinate. The default is its
   * center; `Alignment.Bottom` stands it on the coordinate, as for a pin.
   * Start and end follow the direction of the app's language, not a
   * `.direction()` on an ancestor.
   */
  @Param alignment: Alignment = Alignment.Center;
  /** The content, in the trailing closure. */
  @BuilderParam content: () => void = noContent;
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();
  @Local layout: Layout | undefined = undefined;
  private reader: LayoutReader | undefined = undefined;

  // Where the content's top-left corner goes, in vp from the map's top-left
  // corner.
  @Computed
  get corner(): ScreenPoint | undefined {
    const point = this.scope?.controller.viewport?.project(this.coordinate);
    const layout = this.layout;
    if (point === undefined || layout === undefined) {
      return undefined;
    }
    const anchor = anchorOf(this.alignment);
    return { x: point.x - layout.contentWidth * anchor.x, y: point.y - layout.contentHeight * anchor.y };
  }

  // Whether any of the content is on the map.
  @Computed
  get onMap(): boolean {
    const corner = this.corner;
    const layout = this.layout;
    const size = this.scope?.controller.viewport?.size;
    return corner !== undefined && layout !== undefined && size !== undefined &&
      corner.x + layout.contentWidth >= 0 && corner.y + layout.contentHeight >= 0 &&
      corner.x <= (size.width as number) && corner.y <= (size.height as number);
  }

  build() {
    Stack() {
      this.content()
    }
    .position(positionAt(this.corner, this.layout))
    .visibility(this.onMap ? Visibility.Visible : Visibility.Hidden)
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'Marker');
      this.reader?.stop();
      if (this.scope !== undefined) {
        this.reader = new LayoutReader(this.getUIContext(), this.scope, this.nodeId, (layout: Layout | undefined) => {
          this.layout = layout;
        });
      }
    })
    .onDetach(() => {
      this.reader?.stop();
      this.reader = undefined;
    })
  }
}
