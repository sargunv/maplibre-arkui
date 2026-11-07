// ArkUI paddings as four sides in vp, as the map's camera padding and its
// viewport insets take them. Each side becomes a LengthMetrics, which one
// switch on its unit converts to vp. The FFI map's padding is the insets plus
// the app's camera padding; the controller reads and takes the app's alone,
// so the insets never show in a camera that the app reads or saves.

import { LengthMetrics, LengthUnit } from '@ohos.arkui.node';
import i18n from '@ohos.i18n';

// Four sides in vp, which pass to FFI as its EdgeInsets.
export interface Insets {
  top: number;
  left: number;
  bottom: number;
  right: number;
}

export const NO_INSETS: Insets = { top: 0, left: 0, bottom: 0, right: 0 };

export function addInsets(a: Insets, b: Insets): Insets {
  return { top: a.top + b.top, left: a.left + b.left, bottom: a.bottom + b.bottom, right: a.right + b.right };
}

export function sameInsets(a: Insets, b: Insets): boolean {
  return a.top === b.top && a.left === b.left && a.bottom === b.bottom && a.right === b.right;
}

// Whether the app's language reads right to left, so start is right. A
// `.direction()` on an ancestor doesn't change it.
export function isRtl(): boolean {
  return i18n.isRTL(i18n.System.getAppPreferredLanguage());
}

// How many vp a length of each unit is, besides vp. Without `lpx`, an lpx
// length is invalid.
export interface LengthScales {
  px: (px: number) => number;
  fp: (fp: number) => number;
  lpx?: (lpx: number) => number;
}

// The scales of a UI context.
export function contextScales(context: UIContext): LengthScales {
  return {
    px: (px: number) => context.px2vp(px),
    fp: (fp: number) => context.px2vp(context.fp2px(fp)),
    lpx: (lpx: number) => context.px2vp(context.lpx2px(lpx)),
  };
}

type Side = Length | LengthMetrics | undefined;

// A padding's sides as LengthMetrics, left and right, each checked to be
// finite and at least 0, in a unit other than a percentage.
export interface PaddingMetrics {
  top: LengthMetrics;
  left: LengthMetrics;
  bottom: LengthMetrics;
  right: LengthMetrics;
}

// Checks each side of `padding`, which `what` names in the error, and throws
// for the first that's invalid.
export function checkPadding(padding: Padding | LocalizedPadding, what: string): PaddingMetrics {
  const sides = physicalSides(padding);
  return {
    top: checkSide(sides[0], what),
    left: checkSide(sides[1], what),
    bottom: checkSide(sides[2], what),
    right: checkSide(sides[3], what),
  };
}

// `padding` in vp. Throws for an lpx side without `scales.lpx`.
export function paddingInVp(padding: PaddingMetrics, scales: LengthScales): Insets {
  return {
    top: lengthInVp(padding.top, scales),
    left: lengthInVp(padding.left, scales),
    bottom: lengthInVp(padding.bottom, scales),
    right: lengthInVp(padding.right, scales),
  };
}

// `padding` in vp, with each invalid side reported to `report` and taken as 0.
export function paddingInVpOrZero(padding: Padding | LocalizedPadding, what: string, scales: LengthScales,
  report: (error: Error) => void): Insets {
  const sides = physicalSides(padding);
  const inVp = (side: Side): number => {
    try {
      return lengthInVp(checkSide(side, what), scales);
    } catch (error) {
      report(error as Error);
      return 0;
    }
  };
  return { top: inVp(sides[0]), left: inVp(sides[1]), bottom: inVp(sides[2]), right: inVp(sides[3]) };
}

// The top, left, bottom, and right of `padding`, with a LocalizedPadding's
// start and end on the sides that the app's language puts them. Strict ArkTS
// has no `in`, so a LocalizedPadding is one with a LengthMetrics side.
function physicalSides(padding: Padding | LocalizedPadding): Side[] {
  const localized = padding as LocalizedPadding;
  if (localized.top instanceof LengthMetrics || localized.bottom instanceof LengthMetrics ||
    localized.start instanceof LengthMetrics || localized.end instanceof LengthMetrics) {
    const rtl = isRtl();
    return [localized.top, rtl ? localized.end : localized.start, localized.bottom,
      rtl ? localized.start : localized.end];
  }
  const physical = padding as Padding;
  return [physical.top, physical.left, physical.bottom, physical.right];
}

// A length as ArkUI writes one, such as 12, '12px', or '12fp'. A number, or a
// string without a unit, is in vp.
const LENGTH = /^([-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?)(px|vp|fp|lpx|%)?$/i;

function checkSide(side: Side, what: string): LengthMetrics {
  let metrics: LengthMetrics | undefined = undefined;
  if (side === undefined) {
    metrics = LengthMetrics.vp(0);
  } else if (typeof side === 'number') {
    metrics = LengthMetrics.vp(side);
  } else if (typeof side === 'string') {
    metrics = parseLength(side);
  } else if (side instanceof LengthMetrics) {
    metrics = side;
  } else {
    try {
      metrics = LengthMetrics.resource(side as Resource);
    } catch (error) {
      metrics = undefined;
    }
  }
  if (metrics === undefined || !Number.isFinite(metrics.value) || metrics.value < 0 ||
    metrics.unit === LengthUnit.PERCENT) {
    throw new Error(`Each side of ${what} must be a finite length of at least 0, not a percentage: ` +
      describeSide(side));
  }
  return metrics;
}

// A side as the app wrote it. JSON would write NaN as null.
function describeSide(side: Side): string {
  if (side instanceof LengthMetrics) {
    return `${side.value} in LengthUnit ${side.unit}`;
  }
  return typeof side === 'number' || typeof side === 'string' ? `${side}` : JSON.stringify(side);
}

function parseLength(text: string): LengthMetrics | undefined {
  const match = LENGTH.exec(text.trim());
  if (match === null) {
    return undefined;
  }
  const value = Number(match[1]);
  switch ((match[2] ?? 'vp').toLowerCase()) {
    case 'px':
      return LengthMetrics.px(value);
    case 'fp':
      return LengthMetrics.fp(value);
    case 'lpx':
      return LengthMetrics.lpx(value);
    case '%':
      return LengthMetrics.percent(value);
    default:
      return LengthMetrics.vp(value);
  }
}

function lengthInVp(length: LengthMetrics, scales: LengthScales): number {
  switch (length.unit) {
    case LengthUnit.VP:
      return length.value;
    case LengthUnit.PX:
      return scales.px(length.value);
    case LengthUnit.FP:
      return scales.fp(length.value);
    case LengthUnit.LPX:
      if (scales.lpx !== undefined) {
        return scales.lpx(length.value);
      }
      throw new Error(`An lpx length needs a UI context: ${length.value}lpx`);
    default:
      throw new Error(`A length must be in vp, px, fp, or lpx: ${JSON.stringify(length)}`);
  }
}
