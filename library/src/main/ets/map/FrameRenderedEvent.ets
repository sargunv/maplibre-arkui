// What a map's onFrameRendered receives.

/**
 * What `MaplibreMap.onFrameRendered` receives: measurements of one frame.
 * Fields may be added in later releases.
 */
export interface FrameRenderedEvent {
  /** Whether the frame drew everything in view, with nothing still loading. */
  readonly complete: boolean;
  /** Whether the map needs more frames to finish something, such as a fade. */
  readonly needsRepaint: boolean;
  /** Whether labels or icons moved, appeared, or disappeared in this frame. */
  readonly placementChanged: boolean;
  /** How long the frame took to encode. */
  readonly encodingTimeMs: number;
  /** How long the frame took to render. */
  readonly renderingTimeMs: number;
  /** How many frames the map has drawn, including this one. */
  readonly frameCount: number;
  /** How many draw calls this frame made. */
  readonly drawCallCount: number;
  /** How many draw calls the map has made, including this frame's. */
  readonly totalDrawCallCount: number;
}
