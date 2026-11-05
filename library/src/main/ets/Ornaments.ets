// The controls that a MapLibreMap can show over itself, which apps can also
// place themselves. Each takes the controller of the map it controls, and
// reads the frame on screen through it, so it follows animations.

import { CameraUpdateMode } from '@maplibre/native-ffi';
import i18n from '@ohos.i18n';
import { LengthMetrics } from '@ohos.arkui.node';

import { MapController } from './MapController';

const ORNAMENT_SIZE = 40;

/**
 * A compass that points north, and turns the map north and flat when tapped.
 * It shows only while the map is rotated or tilted, unless `alwaysShown`.
 */
@ComponentV2
export struct MapCompass {
  @Require @Param controller: MapController;
  /** Whether it shows while the map faces north and looks straight down. */
  @Param alwaysShown: boolean = false;

  @Computed
  get bearing(): number {
    return this.controller.frameCamera?.bearing ?? 0;
  }

  @Computed
  get shown(): boolean {
    const camera = this.controller.frameCamera;
    if (camera === undefined) {
      return false;
    }
    // How far the map turns from north, from 0 to 180 degrees.
    const bearing = Math.abs((camera.bearing % 360 + 540) % 360 - 180);
    return this.alwaysShown || bearing > 0.5 || camera.pitch > 0.5;
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
    .width(ORNAMENT_SIZE)
    .height(ORNAMENT_SIZE)
    .borderRadius(ORNAMENT_SIZE / 2)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .shadow(ShadowStyle.OUTER_DEFAULT_XS)
    .opacity(this.shown ? 1 : 0)
    .animation({ duration: 200 })
    .hitTestBehavior(this.shown ? HitTestMode.Default : HitTestMode.None)
    .accessibilityText('Compass')
    .accessibilityLevel(this.shown ? 'auto' : 'no-hide-descendants')
    .onClick(() => {
      this.controller.updateCamera({
        mode: CameraUpdateMode.ease,
        camera: { bearing: 0, pitch: 0 },
        animation: { durationMs: 300 },
      }).catch((error: Error) => console.error(`MapLibre: ${error.message}`));
    })
  }
}

/** Buttons that zoom the map in and out by one level. */
@ComponentV2
export struct MapZoomButtons {
  @Require @Param controller: MapController;

  build() {
    Column() {
      this.zoomButton($r('sys.media.ohos_ic_public_add'), 'Zoom in', 1)
      Divider().width(ORNAMENT_SIZE / 2)
      this.zoomButton($r('sys.media.ohos_ic_public_minus'), 'Zoom out', -1)
    }
    .borderRadius(ORNAMENT_SIZE / 2)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .shadow(ShadowStyle.OUTER_DEFAULT_XS)
  }

  @Builder
  zoomButton(icon: Resource, label: string, delta: number) {
    Button({ type: ButtonType.Circle }) {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor($r('sys.color.icon_primary'))
    }
    .width(ORNAMENT_SIZE)
    .height(ORNAMENT_SIZE)
    .backgroundColor(Color.Transparent)
    .accessibilityText(label)
    .onClick(() => this.zoomBy(delta))
  }

