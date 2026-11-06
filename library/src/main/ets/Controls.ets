// The controls that a MapLibreMap's overlay presets draw, which apps can also
// place in the overlay themselves. Each finds its map through the overlay's
// MapScope, and reads the frame on screen through the map's controller, so it
// follows animations. They draw with the system's colors, so they follow dark
// mode, and label themselves with the library's localized strings.

import { CameraUpdateMode } from '@maplibre/native-ffi';
import common from '@ohos.app.ability.common';
import { LengthMetrics } from '@ohos.arkui.node';
import i18n from '@ohos.i18n';
import intl from '@ohos.intl';

import { GESTURE_ANIMATION_MS } from './gestures';
import { logError } from './log';
import { afterDelay, controlKey, findScope, MapScope } from './scope';

const BUTTON_SIZE = 40;
const FADE_MS = 200;

// How far the camera turns from north, from 0 to 180 degrees.
function turnFromNorth(bearing: number): number {
  return Math.abs((bearing % 360 + 540) % 360 - 180);
}

/**
 * A compass that points north, and turns the map north and flat when tapped.
 * It always shows; `MapDisappearingCompassButton` shows only while the map is
 * rotated or tilted.
 */
@ComponentV2
export struct MapCompassButton {
  @Local scope: MapScope = new MapScope();
  private readonly nodeId: string = controlKey();

  @Computed
  get bearing(): number {
    return this.scope.controller.frameCamera?.bearing ?? 0;
  }

  build() {
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
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId);
    })
    .onClick(() => {
      this.scope.controller.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { bearing: 0, pitch: 0 },
        animation: { durationMs: GESTURE_ANIMATION_MS },
      }).catch((error: Error) => logError(error.message));
    })
  }
}

/**
 * A `MapCompassButton` that fades in while the map is rotated or tilted, and
 * fades out once the map faces north and looks straight down again.
 */
@ComponentV2
export struct MapDisappearingCompassButton {
  @Local scope: MapScope = new MapScope();
  private readonly nodeId: string = controlKey();
  /** How long it stays after the map turns back north and flat, in ms. */
  @Param visibilityDurationMs: number = 1000;
  @Local shown: boolean = false;
  // Counts the changes of `turned`, so a hide that a later turn overtook
  // doesn't run.
  private turns: number = 0;

  @Computed
  get turned(): boolean {
    const camera = this.scope.controller.frameCamera;
    return camera !== undefined && (turnFromNorth(camera.bearing) > 0.5 || camera.pitch > 0.5);
  }

  @Monitor('turned')
  turnedChanged(): void {
    const turn = ++this.turns;
    if (this.turned) {
      this.shown = true;
      return;
    }
    afterDelay(this.getUIContext(), this.visibilityDurationMs, () => {
      if (turn === this.turns) {
        this.shown = false;
      }
    });
  }

  build() {
    Stack() {
      if (this.shown) {
        MapCompassButton()
          .transition(TransitionEffect.OPACITY.animation({ duration: FADE_MS }))
      }
    }
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId);
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
 */
@ComponentV2
export struct MapZoomButtons {
  @Local scope: MapScope = new MapScope();
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
    Column() {
      this.zoomButton($r('sys.media.ohos_ic_public_add'), $r('app.string.maplibre_zoom_in'), 1)
      Divider().width(BUTTON_SIZE / 2)
      this.zoomButton($r('sys.media.ohos_ic_public_minus'), $r('app.string.maplibre_zoom_out'), -1)
    }
    .borderRadius(BUTTON_SIZE / 2)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .shadow(ShadowStyle.OUTER_DEFAULT_XS)
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId);
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
    const controller = this.scope.controller;
    const camera = controller.getCamera();
    if (camera === undefined) {
      return;
    }
    const zoomIn = delta > 0;
    const last = this.step;
    const step: ZoomStep = {
      zoomIn: zoomIn,
      zoom: (last !== undefined && last.zoomIn === zoomIn ? last.zoom : camera.zoom) + delta,
    };
    this.step = step;
    controller.updateCamera({
      mode: CameraUpdateMode.ease,
      camera: { zoom: step.zoom },
      animation: { durationMs: GESTURE_ANIMATION_MS },
    }).catch((error: Error) => logError(error.message)).finally(() => {
      if (this.step === step) {
        this.step = undefined;
      }
    });
  }
}

