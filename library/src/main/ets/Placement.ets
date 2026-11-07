// Components that place ArkUI content by coordinates in a MaplibreMap's
// overlay, as MapLibre Compose's `placedAt` and `placedTowards` modifiers do.
// ArkUI has no custom modifiers, so each wraps its content. A wrapper fills
// its parent, and finds where the map's points are in its own frame from
// where it and the map are on the page, so it works anywhere in the overlay.

import { LatLng, ScreenPoint } from './Geometry';
import { isRtl } from './Insets';
import { controlKey, findScope, MapScope } from './scope';

// What a trailing closure that the app leaves out builds.
@Builder
export function noContent() {
}

// The point of content that `alignment` names, as percentages of its size
// from its top-left corner, with start and end in the app's direction.
function anchorOf(alignment: Alignment): Position {
  const rtl = isRtl();
  const start = rtl ? '100%' : '0%';
  const end = rtl ? '0%' : '100%';
  switch (alignment) {
    case Alignment.TopStart:
      return { x: start, y: '0%' };
    case Alignment.Top:
      return { x: '50%', y: '0%' };
    case Alignment.TopEnd:
      return { x: end, y: '0%' };
    case Alignment.Start:
      return { x: start, y: '50%' };
    case Alignment.End:
      return { x: end, y: '50%' };
    case Alignment.BottomStart:
      return { x: start, y: '100%' };
    case Alignment.Bottom:
      return { x: '50%', y: '100%' };
    case Alignment.BottomEnd:
      return { x: end, y: '100%' };
    default:
      return { x: '50%', y: '50%' };
  }
}

// Where a wrapper is: its size, and its top-left corner on the page, in vp.
interface Frame {
  width: number;
  height: number;
  x: number;
  y: number;
}

function frameOf(area: Area): Frame {
  return {
    width: area.width as number,
    height: area.height as number,
    x: area.globalPosition.x as number,
    y: area.globalPosition.y as number,
  };
}

// Where `coordinate` is in the frame on screen, in vp from the top-left corner
// of `frame`, which is somewhere over the map.
function pointIn(scope: MapScope, frame: Frame, coordinate: LatLng): ScreenPoint | undefined {
  const point = scope.controller.viewport?.project(coordinate);
  if (point === undefined) {
    return undefined;
  }
  return { x: point.x - (frame.x - scope.origin.x), y: point.y - (frame.y - scope.origin.y) };
}

/**
 * ArkUI content pinned to a coordinate, which follows the map as its camera
 * moves. Place it in a `MaplibreMap`'s overlay, its trailing closure:
 *
 * ```ets
 * MaplibreMap({ controller: this.map, style: STYLE }) {
 *   MapDefaultOverlay()
 *   MapPlacedAt({ coordinate: { latitude: 48.8566, longitude: 2.3522 }, alignment: Alignment.Bottom }) {
 *     Text('Paris')
 *   }
 * }
 * ```
 *
 * It fills its parent and passes touches outside its content through to the
 * map. Its content hides until the map shows a frame, and while it's entirely
 * outside the wrapper. The content moves in the ArkUI frame after the map
 * draws, so it can trail the map by a frame.
 */
@ComponentV2
export struct MapPlacedAt {
  @Local scope: MapScope = new MapScope();
  private readonly nodeId: string = controlKey();
  /** Where the content goes. A new value moves it. */
  @Require @Param coordinate: LatLng;
  /**
   * The point of the content that sits on the coordinate. The default is its
   * center; `Alignment.Bottom` stands it on the coordinate, as for a pin.
   */
  @Param alignment: Alignment = Alignment.Center;
  /** The content, in the trailing closure. */
  @BuilderParam content: () => void = noContent;
  @Local frame: Frame | undefined = undefined;
  @Local contentSize: SizeOptions = { width: 0, height: 0 };

  @Computed
  get point(): ScreenPoint | undefined {
    const frame = this.frame;
    return frame === undefined ? undefined : pointIn(this.scope, frame, this.coordinate);
  }

  @Computed
  get anchor(): Position {
    return anchorOf(this.alignment);
  }

  // Whether any of the content is inside the wrapper.
  @Computed
  get inside(): boolean {
    const point = this.point;
    const frame = this.frame;
    if (point === undefined || frame === undefined) {
      return false;
    }
    const width = this.contentSize.width as number;
    const height = this.contentSize.height as number;
    const left = point.x - width * parseFloat(this.anchor.x as string) / 100;
    const top = point.y - height * parseFloat(this.anchor.y as string) / 100;
    return left + width >= 0 && top + height >= 0 && left <= frame.width && top <= frame.height;
  }

