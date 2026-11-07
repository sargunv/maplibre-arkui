// What a map's onCameraMoveStart receives.

import { CameraMoveReason } from './CameraMoveReason';

/** The camera left rest. The map creates it; fields may be added in later releases. */
export interface CameraMoveStartEvent {
  /** What moved the camera. */
  reason: CameraMoveReason;
}
