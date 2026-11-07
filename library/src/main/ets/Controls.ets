// The controls that a MaplibreMap's overlay presets draw, which apps can also
// place in the overlay themselves. Each finds its map through the overlay's
// MapScope, and reads the frame on screen through the viewport of the map's
// controller, so it follows animations. They draw with the system's colors, so
// they follow dark mode, and label themselves with the library's localized
// strings.

import common from '@ohos.app.ability.common';
import { LengthMetrics } from '@ohos.arkui.node';
import i18n from '@ohos.i18n';
import intl from '@ohos.intl';

import { CameraTransitionMode } from './CameraPosition';
import { GESTURE_ANIMATION_MS } from './gestures';
import { logError } from './log';
import { afterDelay, controlKey, findScope, MapScope } from './scope';

const BUTTON_SIZE = 40;
const FADE_MS = 200;
const DEFAULT_MAX_WIDTH = 100;

// How far the camera turns from north, from 0 to 180 degrees.
function turnFromNorth(bearing: number): number {
  return Math.abs((bearing % 360 + 540) % 360 - 180);
}

// A control's `maxWidth`, or the default with an error in the log when it
// isn't finite and above 0.
function validMaxWidth(control: string, maxWidth: number): number {
  if (maxWidth > 0 && maxWidth < Infinity) {
    return maxWidth;
  }
  logError(`${control} maxWidth must be finite and above 0, not ${maxWidth}; using ${DEFAULT_MAX_WIDTH}`);
  return DEFAULT_MAX_WIDTH;
}

// A control's `visibilityDurationMs`, or `fallback` with an error in the log
// when it isn't at least 0.
function validDuration(control: string, durationMs: number, fallback: number): number {
  if (durationMs >= 0) {
    return durationMs;
  }
  logError(`${control} visibilityDurationMs must be at least 0, not ${durationMs}; using ${fallback}`);
  return fallback;
}

// Runs `hide` in the first frame after `durationMs`, unless that's Infinity.
function hideAfter(context: UIContext, durationMs: number, hide: () => void): void {
  if (durationMs < Infinity) {
    afterDelay(context, durationMs, hide);
  }
}

/**
 * A compass that points north, and turns the map north and flat when tapped.
 * It always shows; `DisappearingCompassButton` shows only while the map is
 * rotated or tilted.
 *
 * Place it in a `MaplibreMap`'s overlay. Anywhere else, it logs an error and
 * draws nothing.
 */
@ComponentV2
export struct CompassButton {
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();

  @Computed
  get bearing(): number {
    return this.scope?.controller.viewport?.camera.bearing ?? 0;
  }

  build() {
    Stack() {
      if (this.scope !== undefined) {
        Stack() {
          Column() {
            Polygon({ width: 10, height: 13 })
              .points([[0, 13], [5, 0], [10, 13]])
              .fill('#e53935')
            Polygon({ width: 10, height: 13 })
              .points([[0, 0], [5, 13], [10, 0]])
              .fill($r('sys.color.icon_secondary'))
          }
          .rotate({ angle: -this.bearing })
        }
        .width(BUTTON_SIZE)
        .height(BUTTON_SIZE)
        .borderRadius(BUTTON_SIZE / 2)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .shadow(ShadowStyle.OUTER_DEFAULT_XS)
        .accessibilityText($r('app.string.maplibre_compass'))
        .onClick(() => {
          this.scope?.controller.updateCamera({ bearing: 0, pitch: 0 },
            { mode: CameraTransitionMode.EASE, durationMs: GESTURE_ANIMATION_MS })
            .catch((error: Error) => logError(error.message));
        })
      }
    }
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'CompassButton');
    })
  }
}

/**
 * A `CompassButton` that fades in while the map is rotated or tilted, and
 * fades out once the map faces north and looks straight down again.
 *
 * Place it in a `MaplibreMap`'s overlay. Anywhere else, it logs an error and
 * draws nothing.
 */
@ComponentV2
export struct DisappearingCompassButton {
  /**
   * How long it stays after the map turns back north and flat, in ms: at least
   * 0, or Infinity to stay. 1000 by default. Another value logs an error, and
   * 1000 takes its place.
   */
  @Param visibilityDurationMs: number = 1000;
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();
  @Local shown: boolean = false;
  // Counts the changes of `turned`, so a hide that a later turn overtook
  // doesn't run.
  private turns: number = 0;

  @Computed
  get durationMs(): number {
    return validDuration('DisappearingCompassButton', this.visibilityDurationMs, 1000);
  }

