// Where a Marker or an OffscreenMarker goes, as MapLibre Compose's
// `placedAt` and `placedTowards` modifiers place content. ArkUI has no custom
// modifiers, so each wraps its content. A marker is the size of its content,
// and `.position()` puts it in the content box of the node that lays it out.
// After each layout, it reads where that box is from the frame nodes, since a
// marker's own frame node reports its position without the parent's padding,
// which `.position()` adds.

import { LengthMetrics, LengthUnit } from '@ohos.arkui.node';

import { contextScales, LengthScales, lengthInVp } from '../../camera/internal/Insets';
import { ScreenPoint } from '../../geometry/Geometry';
import { MapScope } from '../../map/internal/MapScope';

// Where a marker is laid out: the content box of its parent, the node that
// lays it out, in vp from the map's top-left corner, and the size of the
// marker's content.
export interface Layout {
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
export class LayoutReader {
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
export function positionAt(corner: ScreenPoint | undefined, layout: Layout | undefined): Position {
  return corner === undefined || layout === undefined ? { x: 0, y: 0 } :
    { x: corner.x - layout.x, y: corner.y - layout.y };
}