  build() {
    Stack() {
      Stack() {
        this.content()
      }
      .position({ x: this.point?.x ?? 0, y: this.point?.y ?? 0 })
      .markAnchor(this.anchor)
      .visibility(this.inside ? Visibility.Visible : Visibility.Hidden)
      .onSizeChange((old: SizeOptions, size: SizeOptions) => {
        this.contentSize = size;
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .onAreaChange((old: Area, area: Area) => {
      this.frame = frameOf(area);
    })
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId);
    })
  }
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
 * ArkUI content on the edge of an oval that fills the wrapper, on the line
 * from the oval's center towards a coordinate, for a coordinate off the
 * screen. The content hides while the coordinate is inside the oval, and until
 * the map shows a frame. The point of the content's own inscribed oval that
 * faces the coordinate touches the wrapper's oval, so round content stays
 * inside it.
 *
 * Place it in a `MaplibreMap`'s overlay; pad its parent to move the oval in
 * from the map's edges. `onAngleChange` gives the direction towards the
 * coordinate, to turn the content with it, as `MapPointerPinButton` does.
 */
@ComponentV2
export struct MapPlacedTowards {
  @Local scope: MapScope = new MapScope();
  private readonly nodeId: string = controlKey();
  /** The coordinate that the content points towards. */
  @Require @Param coordinate: LatLng;
  /** The content, in the trailing closure. */
  @BuilderParam content: () => void = noContent;
  /**
   * The direction from the oval's center towards the coordinate changed, in
   * degrees clockwise from up, from 0 to 360. It's called as the content
   * shows, and as it moves.
   */
  @Event onAngleChange: (angle: number) => void = (angle: number) => {
  };
  @Local frame: Frame | undefined = undefined;

  @Computed
  get towards(): Towards | undefined {
    const frame = this.frame;
    const point = frame === undefined ? undefined : pointIn(this.scope, frame, this.coordinate);
    return frame === undefined || point === undefined ? undefined : ovalCrossing(frame.width, frame.height, point);
  }

  @Monitor('towards')
  towardsChanged(): void {
    const towards = this.towards;
    if (towards !== undefined) {
      this.onAngleChange(towards.angle);
    }
  }

  build() {
    Stack() {
      Stack() {
        this.content()
      }
      .position({ x: this.towards?.x ?? 0, y: this.towards?.y ?? 0 })
      .markAnchor(this.anchor())
      .visibility(this.towards === undefined ? Visibility.Hidden : Visibility.Visible)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .onAreaChange((old: Area, area: Area) => {
      this.frame = frameOf(area);
    })
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId);
    })
  }

  // The point of the content's inscribed oval that faces the coordinate.
  private anchor(): Position {
    const theta = (this.towards?.angle ?? 0) * Math.PI / 180;
    return { x: `${50 * (1 + Math.sin(theta))}%`, y: `${50 * (1 - Math.cos(theta))}%` };
  }
}

// The pin's width and height in vp, and the diameter of its round part, a
// circle at the center. The pin's image, maplibre_pointer_pin, is 76 by 76,
// with a round part 48 across.
const PIN_SIZE = 64;
const PIN_ROUND_SIZE = PIN_SIZE * 48 / 76;

/**
 * A button shaped like a map pin, on the edge of the map towards a coordinate
 * off the screen, which `MapPlacedTowards` places. The pin turns to point at
 * the coordinate, and its content, such as a 24 vp icon, stays upright in its
 * round part. It hides while the coordinate is on the screen.
 *
 * ```ets
 * MapPointerPinButton({
 *   coordinate: PARIS,
 *   onTap: () => this.map.updateCamera({ center: PARIS }, { mode: CameraTransitionMode.EASE }),
 * }) {
 *   Image($r('sys.media.ohos_ic_public_location')).width(24).height(24)
 * }
 * ```
 */
@ComponentV2
export struct MapPointerPinButton {
  /** The coordinate that the pin points at. */
  @Require @Param coordinate: LatLng;
  /** The content, in the trailing closure. */
  @BuilderParam content: () => void = noContent;
  /** The user tapped the pin. */
  @Event onTap: () => void = () => {
  };
  @Local angle: number = 0;

  build() {
    MapPlacedTowards({
      coordinate: this.coordinate,
      onAngleChange: (angle: number) => {
        this.angle = angle;
      },
    }) {
      this.pin()
    }
  }

  @Builder
  pin() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Stack() {
        Image($r('app.media.maplibre_pointer_pin'))
          .width(PIN_SIZE)
          .height(PIN_SIZE)
          .fillColor($r('sys.color.comp_background_primary'))
          .draggable(false)
          .rotate({ angle: this.angle })
        Stack() {
          this.content()
        }
        .width(PIN_ROUND_SIZE)
        .height(PIN_ROUND_SIZE)
        .borderRadius(PIN_ROUND_SIZE / 2)
        .clip(true)
      }
      .width(PIN_SIZE)
      .height(PIN_SIZE)
    }
    .width(PIN_SIZE)
    .height(PIN_SIZE)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .onClick(() => this.onTap())
  }
}
