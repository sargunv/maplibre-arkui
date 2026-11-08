// What a map's onCameraMoveStart receives.

import { CameraMoveReason } from './CameraMoveReason';

/**
 * What `MaplibreMap.onCameraMoveStart` receives. Fields may be added in later
 * releases.
 */
export interface CameraMoveStartEvent {
  /** What moved the camera. */
  readonly reason: CameraMoveReason;
}
