// What a map's camera idle handler receives.

import { CameraPosition } from './CameraPosition';

/**
 * What `MaplibreMap.onCameraIdle` receives. Fields may be added in later
 * releases.
 */
export interface CameraIdleEvent {
  /** Where the camera came to rest. */
  readonly camera: CameraPosition;
}
