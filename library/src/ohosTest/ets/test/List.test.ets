import clicksTest from './Clicks.test';
import connectivityTest from './Connectivity.test';
import contentTest from './Content.test';
import expressionsTest from './Expressions.test';
import gestureInputTest from './GestureInput.test';
import gesturesTest from './Gestures.test';
import lifecycleTest from './Lifecycle.test';
import locationTest from './Location.test';
import mapControllerTest from './MapController.test';
import overlayTest from './Overlay.test';
import runtimeTest from './Runtime.test';
import styleTest from './Style.test';

// The suites without a map on the page come first, and each suite with one
// resets it before each case.
export default function testsuite(): void {
  expressionsTest();
  gesturesTest();
  runtimeTest();
  connectivityTest();
  mapControllerTest();
  lifecycleTest();
  styleTest();
  overlayTest();
  gestureInputTest();
  clicksTest();
  contentTest();
  locationTest();
}
