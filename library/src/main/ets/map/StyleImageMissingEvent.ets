// What a map's onStyleImageMissing receives.

/**
 * The style uses an image that it doesn't have. The map creates it; fields may
 * be added in later releases.
 */
export interface StyleImageMissingEvent {
  /** The ID that the style names the image by, such as in a symbol layer's `icon-image`. */
  readonly id: string;
}