  @Computed
  get turned(): boolean {
    const camera = this.scope?.controller.viewport?.camera;
    return camera !== undefined && (turnFromNorth(camera.bearing) > 0.5 || camera.pitch > 0.5);
  }

  @Monitor('turned')
  turnedChanged(): void {
    const turn = ++this.turns;
    if (this.turned) {
      this.shown = true;
      return;
    }
    hideAfter(this.getUIContext(), this.durationMs, () => {
      if (turn === this.turns) {
        this.shown = false;
      }
    });
  }

  build() {
    Stack() {
      if (this.shown) {
        CompassButton()
          .transition(TransitionEffect.OPACITY.animation({ duration: FADE_MS }))
      }
    }
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'DisappearingCompassButton');
    })
  }
}

// What a press of the zoom buttons is moving the camera to.
interface ZoomStep {
  zoomIn: boolean;
  zoom: number;
}

/**
 * Buttons that zoom the map in and out by one level. Quick presses in one
 * direction add up, so three zoom three levels.
 *
 * Place them in a `MaplibreMap`'s overlay. Anywhere else, they log an error
 * and draw nothing.
 */
@ComponentV2
export struct ZoomButtons {
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();
  // A step steps on from the last one while it animates in the same
  // direction. Otherwise, it steps from the camera: the map may have clamped
  // the last step, and a gesture moves the camera elsewhere.
  private step: ZoomStep | undefined = undefined;

  @Monitor('scope.gesturing')
  gesturingChanged(): void {
    this.step = undefined;
  }

  build() {
    Stack() {
      if (this.scope !== undefined) {
        Column() {
          this.zoomButton($r('sys.media.ohos_ic_public_add'), $r('app.string.maplibre_zoom_in'), 1)
          Divider().width(BUTTON_SIZE / 2)
          this.zoomButton($r('sys.media.ohos_ic_public_minus'), $r('app.string.maplibre_zoom_out'), -1)
        }
        .borderRadius(BUTTON_SIZE / 2)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .shadow(ShadowStyle.OUTER_DEFAULT_XS)
      }
    }
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'ZoomButtons');
    })
  }

  @Builder
  zoomButton(icon: Resource, label: Resource, delta: number) {
    Button({ type: ButtonType.Circle }) {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor($r('sys.color.icon_primary'))
    }
    .width(BUTTON_SIZE)
    .height(BUTTON_SIZE)
    .backgroundColor(Color.Transparent)
    .accessibilityText(label)
    .onClick(() => this.zoomBy(delta))
  }

  private zoomBy(delta: number): void {
    const controller = this.scope?.controller;
    const camera = controller?.viewport?.camera;
    if (controller === undefined || camera === undefined) {
      return;
    }
    const zoomIn = delta > 0;
    const last = this.step;
    const step: ZoomStep = {
      zoomIn: zoomIn,
      zoom: (last !== undefined && last.zoomIn === zoomIn ? last.zoom : camera.zoom) + delta,
    };
    this.step = step;
    controller.updateCamera({ zoom: step.zoom }, { mode: CameraTransitionMode.EASE, durationMs: GESTURE_ANIMATION_MS })
      .catch((error: Error) => logError(error.message))
      .finally(() => {
        if (this.step === step) {
          this.step = undefined;
        }
      });
  }
}

/**
 * The units of a `ScaleBar`. Values may be added in later releases; give a
 * `switch` over it a `default` branch.
 */
export enum ScaleBarUnits {
  /** Meters, and kilometers once one fits. */
  METRIC,
  /** Feet, and miles once one fits, as in the United States. */
  FEET_AND_MILES,
  /** Yards, and miles once one fits, as in the United Kingdom. */
  YARDS_AND_MILES,
}

// A unit that a scale bar counts in: its name in ECMA-402, and its length.
interface DistanceUnit {
  name: string;
  meters: number;
}

const METER: DistanceUnit = { name: 'meter', meters: 1 };
const KILOMETER: DistanceUnit = { name: 'kilometer', meters: 1000 };
const FOOT: DistanceUnit = { name: 'foot', meters: 0.3048 };
const YARD: DistanceUnit = { name: 'yard', meters: 0.9144 };
const MILE: DistanceUnit = { name: 'mile', meters: 1609.344 };

// The small and the large unit of `units`.
function unitsOf(units: ScaleBarUnits): DistanceUnit[] {
  switch (units) {
    case ScaleBarUnits.FEET_AND_MILES:
      return [FOOT, MILE];
    case ScaleBarUnits.YARDS_AND_MILES:
      return [YARD, MILE];
    default:
      return [METER, KILOMETER];
  }
}

