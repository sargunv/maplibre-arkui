// What DisappearingCompassButton and DisappearingScaleBar share: their fade,
// and when they hide.

import { afterDelay } from '../../map/internal/MapScope';
import { logError } from '../../runtime/internal/Log';

export const FADE_MS = 200;

// A control's `visibilityDurationMs`, or `fallback` with an error in the log
// when it isn't at least 0.
export function validDuration(control: string, durationMs: number, fallback: number): number {
  if (durationMs >= 0) {
    return durationMs;
  }
  logError(`${control} visibilityDurationMs must be at least 0, not ${durationMs}; using ${fallback}`);
  return fallback;
}

// Runs `hide` in the first frame after `durationMs`, unless that's Infinity.
export function hideAfter(context: UIContext, durationMs: number, hide: () => void): void {
  if (durationMs < Infinity) {
    afterDelay(context, durationMs, hide);
  }
}