  private zoomBy(delta: number): void {
    const camera = this.controller.getCamera();
    if (camera === undefined) {
      return;
    }
    this.controller.updateCamera({
      mode: CameraUpdateMode.ease,
      camera: { zoom: camera.zoom + delta },
      animation: { durationMs: 300 },
    }).catch((error: Error) => console.error(`MapLibre: ${error.message}`));
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

// The longest round distance, 1, 2, or 5 times a power of ten, that fits in
// `maxWidth` vp at `metersPerPixel` meters per vp. It counts in kilometers or
// miles once one fits.
function scaleBarLength(metersPerPixel: number, maxWidth: number, units: ScaleBarUnits): ScaleBarLength {
  const meters = metersPerPixel * maxWidth;
  const small = units === ScaleBarUnits.metric ? 1 : 0.3048;
  const large = units === ScaleBarUnits.metric ? 1000 : 1609.344;
  const unit = meters >= large ? large : small;
  const value = roundDown(meters / unit);
  const symbol = units === ScaleBarUnits.metric ? (unit === large ? 'km' : 'm') : (unit === large ? 'mi' : 'ft');
  return { label: `${value} ${symbol}`, width: value * unit / metersPerPixel };
}

// The largest of 1, 2, and 5 times a power of ten that's at most `value`, and
// at least 1.
function roundDown(value: number): number {
  const power = Math.pow(10, Math.floor(Math.log10(Math.max(value, 1))));
  const digit = value / power;
  return (digit >= 5 ? 5 : digit >= 2 ? 2 : 1) * power;
}

// Feet and miles in the United States and the countries that use its units.
const IMPERIAL_REGIONS: string[] = ['US', 'AS', 'GU', 'MP', 'PR', 'VI', 'UM', 'LR', 'MM'];

// The units of the system's region: imperial in the US, Liberia, and Myanmar.
function defaultScaleBarUnits(): ScaleBarUnits {
  return IMPERIAL_REGIONS.includes(i18n.System.getSystemRegion()) ? ScaleBarUnits.imperial : ScaleBarUnits.metric;
}

/**
 * A scale bar for the distance at the map's center, which updates as the map
 * zooms and pans. It draws in fixed colors that read on light and dark maps.
 */
@ComponentV2
export struct MapScaleBar {
  @Require @Param controller: MapController;
  @Param units: ScaleBarUnits = defaultScaleBarUnits();
  /** The longest the bar grows, in vp. */
  @Param maxWidth: number = 100;

  @Computed
  get length(): ScaleBarLength | undefined {
    const camera = this.controller.frameCamera;
    const metersPerPixel = camera === undefined ? undefined :
      this.controller.metersPerPixelAtLatitude(camera.center.latitude);
    return metersPerPixel === undefined ? undefined : scaleBarLength(metersPerPixel, this.maxWidth, this.units);
  }

  build() {
    Column() {
      Text(this.length?.label ?? '')
        .fontSize(11)
        .fontColor('#bf000000')
        .textShadow({ radius: 2, color: Color.White })
        .maxLines(1)
        .padding({ left: 4, right: 4 })
      Row()
        .width(this.length?.width ?? 0)
        .height(6)
        .border({ width: { left: 2, right: 2, bottom: 2 }, color: '#bf000000' })
        .shadow({ radius: 2, color: Color.White })
    }
    .alignItems(HorizontalAlign.Start)
    .visibility(this.length === undefined ? Visibility.Hidden : Visibility.Visible)
  }
}

/**
 * The attribution of the map's sources, which the sources' terms usually
 * require. It starts expanded, and a tap on its button folds it away. Its
 * links open in the browser. It draws nothing while the style has no
 * attribution.
 */
@ComponentV2
export struct MapAttribution {
  @Require @Param controller: MapController;
  @Local expanded: boolean = true;
  private text: TextController = new TextController();

  @Monitor('controller.attributions')
  attributionsChanged(): void {
    this.showText();
  }

  build() {
    if (this.controller.attributions.length > 0) {
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
        .accessibilityText('Attribution')
        .onClick(() => {
          this.expanded = !this.expanded;
        })
      }
      .width('auto')
      .padding(4)
      .borderRadius(20)
      .backgroundColor($r('sys.color.comp_background_primary'))
    }
  }

  // The attributions are HTML, which StyledString converts with their links.
  private showText(): void {
    const attributions = this.controller.attributions;
    if (attributions.length === 0) {
      return;
    }
    StyledString.fromHtml(attributions.join('  ')).then((html: StyledString) => {
      if (attributions !== this.controller.attributions) {
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
    }).catch((error: Error) => console.error(`MapLibre: ${error.message}`));
  }
}
