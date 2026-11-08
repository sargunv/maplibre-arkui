import { CameraTransitionMode } from '../camera/CameraTransitionOptions';
import { GESTURE_ANIMATION_MS } from '../interaction/internal/MapGestures';
import { controlKey, findScope, MapScope } from '../map/internal/MapScope';
import { logError } from '../runtime/internal/Log';
import { FADE_MS, hideAfter, validDuration } from './internal/Disappearing';
import { BUTTON_SIZE } from './internal/Layout';

// How far the camera turns from north, from 0 to 180 degrees.
function turnFromNorth(bearing: number): number {
  return Math.abs((bearing % 360 + 540) % 360 - 180);
}

/**
 * A compass that points north. Tapping it turns the map to face north and
 * look straight down. It always shows; `DisappearingCompassButton` shows only
 * while the map is rotated or tilted.
 *
 * Works only in a `MaplibreMap`'s trailing closure. Elsewhere, it logs an
 * error and draws nothing.
 */
@ComponentV2
export struct CompassButton {
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();

  @Computed
  get bearing(): number {
    return this.scope?.controller.viewport?.camera.bearing ?? 0;
  }

  build() {
    Stack() {
      if (this.scope !== undefined) {
        Stack() {
          Column() {
            Polygon({ width: 10, height: 13 })
              .points([[0, 13], [5, 0], [10, 13]])
              .fill('#e53935')
            Polygon({ width: 10, height: 13 })
              .points([[0, 0], [5, 13], [10, 0]])
              .fill($r('sys.color.icon_secondary'))
          }
          .rotate({ angle: -this.bearing })
        }
        .width(BUTTON_SIZE)
        .height(BUTTON_SIZE)
        .borderRadius(BUTTON_SIZE / 2)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .shadow(ShadowStyle.OUTER_DEFAULT_XS)
        .accessibilityText($r('app.string.maplibre_compass'))
        .onClick(() => {
          this.scope?.controller.updateCamera({ bearing: 0, pitch: 0 },
            { mode: CameraTransitionMode.EASE, durationMs: GESTURE_ANIMATION_MS })
            .catch((error: Error) => logError(error.message));
        })
      }
    }
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'CompassButton');
    })
  }
}

/**
 * A `CompassButton` that fades in while the map is rotated or tilted, and
 * fades out after the map faces north and looks straight down again.
 *
 * Works only in a `MaplibreMap`'s trailing closure. Elsewhere, it logs an
 * error and draws nothing.
 */
@ComponentV2
export struct DisappearingCompassButton {
  /**
   * How long the button stays after the map faces north and looks straight
   * down again, in ms. At least 0, or `Infinity` to stay. 1000 by default; an
   * invalid value logs an error and uses the default.
   */
  @Param visibilityDurationMs: number = 1000;
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();
  @Local shown: boolean = false;
  // Counts the changes of `turned`, so a hide that a later turn overtook
  // doesn't run.
  private turns: number = 0;

  @Computed
  get durationMs(): number {
    return validDuration('DisappearingCompassButton', this.visibilityDurationMs, 1000);
  }

  @Computed
  get turned(): boolean {
    const camera = this.scope?.controller.viewport?.camera;
    return camera !== undefined && (turnFromNorth(camera.bearing) > 0.5 || camera.pitch > 0.5);
  }

  @Monitor('turned')
  turnedChanged(): void {
    const turn = ++this.turns;
    if (this.turned) {
      this.shown = true;
      return;
    }
    hideAfter(this.getUIContext(), this.durationMs, () => {
      if (turn === this.turns) {
        this.shown = false;
      }
    });
  }

  build() {
    Stack() {
      if (this.shown) {
        CompassButton()
          .transition(TransitionEffect.OPACITY.animation({ duration: FADE_MS }))
      }
    }
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'DisappearingCompassButton');
    })
  }
}
