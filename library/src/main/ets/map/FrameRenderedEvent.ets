// What a map's onFrameRendered receives.

/**
 * A frame that the map drew, with MapLibre Native's measurements of it. The
 * map creates it; fields may be added in later releases.
 */
export interface FrameRenderedEvent {
  /**
   * Whether the frame drew everything that the view needs, or drew before
   * some tiles or images had loaded.
   */
  complete: boolean;
  /** Whether the map needs another frame to finish what this one started, such as a fade. */
  needsRepaint: boolean;
  /** Whether the symbols moved or changed in this frame. */
  placementChanged: boolean;
  /** How long the frame took to encode, in milliseconds. */
  encodingTimeMs: number;
  /** How long the frame took to render, in milliseconds. */
  renderingTimeMs: number;
  /** The frames that the map has drawn, with this one. */
  frameCount: number;
  /** The draw calls of this frame. */
  drawCallCount: number;
  /** The draw calls of every frame that the map has drawn, with this one. */
  totalDrawCallCount: number;
}
