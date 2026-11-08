// The failures that a running map reports to its `onError`.

/**
 * A failure that a map reports to `MaplibreMap.onError`. Subclasses may be
 * added in later releases, so match them with `instanceof` and keep a
 * fallback.
 */
export class MapError extends Error {
  /** Creates an error with `message`, which describes the failure. */
  constructor(message: string) {
    super(message);
    this.name = 'MapError';
  }
}

/** The map's style failed to load. */
export class StyleLoadError extends MapError {
  /** Creates an error with `message`, which describes the failure. */
  constructor(message: string) {
    super(message);
    this.name = 'StyleLoadError';
  }
}

/**
 * The map rejected a source or layer of its `content`. It stays off the map
 * until the app changes it.
 */
export class ContentError extends MapError {
  /** The ID of the rejected source or layer. */
  readonly id: string;

  /** Creates an error for the content with `id`. */
  constructor(id: string, message: string) {
    super(message);
    this.name = 'ContentError';
    this.id = id;
  }
}
