// The failures that a running map reports to its `onError`.

/**
 * A failure of a running map that no caller waits for, which the map reports
 * to its `onError` and to the log.
 *
 * Subclasses may be added in later releases; match them with `instanceof` and
 * keep a fallback. Failures without a subclass, such as a frame that fails to
 * render, a runtime that fails to start, or an invalid parameter, arrive as a
 * plain `MapError`.
 */
export class MapError extends Error {
  /** Creates an error with `message`, which describes the failure. */
  constructor(message: string) {
    super(message);
    this.name = 'MapError';
  }
}

/**
 * The map's style failed to load: its URL failed, or MapLibre rejected the
 * document. The map keeps no style until the next one loads.
 */
export class StyleLoadError extends MapError {
  /** Creates an error with `message`, which describes the failure. */
  constructor(message: string) {
    super(message);
    this.name = 'StyleLoadError';
  }
}

/**
 * The map rejected a source, layer, or image of its `content`, which stays out
 * of the style until it changes.
 */
export class ContentError extends MapError {
  /** The ID of the source, layer, or image that the map rejected. */
  readonly id: string;

  /** Creates an error for the content with `id`, with `message`, which describes the failure. */
  constructor(id: string, message: string) {
    super(message);
    this.name = 'ContentError';
    this.id = id;
  }
}
