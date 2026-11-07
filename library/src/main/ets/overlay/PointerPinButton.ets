import { LatLng } from '../geometry/Geometry';
import { callHandler } from '../runtime/internal/Log';
import { noContent } from './internal/NoContent';
import { OffscreenMarker, OffscreenMarkerAngleEvent } from './OffscreenMarker';

// The pin's width and height in vp, and the diameter of its round part, a
// circle at the center. The pin's image, maplibre_pointer_pin, is 76 by 76,
// with a round part 48 across.
const PIN_SIZE = 64;
const PIN_ROUND_SIZE = PIN_SIZE * 48 / 76;

// Sets a button's accessibility text to a ResourceStr, which
// `accessibilityText()` takes only as a string or as a Resource.
class AccessibilityLabel implements AttributeModifier<ButtonAttribute> {
  private readonly label: ResourceStr;

  constructor(label: ResourceStr) {
    this.label = label;
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    if (typeof this.label === 'string') {
      instance.accessibilityText(this.label);
    } else {
      instance.accessibilityText(this.label as Resource);
    }
  }
}

/**
 * A button shaped like a map pin, on the edge of the map towards a coordinate
 * off the screen, which `OffscreenMarker` places. The pin turns to point at
 * the coordinate, and its content, such as a 24 vp icon, stays upright in its
 * round part. It hides while the coordinate is on the screen.
 *
 * ```ets
 * PointerPinButton({
 *   coordinate: PARIS,
 *   label: 'Paris',
 *   onPinClick: () => this.map.updateCamera({ center: PARIS }, { mode: CameraTransitionMode.EASE }),
 * }) {
 *   Image($r('sys.media.ohos_ic_public_location')).width(24).height(24)
 * }
 * ```
 *
 * It takes its label and click handler as parameters, rather than as
 * `.accessibilityText()` and `.onClick()`, because ArkUI would put those on a
 * node that the parent lays out by its own rules, not on the pin, as for
 * `Marker`.
 *
 * Place it in a `MaplibreMap`'s overlay; its parent sets the oval, as for
 * `OffscreenMarker`. It's the size of the pin, so taps beside it reach what's
 * under it. Anywhere but a map's overlay, it logs an error that names
 * `OffscreenMarker`, and draws nothing.
 */
@ComponentV2
export struct PointerPinButton {
  /** The coordinate that the pin points at. */
  @Require @Param coordinate: LatLng;
  /** What the pin leads to, which screen readers read as the button's text. */
  @Require @Param label: ResourceStr;
  /** The user clicked the pin. Called on the UI thread; the button logs what it throws. */
  @Event onPinClick: () => void = () => {
  };
  /** The content, in the trailing closure. */
  @BuilderParam content: () => void = noContent;
  @Local angle: number = 0;

  // The marker is the root, with no node of this component around it, so its
  // parent is the app's container.
  build() {
    OffscreenMarker({
      coordinate: this.coordinate,
      onAngleChange: (event: OffscreenMarkerAngleEvent) => {
        this.angle = event.angle;
      },
    }) {
      this.pin()
    }
  }

  @Builder
  pin() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Stack() {
        Image($r('app.media.maplibre_pointer_pin'))
          .width(PIN_SIZE)
          .height(PIN_SIZE)
          .fillColor($r('sys.color.comp_background_primary'))
          .draggable(false)
          .rotate({ angle: this.angle })
        Stack() {
          this.content()
        }
        .width(PIN_ROUND_SIZE)
        .height(PIN_ROUND_SIZE)
        .borderRadius(PIN_ROUND_SIZE / 2)
        .clip(true)
      }
      .width(PIN_SIZE)
      .height(PIN_SIZE)
    }
    .width(PIN_SIZE)
    .height(PIN_SIZE)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .attributeModifier(new AccessibilityLabel(this.label))
    .onClick(() => callHandler('onPinClick', () => this.onPinClick()))
  }
}
