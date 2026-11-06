// The font scale that fp() sizes text by, as MapLibre Compose's sp does: a
// global state property that the content reconciler sets on each style.

// The global state property that fp() reads.
export const FONT_SCALE_STATE = 'maplibre-arkui:font-scale';

// How many vp an fp is in `context`, which is how ArkUI scales text by the
// user's font size setting.
export function fontScaleOf(context: UIContext): number {
  return context.fp2px(1) / context.vp2px(1);
}