// A distance that a scale bar shows: its label, and its width in vp.
interface ScaleBarLength {
  label: string;
  width: number;
}

// Formatters of the app's language for each unit, which the scale bar reuses
// every frame.
const formats: Map<string, intl.NumberFormat> = new Map<string, intl.NumberFormat>();

// `value` of `unit`, a unit that ECMA-402 names, such as `kilometer`, in the
// app's language: "100 km", or "100公里" in Chinese.
function formatDistance(value: number, unit: string): string {
  const language = i18n.System.getAppPreferredLanguage();
  const key = `${language} ${unit}`;
  let format = formats.get(key);
  if (format === undefined) {
    format = new intl.NumberFormat(language, {
      style: 'unit',
      unit: unit,
      unitDisplay: 'short',
      maximumFractionDigits: 6,
    });
    formats.set(key, format);
  }
  return format.format(value);
}

// The longest round distance, 1, 2, or 5 times a power of ten, that fits in
// `maxWidth` vp at `metersPerPixel` meters per vp. It counts in the large unit
// once one fits.
function scaleBarLength(metersPerPixel: number, maxWidth: number, units: ScaleBarUnits): ScaleBarLength {
  const meters = metersPerPixel * maxWidth;
  const small = unitsOf(units)[0];
  const large = unitsOf(units)[1];
  const unit = meters >= large.meters ? large : small;
  const value = roundDown(meters / unit.meters);
  return { label: formatDistance(value, unit.name), width: value * unit.meters / metersPerPixel };
}

// The largest of 1, 2, and 5 times a power of ten that's at most `value`, which
// can be below 1, as at high zoom near the poles.
function roundDown(value: number): number {
  if (!(value > 0)) {
    return 0;
  }
  const power = Math.pow(10, Math.floor(Math.log10(value)));
  const digit = value / power;
  return (digit >= 5 ? 5 : digit >= 2 ? 2 : 1) * power;
}

// The regions that measure in feet and miles, and in yards and miles, as
// MapLibre Compose's `regionsUsingFeetAndMiles` and
// `regionsUsingYardsAndMiles` list them.
const FEET_AND_MILES_REGIONS: string[] = [
  // The United States and its unincorporated territories
  'US', 'AS', 'GU', 'MP', 'PR', 'VI',
  // Former United States territories, in the Compact of Free Association
  'FM', 'MH', 'PW',
  // Liberia
  'LR',
];
const YARDS_AND_MILES_REGIONS: string[] = [
  // The United Kingdom, its overseas territories, and its crown dependencies
  'GB', 'AI', 'BM', 'FK', 'GG', 'GI', 'GS', 'IM', 'IO', 'JE', 'KY', 'MS', 'PN', 'SH', 'TC', 'VG',
  // Former British overseas territories and colonies
  'BS', 'BZ', 'GD', 'KN', 'VC',
  // Myanmar
  'MM',
];

// The units of the system's region.
function defaultScaleBarUnits(): ScaleBarUnits {
  const region = i18n.System.getSystemRegion();
  if (FEET_AND_MILES_REGIONS.includes(region)) {
    return ScaleBarUnits.FEET_AND_MILES;
  }
  return YARDS_AND_MILES_REGIONS.includes(region) ? ScaleBarUnits.YARDS_AND_MILES : ScaleBarUnits.METRIC;
}

// A halo in the theme's background color around the scale bar's label, so it
// reads on the map: a shadow to each side, as a stroke.
const HALO: ShadowOptions[] = [[1, 0], [-1, 0], [0, 1], [0, -1]].map((offset: number[]): ShadowOptions => ({
  radius: 1,
  color: $r('sys.color.background_primary'),
  offsetX: offset[0],
  offsetY: offset[1],
}));

/**
 * A scale bar for the distance at the map's center, which updates as the map
 * zooms and pans. Its label is in the app's language. It always shows once
 * the map shows a frame; `DisappearingScaleBar` shows only for a moment after
 * the zoom changes.
 *
 * Place it in a `MaplibreMap`'s overlay. Anywhere else, it logs an error and
 * draws nothing.
 */