/** The units of a `MapScaleBar`. */
export enum ScaleBarUnits {
  /** Meters and kilometers. */
  metric,
  /** Feet and miles. */
  imperial,
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
// `maxWidth` vp at `metersPerPixel` meters per vp. It counts in kilometers or
// miles once one fits.
function scaleBarLength(metersPerPixel: number, maxWidth: number, units: ScaleBarUnits): ScaleBarLength {
  const meters = metersPerPixel * maxWidth;
  const metric = units === ScaleBarUnits.metric;
  const small = metric ? 1 : 0.3048;
  const large = metric ? 1000 : 1609.344;
  const unit = meters >= large ? large : small;
  const value = roundDown(meters / unit);
  const name = metric ? (unit === large ? 'kilometer' : 'meter') : (unit === large ? 'mile' : 'foot');
  return { label: formatDistance(value, name), width: value * unit / metersPerPixel };
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

// Feet and miles in the United States and the countries that use its units.
const IMPERIAL_REGIONS: string[] = ['US', 'AS', 'GU', 'MP', 'PR', 'VI', 'UM', 'LR', 'MM'];

// The units of the system's region: imperial in the US, Liberia, and Myanmar.
function defaultScaleBarUnits(): ScaleBarUnits {
  return IMPERIAL_REGIONS.includes(i18n.System.getSystemRegion()) ? ScaleBarUnits.imperial : ScaleBarUnits.metric;
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
 * the map shows a frame; `MapDisappearingScaleBar` shows only for a moment
 * after the zoom changes.
 */
@ComponentV2
export struct MapScaleBar {
  @Local scope: MapScope = new MapScope();
  private readonly nodeId: string = controlKey();
  /** The units: by default, imperial in the regions that use them, and metric elsewhere. */
  @Param units: ScaleBarUnits = defaultScaleBarUnits();
  /** The longest the bar grows, in vp. */
  @Param maxWidth: number = 100;

  @Computed
  get length(): ScaleBarLength | undefined {
    const controller = this.scope.controller;
    const camera = controller.frameCamera;
    const metersPerPixel = camera === undefined ? undefined :
      controller.metersPerPixelAtLatitude(camera.center.latitude);
    return metersPerPixel === undefined ? undefined : scaleBarLength(metersPerPixel, this.maxWidth, this.units);
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
      this.scope = findScope(this.getUIContext(), this.nodeId);
    })
  }
}

/**
 * A `MapScaleBar` that fades in as the zoom changes, and fades out once it
 * stays the same for `visibilityDurationMs`.
 */
@ComponentV2
export struct MapDisappearingScaleBar {
  @Local scope: MapScope = new MapScope();
  private readonly nodeId: string = controlKey();
  /** The units: by default, imperial in the regions that use them, and metric elsewhere. */
  @Param units: ScaleBarUnits = defaultScaleBarUnits();
  /** The longest the bar grows, in vp. */
  @Param maxWidth: number = 100;
  /** How long it stays after the zoom last changed, in ms. */
  @Param visibilityDurationMs: number = 3000;
  @Local shown: boolean = false;
  // When the zoom last changed, and whether a hide is scheduled. The zoom
  // changes every frame of a pinch, so one hide waits for the last change.
  private changedAt: number = 0;
  private hiding: boolean = false;

  @Computed
  get zoom(): number | undefined {
    return this.scope.controller.frameCamera?.zoom;
  }

  @Monitor('zoom')
  zoomChanged(): void {
    this.changedAt = Date.now();
    this.shown = this.zoom !== undefined;
    if (!this.hiding) {
      this.hiding = true;
      this.hideAfter(this.visibilityDurationMs);
    }
  }

  private hideAfter(delayMs: number): void {
    afterDelay(this.getUIContext(), delayMs, () => {
      const left = this.changedAt + this.visibilityDurationMs - Date.now();
      if (left > 0) {
        this.hideAfter(left);
      } else {
        this.hiding = false;
        this.shown = false;
      }
    });
  }

  build() {
    Stack() {
      if (this.shown) {
        MapScaleBar({ units: this.units, maxWidth: this.maxWidth })
          .transition(TransitionEffect.OPACITY.animation({ duration: FADE_MS }))
      }
    }
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId);
    })
  }
}

/**
 * The attribution of the map's sources, which the sources' terms usually
 * require, behind a button. It starts expanded; a tap on the button folds or
 * unfolds it, and it folds as the user starts a gesture. Its links open in
 * the browser. It draws nothing while the style has no attribution.
 */
@ComponentV2
export struct MapAttributionButton {
  @Local scope: MapScope = new MapScope();
  private readonly nodeId: string = controlKey();
  @Local expanded: boolean = true;
  private text: TextController = new TextController();

  // ets-loader's webpack build warns that these watch no state variable. Its
  // checker types every member as `any` there, so it can't follow a path
  // through the scope, but the monitors run as the values change.
  @Monitor('scope.controller.attributions')
  attributionsChanged(): void {
    this.showText();
  }

  // It folds as a gesture starts, not as one goes on, so a tap that unfolds
  // it during a gesture keeps it open.
  @Monitor('scope.gesturing')
  gesturingChanged(): void {
    if (this.scope.gesturing) {
      this.expanded = false;
    }
  }

  build() {
    Stack() {
      if (this.scope.controller.attributions.length > 0) {
        Flex({ alignItems: ItemAlign.Center }) {
          if (this.expanded) {
            Text(undefined, { controller: this.text })
              .flexShrink(1)
              .padding({ left: 12, top: 6, bottom: 6 })
              .onAppear(() => this.showText())
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
      this.scope = findScope(this.getUIContext(), this.nodeId);
    })
  }

  // The attributions are HTML, which StyledString converts with their links.
  private showText(): void {
    const attributions = this.scope.controller.attributions;
    if (attributions.length === 0) {
      return;
    }
    StyledString.fromHtml(attributions.join('  ')).then((html: StyledString) => {
      if (attributions !== this.scope.controller.attributions) {
        return;
      }
      const text = new MutableStyledString('');
      text.appendStyledString(html);
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

/** The address that `MapLibreLogo` opens when tapped. */
const MAPLIBRE_URL = 'https://maplibre.org/';
// The logo's size in vp.
export const LOGO_WIDTH = 88;
const LOGO_HEIGHT = 23;

/**
 * The MapLibre wordmark, 88 by 23 vp, with a shadow that reads on light and
 * dark maps. A tap opens maplibre.org in the browser.
 */
@ComponentV2
export struct MapLibreLogo {
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
