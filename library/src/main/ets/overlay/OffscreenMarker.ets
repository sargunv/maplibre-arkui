import { LatLng, ScreenPoint } from '../geometry/Geometry';
import { controlKey, findScope, MapScope } from '../map/internal/MapScope';
import { callHandler } from '../runtime/internal/Log';
import { noContent } from './internal/NoContent';
import { Layout, LayoutReader, positionAt } from './internal/Placement';

/** What `OffscreenMarker.onAngleChange` reports. */
export interface OffscreenMarkerAngleEvent {
  /**
   * The direction from the oval's center towards the coordinate, in degrees
   * clockwise from up: at least 0, and less than 360.
   */
  angle: number;
}

// Where content placed towards a coordinate goes: a point on the edge of the
// oval, and the direction from the oval's center to it, in degrees clockwise
// from up.
interface Towards {
  x: number;
  y: number;
  angle: number;
}

// Where the line from the center of a `width` by `height` box to `target`
// crosses the oval inscribed in the box, or undefined while `target` is
// inside the oval.
function ovalCrossing(width: number, height: number, target: ScreenPoint): Towards | undefined {
  if (!(width > 0 && height > 0)) {
    return undefined;
  }
  const dx = target.x - width / 2;
  const dy = target.y - height / 2;
  const theta = Math.atan2(dy, dx) + Math.PI / 2;
  const sin = Math.sin(theta);
  const cos = Math.cos(theta);
  const a = height / 2;
  const b = width / 2;
  const radius = a * b / Math.sqrt(a * a * sin * sin + b * b * cos * cos);
  const x = sin * radius;
  const y = -cos * radius;
  if (dx * dx + dy * dy < x * x + y * y) {
    return undefined;
  }
  return { x: x + width / 2, y: y + height / 2, angle: (theta * 180 / Math.PI + 360) % 360 };
}

/**
 * ArkUI content on the edge of an oval that fills its parent's content box,
 * on the line from the oval's center towards a coordinate, for a coordinate
 * off the screen. The content hides while the coordinate is inside the oval,
 * and until the map shows a frame. The point of the content's own inscribed
 * oval that faces the coordinate touches the parent's oval, so round content
 * stays inside it.
 *
 * Place it in a `MaplibreMap`'s overlay. The marker is the size of its
 * content, so its parent, the overlay or a container in it, sets the oval:
 * size the container to the map, as `.width('100%').height('100%')` does, and
 * pad it to move the oval in from the map's edges. A percentage in the
 * parent's padding counts as 0. Chain universal attributes on the content, as
 * for `Marker`. Anywhere but a map's overlay, it logs an error and draws
 * nothing. `onAngleChange` gives the direction towards the coordinate, to
 * turn the content with it, as `PointerPinButton` does.
 */
@ComponentV2
export struct OffscreenMarker {
  /** The coordinate that the content points towards. */
  @Require @Param coordinate: LatLng;
  /**
   * The direction towards the coordinate changed. It's called as the content
   * first shows, and as the direction changes, on the UI thread. The marker
   * logs what it throws.
   */
  @Event onAngleChange: (event: OffscreenMarkerAngleEvent) => void = (event: OffscreenMarkerAngleEvent) => {
  };
  /** The content, in the trailing closure. */
  @BuilderParam content: () => void = noContent;
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();
  @Local layout: Layout | undefined = undefined;
  private reader: LayoutReader | undefined = undefined;
  // The angle that onAngleChange last reported.
  private reportedAngle: number = NaN;

  // Where the line towards the coordinate crosses the oval, in vp from the
  // map's top-left corner.
  @Computed
  get towards(): Towards | undefined {
    const layout = this.layout;
    const point = this.scope?.controller.viewport?.project(this.coordinate);
    if (layout === undefined || point === undefined) {
      return undefined;
    }
    const crossing = ovalCrossing(layout.width, layout.height, { x: point.x - layout.x, y: point.y - layout.y });
    return crossing === undefined ? undefined :
      { x: crossing.x + layout.x, y: crossing.y + layout.y, angle: crossing.angle };
  }

  @Monitor('towards')
  towardsChanged(): void {
    const angle = this.towards?.angle;
    if (angle !== undefined && angle !== this.reportedAngle) {
      this.reportedAngle = angle;
      callHandler('onAngleChange', () => this.onAngleChange({ angle: angle }));
    }
  }

  // Where the content's top-left corner goes, so the point of its inscribed
  // oval that faces the coordinate is on the parent's oval.
  @Computed
  get corner(): ScreenPoint | undefined {
    const towards = this.towards;
    const layout = this.layout;
    if (towards === undefined || layout === undefined) {
      return undefined;
    }
    const theta = towards.angle * Math.PI / 180;
    return {
      x: towards.x - layout.contentWidth * (1 + Math.sin(theta)) / 2,
      y: towards.y - layout.contentHeight * (1 - Math.cos(theta)) / 2,
    };
  }

  build() {
    Stack() {
      this.content()
    }
    .position(positionAt(this.corner, this.layout))
    .visibility(this.corner === undefined ? Visibility.Hidden : Visibility.Visible)
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'OffscreenMarker');
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
