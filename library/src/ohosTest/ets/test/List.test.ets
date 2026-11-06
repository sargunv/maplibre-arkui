import contentTest from './Content.test';
import expressionsTest from './Expressions.test';
import gestureInputTest from './GestureInput.test';
import gesturesTest from './Gestures.test';
import locationTest from './Location.test';
import mapControllerTest from './MapController.test';
import ornamentsTest from './Ornaments.test';
import runtimeTest from './Runtime.test';
import styleTest from './Style.test';

// The suites without a map on the page come first, and each suite with one
// resets it before each case.
export default function testsuite(): void {
  expressionsTest();
  gesturesTest();
  runtimeTest();
  mapControllerTest();
  styleTest();
  ornamentsTest();
  gestureInputTest();
  contentTest();
  locationTest();
}
