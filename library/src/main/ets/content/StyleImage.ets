import image from '@ohos.multimedia.image';

/** An image for icons and patterns, without an ID. */
export interface ResolvedStyleImage {
  /** The pixels, in `RGBA_8888` or `BGRA_8888` format. Other formats are rejected. */
  image: image.PixelMap;
  /**
   * How many of the image's pixels make one vp. Finite and greater than 0. The
   * display density by default, or a snapshot's `pixelRatio`.
   */
  pixelRatio?: number;
  /** Whether the image is a signed distance field. False by default. */
  sdf?: boolean;
}

/**
 * An image of the map's content, which layers name by its ID, such as in
 * `icon-image`. It replaces any image in the style with the same ID.
 *
 * Don't release the pixel map while the content has it. To change the pixels,
 * pass a new pixel map. An image that the map rejects is reported to `onError`
 * as a `ContentError`.
 */
export interface StyleImage extends ResolvedStyleImage {
  /** The ID that layers name the image by. */
  id: string;
}
