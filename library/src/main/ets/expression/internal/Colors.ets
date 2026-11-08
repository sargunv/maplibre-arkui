// Turns an ArkUI ResourceColor into a color that the style spec takes. ArkUI
// and CSS read a hex color's alpha from opposite ends (`#AARRGGBB` against
// `#RRGGBBAA`), so no color goes to the style as the app wrote it.

import { ColorMetrics } from '@ohos.arkui.node';

// A color that ArkUI resolved: channels from 0 to 255, and alpha from 0 to 1.
export class StyleColor {
  readonly red: number;
  readonly green: number;
  readonly blue: number;
  readonly alpha: number;

  constructor(red: number, green: number, blue: number, alpha: number) {
    this.red = red;
    this.green = green;
    this.blue = blue;
    this.alpha = alpha;
  }

  // The style spec's `rgba()`, with the alpha times `opacity`.
  rgba(opacity: number = 1): string {
    return `rgba(${this.red}, ${this.green}, ${this.blue}, ${this.alpha * opacity})`;
  }
}

// Resolves `color` as ArkUI draws it now, so a resource takes the current color
// mode's value. Throws an Error with the color when ArkUI can't resolve it.
export function resolveColor(color: ResourceColor): StyleColor {
  let metrics: ColorMetrics;
  try {
    metrics = ColorMetrics.resourceColor(color);
  } catch (error) {
    throw new Error(`The color ${JSON.stringify(color)} can't be resolved: ${(error as Error).message}`);
  }
  // ColorMetrics reports alpha from 0 to 255.
  return new StyleColor(metrics.red, metrics.green, metrics.blue, metrics.alpha / 255);
}
