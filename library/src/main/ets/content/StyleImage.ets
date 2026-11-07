import image from '@ohos.multimedia.image';

/**
 * The pixels of an image for symbol layers' `icon-image` and for patterns,
 * and how the map draws them, without the image's ID: what a map's
 * `onStyleImageMissing` resolves for the ID that it asked for. `StyleImage`
 * adds the ID.
 */
export interface ResolvedStyleImage {
  /**
   * The pixels, in the `RGBA_8888` or `BGRA_8888` format that decoding an
   * image file gives by default. The map rejects other formats; convert them
   * first with `PixelMap.convertPixelFormat()`.
   */
  image: image.PixelMap;
  /**
   * The image's pixels in each vp. The map's display density by default, so
   * the image draws at the size that ArkUI's `Image` draws the pixel map at;
   * in a snapshot, its `pixelRatio`. Finite and greater than 0.
   */
  pixelRatio?: number;
  /**
   * Whether the image is a signed distance field, which takes its color from
   * the layer's `icon-color`. False by default.
   */
  sdf?: boolean;
}

/**
 * An image for symbol layers' `icon-image` and for patterns, with the name
 * that layers give it.
 *
 * ```ets
 * const pin: StyleImage = { id: 'pin', image: pixelMap };
 * ```
 *
 * In the content, the image replaces any image that the style has with this
 * ID, such as one from the base style's sprite, and stays while the content
 * has it, whether a layer uses it or not. Once it leaves the content, the
 * style has no image with this ID. A new `image`, `pixelRatio`, or `sdf`
 * replaces the image. An image that the map rejects changes neither: it goes
 * to `MaplibreMap.onError` as a `ContentError`, and stays out of the style
 * until its `image`, `pixelRatio`, or `sdf` changes.
 *
 * The map reads the content's pixel map each time it applies the image, such
 * as when a style loads, so keep it unreleased while the content has it. It
 * compares pixel maps by identity: to change the pixels, give a new pixel map,
 * as pixels changed in place change nothing on the map.
 */
export interface StyleImage extends ResolvedStyleImage {
  /** The name that layers give the image, unique in the content. */
  id: string;
}
