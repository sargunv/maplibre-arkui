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

/** How the map draws a `StyleImageSource`. */
export interface StyleImageOptions {
  /**
   * Whether to draw the image as a signed distance field from its alpha, so a
   * layer can recolor it with `icon-color` and give it a halo. Suits
   * single-color icons. False by default.
   */
  drawAsSdf?: boolean;
}

/** An image for an ID that the style lacks. */
export interface ResolvedStyleImage extends StyleImageOptions {
  /** The image. */
  image: StyleImageSource;
}
