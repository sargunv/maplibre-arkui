import { DrawableDescriptor } from '@ohos.arkui.drawableDescriptor';
import image from '@ohos.multimedia.image';

/**
 * An image for icons and patterns. Types may be added in later releases.
 *
 * A pixel map must be in `RGBA_8888` or `BGRA_8888` format, and draws one of
 * its pixels per pixel of the screen, or of a snapshot. A resource or drawable
 * descriptor draws at the size that ArkUI's `Image` gives it, and a resource
 * takes the media of the current color mode. Drawing a resource or drawable
 * descriptor needs a UI context, which a `MaplibreMap` has and
 * `renderSnapshot()` has only with its `uiContext`.
 */
export type StyleImageSource = image.PixelMap | Resource | DrawableDescriptor;

/**
 * How a stretchable image fits the text of a symbol whose `icon-text-fit`
 * isn't `'none'`. Values may be added in later releases; give a `switch` over
 * it a `default` branch.
 */
export enum StyleImageTextFit {
  /** Stretches or shrinks to the text. */
  STRETCH_OR_SHRINK,
  /** Stretches to the text, but doesn't shrink below the image's size. */
  STRETCH_ONLY,
  /** Keeps the image's aspect ratio while it fits the text. */
  PROPORTIONAL,
}

/** A range of an image, in vp from its left or top edge. */
export interface StretchRange {
  /** Where the range starts. */
  from: number;
  /** Where the range ends, at least `from`. */
  to: number;
}

/**
 * The parts of an image that stretch, and the part that holds the text, when a
 * symbol layer fits the image to its text with `icon-text-fit`.
 */
export interface StyleImageStretch {
  /**
   * The edges that keep their size, as for ArkUI's `Image.resizable()`; the
   * middle stretches. Give either `slice` or `x` and `y`.
   */
  slice?: EdgeWidths;
  /** The columns that stretch, in increasing order without overlap. None by default. */
  x?: StretchRange[];
  /** The rows that stretch, in increasing order without overlap. None by default. */
  y?: StretchRange[];
  /** The space between the image's edges and its text. The whole image holds the text by default. */
  content?: Padding | LocalizedPadding;
  /** How the image fits the text's width. `StyleImageTextFit.STRETCH_OR_SHRINK` by default. */
  textFitWidth?: StyleImageTextFit;
  /** How the image fits the text's height. `StyleImageTextFit.STRETCH_OR_SHRINK` by default. */
  textFitHeight?: StyleImageTextFit;
}

/**
 * How the map draws a `StyleImageSource`.
 *
 * Lengths must be finite and at least 0, and not percentages. A stretch range
 * or content box that doesn't fit inside the image fails the image: the map
 * leaves it out and reports the failure.
 */
export interface StyleImageOptions {
  /**
   * The size of the image, in vp. The size that ArkUI's `Image` gives it by
   * default. The image scales to the size, without keeping its aspect ratio.
   */
  size?: Size;
  /**
   * Whether the image is already a signed distance field, which a layer
   * recolors with `icon-color`. False by default.
   */
  sdf?: boolean;
  /**
   * Whether to make a signed distance field from the image's alpha, so a layer
   * can recolor it with `icon-color` and give it a halo. Suits single-color
   * icons. False by default; can't be true along with `sdf`.
   */
  drawAsSdf?: boolean;
  /** How the image stretches to fit text. It doesn't stretch by default. */
  stretch?: StyleImageStretch;
}

/** An image for an ID that the style lacks. */
export interface ResolvedStyleImage extends StyleImageOptions {
  /** The image. */
  image: StyleImageSource;
}