@ComponentV2
export struct ScaleBar {
  /**
   * The units. By default, the ones of the system's region: feet and miles in
   * the United States and the regions that share its units, yards and miles
   * in the United Kingdom and the regions that share its units, and metric
   * elsewhere.
   */
  @Param units: ScaleBarUnits = defaultScaleBarUnits();
  /**
   * The longest the bar grows, in vp: finite and above 0. 100 by default.
   * Another value logs an error, and 100 takes its place.
   */
  @Param maxWidth: number = DEFAULT_MAX_WIDTH;
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();

  @Computed
  get barMaxWidth(): number {
    return validMaxWidth('ScaleBar', this.maxWidth);
  }

  @Computed
  get length(): ScaleBarLength | undefined {
    const viewport = this.scope?.controller.viewport;
    return viewport === undefined ? undefined :
      scaleBarLength(viewport.metersPerVpAtLatitude(viewport.camera.center.latitude), this.barMaxWidth, this.units);
  }

  build() {
    Column() {
      Text(this.length?.label ?? '')
        .fontSize(11)
        .fontColor($r('sys.color.font_primary'))
        .textShadow(HALO)
        .maxLines(1)
        .padding({ left: 4, right: 4 })
      Row()
        .width(this.length?.width ?? 0)
        .height(6)
        .border({ width: { left: 2, right: 2, bottom: 2 }, color: $r('sys.color.font_primary') })
        .shadow({ radius: 2, color: $r('sys.color.background_primary') })
    }
    .alignItems(HorizontalAlign.Start)
    .visibility(this.length === undefined ? Visibility.Hidden : Visibility.Visible)
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'ScaleBar');
    })
  }
}

/**
 * A `ScaleBar` that fades in as the map shows its first frame and as the zoom
 * changes, and fades out once the zoom stays the same for
 * `visibilityDurationMs`.
 *
 * Place it in a `MaplibreMap`'s overlay. Anywhere else, it logs an error and
 * draws nothing.
 */
@ComponentV2
export struct DisappearingScaleBar {
  /** The units, which `ScaleBar.units` describes. */
  @Param units: ScaleBarUnits = defaultScaleBarUnits();
  /** The longest the bar grows, which `ScaleBar.maxWidth` describes. */
  @Param maxWidth: number = DEFAULT_MAX_WIDTH;
  /**
   * How long it stays after the zoom last changed, in ms: at least 0, or
   * Infinity to stay. 3000 by default. Another value logs an error, and 3000
   * takes its place.
   */
  @Param visibilityDurationMs: number = 3000;
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();
  @Local shown: boolean = false;
  // When the zoom last changed, and whether a hide is scheduled. The zoom
  // changes every frame of a pinch, so one hide waits for the last change.
  private changedAt: number = 0;
  private hiding: boolean = false;

  @Computed
  get barMaxWidth(): number {
    return validMaxWidth('DisappearingScaleBar', this.maxWidth);
  }

  @Computed
  get durationMs(): number {
    return validDuration('DisappearingScaleBar', this.visibilityDurationMs, 3000);
  }

  @Computed
  get zoom(): number | undefined {
    return this.scope?.controller.viewport?.camera.zoom;
  }

  @Monitor('zoom')
  zoomChanged(): void {
    this.changedAt = Date.now();
    this.shown = this.zoom !== undefined;
    if (!this.hiding) {
      this.hideLater(this.durationMs);
    }
  }

  private hideLater(delayMs: number): void {
    this.hiding = delayMs < Infinity;
    hideAfter(this.getUIContext(), delayMs, () => {
      const left = this.changedAt + this.durationMs - Date.now();
      if (left > 0) {
        this.hideLater(left);
      } else {
        this.hiding = false;
        this.shown = false;
      }
    });
  }

  build() {
    Stack() {
      if (this.shown) {
        ScaleBar({ units: this.units, maxWidth: this.barMaxWidth })
          .transition(TransitionEffect.OPACITY.animation({ duration: FADE_MS }))
      }
    }
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'DisappearingScaleBar');
    })
  }
}

/**
 * Attribution HTML as text: 12 vp, in the theme's secondary font color, with
 * underlined links that open in the browser. It shows the attributions that
 * `MapController.attributions` and `MapSnapshot.attributions` give, which the
 * sources' terms usually require. It needs no map, so it works anywhere.
 *
 * ```ets
 * AttributionText({ attributions: this.controller.attributions })
 * ```
 */
@ComponentV2
export struct AttributionText {
  /**
   * The attributions, each an HTML fragment. Empty by default, which shows no
   * text. A list with the same strings as the last changes nothing.
   */
  @Param attributions: string[] = [];
  private text: TextController = new TextController();
  // Whether the text has appeared, so the controller reaches it.
  private appeared: boolean = false;
  // The HTML that the text shows, or is converting to show.
  private html: string | undefined = undefined;

