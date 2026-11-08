// What a map's onStyleImageMissing receives.

/**
 * What `MaplibreMap.onStyleImageMissing` receives. Fields may be added in later
 * releases.
 */
export interface StyleImageMissingEvent {
  /** The ID of the missing image, as the style names it. */
  readonly id: string;
}
