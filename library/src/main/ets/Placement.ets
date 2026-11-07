// Components that place ArkUI content by coordinates in a MaplibreMap's
// overlay, as MapLibre Compose's `placedAt` and `placedTowards` modifiers do.
// ArkUI has no custom modifiers, so each wraps its content. A marker is the
// size of its content, and `.position()` puts it in the content box of the
// node that lays it out. After each layout, it reads where that box is from
// the frame nodes, since a marker's own frame node reports its position
// without the parent's padding, which `.position()` adds.

import { LengthMetrics, LengthUnit } from '@ohos.arkui.node';

import { LatLng, ScreenPoint } from './Geometry';
import { contextScales, isRtl, LengthScales, lengthInVp } from './Insets';
import { callHandler } from './log';
import { controlKey, findScope, MapScope } from './scope';

// What a trailing closure that the app leaves out builds.
@Builder
export function noContent() {
}

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

// Where a marker is laid out: the content box of its parent, the node that
// lays it out, in vp from the map's top-left corner, and the size of the
// marker's content.
interface Layout {
  x: number;
  y: number;
  width: number;
  height: number;
  contentWidth: number;
  contentHeight: number;
}

function sameLayout(a: Layout | undefined, b: Layout | undefined): boolean {
  return a !== undefined && b !== undefined && a.x === b.x && a.y === b.y && a.width === b.width &&
    a.height === b.height && a.contentWidth === b.contentWidth && a.contentHeight === b.contentHeight;
}

// A side of a node's padding or border in vp. A percentage counts as 0.
function sideInVp(side: LengthMetrics | undefined, scales: LengthScales): number {
  return side === undefined || side.unit === LengthUnit.PERCENT ? 0 : lengthInVp(side, scales);
}

// The layout of the marker whose root node has ID `key`, from the frame nodes
// as the latest layout left them.
function layoutOf(context: UIContext, scope: MapScope, key: string): Layout | undefined {
  const map = context.getAttachedFrameNodeById(scope.key);
  const marker = context.getAttachedFrameNodeById(key);
  const parent = marker?.getParent();
  if (map === null || map === undefined || marker === null || marker === undefined || parent === null ||
    parent === undefined) {
    return undefined;
  }
  const origin = map.getPositionToWindow();
  const position = parent.getPositionToWindow();
  const size = parent.getMeasuredSize();
  const content = marker.getMeasuredSize();
  const padding = parent.getUserConfigPadding();
  const border = parent.getUserConfigBorderWidth();
  const scales = contextScales(context);
  const left = sideInVp(padding.left, scales) + sideInVp(border.left, scales);
  const top = sideInVp(padding.top, scales) + sideInVp(border.top, scales);
  const right = sideInVp(padding.right, scales) + sideInVp(border.right, scales);
  const bottom = sideInVp(padding.bottom, scales) + sideInVp(border.bottom, scales);
  return {
    x: (position.x as number) - (origin.x as number) + left,
    y: (position.y as number) - (origin.y as number) + top,
    width: context.px2vp(size.width) - left - right,
    height: context.px2vp(size.height) - top - bottom,
    contentWidth: context.px2vp(content.width),
    contentHeight: context.px2vp(content.height),
  };
}

// Reads a marker's layout after each layout of its page, since the parent can
// move or resize without the marker.
class LayoutReader {
  private readonly context: UIContext;
  private readonly scope: MapScope;
  private readonly key: string;
  private readonly onChange: (layout: Layout | undefined) => void;
  private last: Layout | undefined = undefined;
  private readonly read = (): void => {
    const layout = layoutOf(this.context, this.scope, this.key);
    if (!sameLayout(layout, this.last)) {
      this.last = layout;
      this.onChange(layout);
    }
  };

  constructor(context: UIContext, scope: MapScope, key: string, onChange: (layout: Layout | undefined) => void) {
    this.context = context;
    this.scope = scope;
    this.key = key;
    this.onChange = onChange;
    context.getUIObserver().on('didLayout', this.read);
  }

  stop(): void {
    this.context.getUIObserver().off('didLayout', this.read);
  }
}

// A marker's `.position()` that puts its top-left corner at `corner`, in vp
// from the map's top-left corner.
function positionAt(corner: ScreenPoint | undefined, layout: Layout | undefined): Position {
  return corner === undefined || layout === undefined ? { x: 0, y: 0 } :
    { x: corner.x - layout.x, y: corner.y - layout.y };
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

// The pin's width and height in vp, and the diameter of its round part, a
// circle at the center. The pin's image, maplibre_pointer_pin, is 76 by 76,
// with a round part 48 across.
const PIN_SIZE = 64;
const PIN_ROUND_SIZE = PIN_SIZE * 48 / 76;

// Sets a button's accessibility text to a ResourceStr, which
// `accessibilityText()` takes only as a string or as a Resource.
class AccessibilityLabel implements AttributeModifier<ButtonAttribute> {
  private readonly label: ResourceStr;

  constructor(label: ResourceStr) {
    this.label = label;
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    if (typeof this.label === 'string') {
      instance.accessibilityText(this.label);
    } else {
      instance.accessibilityText(this.label as Resource);
    }
  }
}

/**
 * A button shaped like a map pin, on the edge of the map towards a coordinate
 * off the screen, which `OffscreenMarker` places. The pin turns to point at
 * the coordinate, and its content, such as a 24 vp icon, stays upright in its
 * round part. It hides while the coordinate is on the screen.
 *
 * ```ets
 * PointerPinButton({
 *   coordinate: PARIS,
 *   label: 'Paris',
 *   onPinClick: () => this.map.updateCamera({ center: PARIS }, { mode: CameraTransitionMode.EASE }),
 * }) {
 *   Image($r('sys.media.ohos_ic_public_location')).width(24).height(24)
 * }
 * ```
 *
 * It takes its label and click handler as parameters, rather than as
 * `.accessibilityText()` and `.onClick()`, because ArkUI would put those on a
 * node that the parent lays out by its own rules, not on the pin, as for
 * `Marker`.
 *
 * Place it in a `MaplibreMap`'s overlay; its parent sets the oval, as for
 * `OffscreenMarker`. It's the size of the pin, so taps beside it reach what's
 * under it. Anywhere but a map's overlay, it logs an error that names
 * `OffscreenMarker`, and draws nothing.
 */
@ComponentV2
export struct PointerPinButton {
  /** The coordinate that the pin points at. */
  @Require @Param coordinate: LatLng;
  /** What the pin leads to, which screen readers read as the button's text. */
  @Require @Param label: ResourceStr;
  /** The user clicked the pin. Called on the UI thread; the button logs what it throws. */
  @Event onPinClick: () => void = () => {
  };
  /** The content, in the trailing closure. */
  @BuilderParam content: () => void = noContent;
  @Local angle: number = 0;

  // The marker is the root, with no node of this component around it, so its
  // parent is the app's container.
  build() {
    OffscreenMarker({
      coordinate: this.coordinate,
      onAngleChange: (event: OffscreenMarkerAngleEvent) => {
        this.angle = event.angle;
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
    .attributeModifier(new AccessibilityLabel(this.label))
    .onClick(() => callHandler('onPinClick', () => this.onPinClick()))
  }
}
