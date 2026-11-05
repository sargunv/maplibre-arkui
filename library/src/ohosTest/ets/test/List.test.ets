import engineTest from './Engine.test';
import expressionsTest from './Expressions.test';
import gestureInputTest from './GestureInput.test';
import gesturesTest from './Gestures.test';
import mapControllerTest from './MapController.test';
import ornamentsTest from './Ornaments.test';
import styleTest from './Style.test';

export default function testsuite(): void {
  expressionsTest();
  gesturesTest();
  mapControllerTest();
  engineTest();
  styleTest();
  ornamentsTest();
  gestureInputTest();
}
