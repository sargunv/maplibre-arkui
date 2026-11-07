import image from '@ohos.multimedia.image';

/**
 * An image for symbol layers' `icon-image` and for patterns.
 *
 * ```ets
 * const pin: StyleImage = { id: 'pin', image: pixelMap };
 * ```
 *
 * The image replaces any image that the style has with this ID, such as one
 * from the base style's sprite, and stays while the content has it, whether a
 * layer uses it or not. Once it leaves the content, the style has no image
 * with this ID. An image that the map rejects changes neither: it goes to
 * `MaplibreMap.onError` as a `ContentError`, and stays out of the style until
 * its `image`, `pixelRatio`, or `sdf` changes.
 */
export interface StyleImage {
  /** The name that layers give the image, unique in the content. */
  id: string;
  /**
   * The pixels, in the `RGBA_8888` or `BGRA_8888` format that decoding an
   * image file gives by default. The map rejects other formats; convert them
   * first with `PixelMap.convertPixelFormat()`.
   *
   * The map reads the pixel map each time it applies the image, such as when
   * a style loads, so keep it unreleased while the content has it. It compares
   * pixel maps by identity: to change the pixels, give a new pixel map, as
   * pixels changed in place change nothing on the map.
   */
  image: image.PixelMap;
  /**
   * The image's pixels in each vp. The map's display density by default, so
   * the image draws at the size that ArkUI's `Image` draws the pixel map at;
   * in a snapshot, its `pixelRatio`. Finite and greater than 0. A change
   * replaces the image.
   */
  pixelRatio?: number;
  /**
   * Whether the image is a signed distance field, which takes its color from
   * the layer's `icon-color`. False by default. A change replaces the image.
   */
  sdf?: boolean;
}