  @Monitor('attributions')
  attributionsChanged(): void {
    this.showText();
  }

  build() {
    Text(undefined, { controller: this.text })
      .onAppear(() => {
        this.appeared = true;
        this.showText();
      })
  }

  // StyledString converts the HTML with its links, which open in the browser.
  private showText(): void {
    const html = this.attributions.join('  ');
    if (!this.appeared || html === this.html) {
      return;
    }
    this.html = html;
    // fromHtml() rejects empty HTML, so clear the text directly.
    if (html === '') {
      this.text.setStyledString(new StyledString(''));
      return;
    }
    StyledString.fromHtml(html).then((converted: StyledString) => {
      if (html !== this.html) {
        return;
      }
      const text = new MutableStyledString('');
      text.appendStyledString(converted);
      if (text.length === 0) {
        this.text.setStyledString(text);
        return;
      }
      text.setStyle({
        start: 0,
        length: text.length,
        styledKey: StyledStringKey.FONT,
        styledValue: new TextStyle({ fontSize: LengthMetrics.vp(12), fontColor: $r('sys.color.font_secondary') }),
      });
      for (const link of text.getStyles(0, text.length, StyledStringKey.URL)) {
        text.setStyle({
          start: link.start,
          length: link.length,
          styledKey: StyledStringKey.DECORATION,
          styledValue: new DecorationStyle({ type: TextDecorationType.Underline }),
        });
      }
      this.text.setStyledString(text);
    }).catch((error: Error) => logError(error.message));
  }
}

/**
 * The attribution of the map's sources, which the sources' terms usually
 * require, behind a button. It starts expanded; a tap on the button folds or
 * unfolds it, and it folds as the user starts a gesture. It shows the
 * attribution as `AttributionText` does. It draws nothing while the style has
 * no attribution.
 *
 * Place it in a `MaplibreMap`'s overlay. Anywhere else, it logs an error and
 * draws nothing.
 */
@ComponentV2
export struct AttributionButton {
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();
  @Local expanded: boolean = true;

  // ets-loader's webpack build warns that this watches no state variable. Its
  // checker types every member as `any` there, so it can't follow a path
  // through the scope, but the monitor runs as the value changes. It folds as
  // a gesture starts, not as one goes on, so a tap that unfolds it during a
  // gesture keeps it open.
  @Monitor('scope.gesturing')
  gesturingChanged(): void {
    if (this.scope?.gesturing === true) {
      this.expanded = false;
    }
  }

  @Computed
  get attributions(): string[] {
    return this.scope?.controller.attributions ?? [];
  }

  build() {
    Stack() {
      if (this.attributions.length > 0) {
        Flex({ alignItems: ItemAlign.Center }) {
          if (this.expanded) {
            AttributionText({ attributions: this.attributions })
              .flexShrink(1)
              .padding({ left: 12, top: 6, bottom: 6 })
          }
          Button({ type: ButtonType.Circle }) {
            Text('i')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.icon_secondary'))
              .textAlign(TextAlign.Center)
              .width(20)
              .height(20)
              .borderRadius(10)
              .border({ width: 1.5, color: $r('sys.color.icon_secondary') })
          }
          .width(32)
          .height(32)
          .flexShrink(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.maplibre_attribution'))
          .onClick(() => {
            this.expanded = !this.expanded;
          })
        }
        .width('auto')
        .padding(4)
        .borderRadius(20)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .shadow(ShadowStyle.OUTER_DEFAULT_XS)
      }
    }
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'AttributionButton');
    })
  }
}

// The address that `MaplibreLogo` opens when tapped.
const MAPLIBRE_URL = 'https://maplibre.org/';
// The logo's size in vp.
export const LOGO_WIDTH = 88;
const LOGO_HEIGHT = 23;

/**
 * The MapLibre wordmark, 88 by 23 vp, with a shadow that reads on light and
 * dark maps. A tap opens maplibre.org in the browser. It needs no map, so it
 * works anywhere.
 */
@ComponentV2
export struct MaplibreLogo {
  build() {
    Image($r('app.media.maplibre_logo'))
      .width(LOGO_WIDTH)
      .height(LOGO_HEIGHT)
      .draggable(false)
      .accessibilityText($r('app.string.maplibre_logo'))
      .onClick(() => {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        context.openLink(MAPLIBRE_URL).catch((error: Error) => logError(error.message));
      })
  }
}
