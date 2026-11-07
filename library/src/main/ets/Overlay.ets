// The overlay presets, the sets of controls that a MaplibreMap draws over
// itself, as MapLibre Compose's `MapOverlay` presets.

import {
  LOGO_WIDTH,
  MapAttributionButton,
  MapDisappearingCompassButton,
  MapDisappearingScaleBar,
  MapLibreLogo,
  MapZoomButtons,
} from './Controls';
import { controlKey, findScope, MapScope } from './scope';

// The space between the presets' controls and the edges of the part of the
// map that the app's UI leaves, in vp.
const SPACING = 8;

// The padding that keeps the presets' controls clear of the map's viewport
// insets, and SPACING in from them.
function controlsPadding(scope: MapScope): Padding {
  const insets = scope.insets;
  return {
    top: insets.top + SPACING,
    left: insets.left + SPACING,
    bottom: insets.bottom + SPACING,
    right: insets.right + SPACING,
  };
}

// Where the controls go. ets-loader rejects `layoutGravity`, so they align in
// a RelativeContainer.
const CONTAINER = '__container__';
const TOP_START: LocalizedAlignRuleOptions = {
  top: { anchor: CONTAINER, align: VerticalAlign.Top },
  start: { anchor: CONTAINER, align: HorizontalAlign.Start },
};
const TOP_END: LocalizedAlignRuleOptions = {
  top: { anchor: CONTAINER, align: VerticalAlign.Top },
  end: { anchor: CONTAINER, align: HorizontalAlign.End },
};
const CENTER_END: LocalizedAlignRuleOptions = {
  center: { anchor: CONTAINER, align: VerticalAlign.Center },
  end: { anchor: CONTAINER, align: HorizontalAlign.End },
};
const BOTTOM_START: LocalizedAlignRuleOptions = {
  bottom: { anchor: CONTAINER, align: VerticalAlign.Bottom },
  start: { anchor: CONTAINER, align: HorizontalAlign.Start },
};
const BOTTOM_END: LocalizedAlignRuleOptions = {
  bottom: { anchor: CONTAINER, align: VerticalAlign.Bottom },
  end: { anchor: CONTAINER, align: HorizontalAlign.End },
};

/**
 * The MapLibre logo at the map's bottom start, and a `MapAttributionButton`
 * at its bottom end. Most sources' terms require their attribution, so a map
 * keeps these unless the app shows the attribution elsewhere.
 */
@ComponentV2
export struct MapAttributionOnlyOverlay {
  @Local scope: MapScope = new MapScope();
  private readonly nodeId: string = controlKey();
  // The overlay's width, so the expanded attribution stops short of the logo.
  @Local overlayWidth: number = 0;

  // The widest the attribution grows, between the logo and the end edge,
  // within the padding as it is now.
  @Computed
  get attributionMaxWidth(): number {
    const padding = controlsPadding(this.scope);
    return Math.max(0,
      this.overlayWidth - (padding.left as number) - (padding.right as number) - LOGO_WIDTH - SPACING);
  }

  build() {
    RelativeContainer() {
      MapLibreLogo()
        .alignRules(BOTTOM_START)
      MapAttributionButton()
        .alignRules(BOTTOM_END)
        .constraintSize({ maxWidth: this.attributionMaxWidth })
    }
    .width('100%')
    .height('100%')
    .padding(controlsPadding(this.scope))
    .hitTestBehavior(HitTestMode.Transparent)
    .onSizeChange((old: SizeOptions, size: SizeOptions) => {
      this.overlayWidth = size.width as number;
    })
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId);
    })
  }
}

/**
 * What a `MaplibreMap` draws without an overlay of the app's own: a
 * `MapDisappearingScaleBar` at the map's top start and a
 * `MapDisappearingCompassButton` at its top end, which show only while they
 * matter, and the controls of `MapAttributionOnlyOverlay` along the bottom.
 */
@ComponentV2
export struct MapDefaultOverlay {
  @Local scope: MapScope = new MapScope();
  private readonly nodeId: string = controlKey();

  build() {
    Stack() {
      RelativeContainer() {
        MapDisappearingScaleBar()
          .alignRules(TOP_START)
        MapDisappearingCompassButton()
          .alignRules(TOP_END)
      }
      .width('100%')
      .height('100%')
      .padding(controlsPadding(this.scope))
      .hitTestBehavior(HitTestMode.Transparent)

      MapAttributionOnlyOverlay()
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId);
    })
  }
}

/**
 * The controls of `MapDefaultOverlay`, and `MapZoomButtons` in the middle of
 * the map's end edge, for users with a mouse and for accessibility.
 */
@ComponentV2
export struct MapFullOverlay {
  @Local scope: MapScope = new MapScope();
  private readonly nodeId: string = controlKey();

  build() {
    Stack() {
      MapDefaultOverlay()
      RelativeContainer() {
        MapZoomButtons()
          .alignRules(CENTER_END)
      }
      .width('100%')
      .height('100%')
      .padding(controlsPadding(this.scope))
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId);
    })
  }
}

// What a MaplibreMap draws when the app leaves out its trailing closure.
@Builder
export function defaultOverlay() {
  MapDefaultOverlay()
}
