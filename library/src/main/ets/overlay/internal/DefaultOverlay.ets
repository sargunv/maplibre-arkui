import { DefaultControls } from '../DefaultControls';

// What a MaplibreMap draws when the app leaves out its trailing closure.
@Builder
export function defaultOverlay() {
  DefaultControls()
}
