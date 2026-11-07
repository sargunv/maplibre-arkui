// The overlay presets, the sets of controls that a MaplibreMap draws over
// itself, as MapLibre Compose's `MapOverlay` presets.

import {
  AttributionButton,
  DisappearingCompassButton,
  DisappearingScaleBar,
  LOGO_WIDTH,
  MaplibreLogo,
  ZoomButtons,
} from './Controls';
import { NO_INSETS } from './Insets';
import { controlKey, findScope, MapScope } from './scope';

// The space between the presets' controls and the edges of the part of the
// map that the app's UI leaves, in vp.
const SPACING = 8;

// The padding that keeps the presets' controls clear of the map's viewport
// insets, and SPACING in from them.
function controlsPadding(scope: MapScope | undefined): Padding {
  const insets = scope?.insets ?? NO_INSETS;
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
 * A `MaplibreLogo` at the map's bottom start, and an `AttributionButton` at
 * its bottom end. Most sources' terms require their attribution, so a map
 * keeps these unless the app shows the attribution elsewhere.
 *
 * Place it in a `MaplibreMap`'s overlay, where it fills its parent. Anywhere
 * else, it logs an error and draws nothing.
 */
@ComponentV2
export struct AttributionControls {
  @Local scope: MapScope | undefined = undefined;
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
      if (this.scope !== undefined) {
        MaplibreLogo()
          .alignRules(BOTTOM_START)
        AttributionButton()
          .alignRules(BOTTOM_END)
          .constraintSize({ maxWidth: this.attributionMaxWidth })
      }
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
      this.scope = findScope(this.getUIContext(), this.nodeId, 'AttributionControls');
    })
  }
}

/**
 * What a `MaplibreMap` draws without an overlay of the app's own: a
 * `DisappearingScaleBar` at the map's top start and a
 * `DisappearingCompassButton` at its top end, which show only while they
 * matter, and the controls of `AttributionControls` along the bottom.
 *
 * Place it in a `MaplibreMap`'s overlay, where it fills its parent. Anywhere
 * else, it logs an error and draws nothing.
 */
@ComponentV2
export struct DefaultControls {
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();

  build() {
    Stack() {
      if (this.scope !== undefined) {
        RelativeContainer() {
          DisappearingScaleBar()
            .alignRules(TOP_START)
          DisappearingCompassButton()
            .alignRules(TOP_END)
        }
        .width('100%')
        .height('100%')
        .padding(controlsPadding(this.scope))
        .hitTestBehavior(HitTestMode.Transparent)

        AttributionControls()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'DefaultControls');
    })
  }
}

/**
 * The controls of `DefaultControls`, and `ZoomButtons` in the middle of the
 * map's end edge, for users with a mouse and for accessibility.
 *
 * Place it in a `MaplibreMap`'s overlay, where it fills its parent. Anywhere
 * else, it logs an error and draws nothing.
 */
@ComponentV2
export struct FullControls {
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();

  build() {
    Stack() {
      if (this.scope !== undefined) {
        DefaultControls()
        RelativeContainer() {
          ZoomButtons()
            .alignRules(CENTER_END)
        }
        .width('100%')
        .height('100%')
        .padding(controlsPadding(this.scope))
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'FullControls');
    })
  }
}

// What a MaplibreMap draws when the app leaves out its trailing closure.
@Builder
export function defaultControls() {
  DefaultControls()
}
