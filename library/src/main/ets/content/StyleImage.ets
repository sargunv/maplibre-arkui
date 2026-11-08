import { DrawableDescriptor } from '@ohos.arkui.drawableDescriptor';
import image from '@ohos.multimedia.image';

/**
 * An image for icons and patterns: the sources that ArkUI's `Image` takes,
 * except strings, which name an image of the style. Closed.
 *
 * A pixel map draws at the display density, as an `Image` draws it. A resource
 * or drawable descriptor draws at the size that an `Image` draws it, and a
 * resource takes its dark-mode media while the system is in dark mode. Drawing
 * a resource or drawable descriptor needs a UI context, which a `MaplibreMap`
 * has and `renderSnapshot()` has only with its `uiContext`.
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

/** An image for an ID that the style lacks, or that `MapStyle.setImage()` sets. */
export interface ResolvedStyleImage extends StyleImageOptions {
  /** The image. */
  image: StyleImageSource;
}
