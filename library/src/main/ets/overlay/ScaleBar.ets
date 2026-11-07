import i18n from '@ohos.i18n';
import intl from '@ohos.intl';

import { controlKey, findScope, MapScope } from '../map/internal/MapScope';
import { logError } from '../runtime/internal/Log';
import { FADE_MS, hideAfter, validDuration } from './internal/Disappearing';

const DEFAULT_MAX_WIDTH = 100;

// A control's `maxWidth`, or the default with an error in the log when it
// isn't finite and above 0.
function validMaxWidth(control: string, maxWidth: number): number {
  if (maxWidth > 0 && maxWidth < Infinity) {
    return maxWidth;
  }
  logError(`${control} maxWidth must be finite and above 0, not ${maxWidth}; using ${DEFAULT_MAX_WIDTH}`);
  return DEFAULT_MAX_WIDTH;
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
