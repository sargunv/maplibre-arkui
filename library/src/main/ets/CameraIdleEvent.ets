// What a map's camera idle handler receives.

import { CameraPosition } from './CameraPosition';

/** Where the camera came to rest. The map creates it; fields may be added in later releases. */
export interface CameraIdleEvent {
  /** Where the camera rests, as `MapController.camera` reports it. */
  camera: CameraPosition;
}
