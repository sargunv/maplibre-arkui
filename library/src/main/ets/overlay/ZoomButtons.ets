import { CameraTransitionMode } from '../camera/CameraTransitionOptions';
import { GESTURE_ANIMATION_MS } from '../interaction/internal/MapGestures';
import { controlKey, findScope, MapScope } from '../map/internal/MapScope';
import { logError } from '../runtime/internal/Log';
import { BUTTON_SIZE } from './internal/Layout';

// What a press of the zoom buttons is moving the camera to.
interface ZoomStep {
  zoomIn: boolean;
  zoom: number;
}

/**
 * Buttons that zoom the map in and out by one level. Quick presses in the same
 * direction add up, so three presses zoom three levels.
 *
 * Works only in a `MaplibreMap`'s trailing closure. Elsewhere, it logs an
 * error and draws nothing.
 */
@ComponentV2
export struct ZoomButtons {
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();
  // A step steps on from the last one while it animates in the same
  // direction. Otherwise, it steps from the camera: the map may have clamped
  // the last step, and a gesture moves the camera elsewhere.
  private step: ZoomStep | undefined = undefined;

  @Monitor('scope.gesturing')
  gesturingChanged(): void {
    this.step = undefined;
  }

  build() {
    Stack() {
      if (this.scope !== undefined) {
        Column() {
          this.zoomButton($r('sys.media.ohos_ic_public_add'), $r('app.string.maplibre_zoom_in'), 1)
          Divider().width(BUTTON_SIZE / 2)
          this.zoomButton($r('sys.media.ohos_ic_public_minus'), $r('app.string.maplibre_zoom_out'), -1)
        }
        .borderRadius(BUTTON_SIZE / 2)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .shadow(ShadowStyle.OUTER_DEFAULT_XS)
      }
    }
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'ZoomButtons');
    })
  }

  @Builder
  zoomButton(icon: Resource, label: Resource, delta: number) {
    Button({ type: ButtonType.Circle }) {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor($r('sys.color.icon_primary'))
    }
    .width(BUTTON_SIZE)
    .height(BUTTON_SIZE)
    .backgroundColor(Color.Transparent)
    .accessibilityText(label)
    .onClick(() => this.zoomBy(delta))
  }

  private zoomBy(delta: number): void {
    const controller = this.scope?.controller;
    const camera = controller?.viewport?.camera;
    if (controller === undefined || camera === undefined) {
      return;
    }
    const zoomIn = delta > 0;
    const last = this.step;
    const step: ZoomStep = {
      zoomIn: zoomIn,
      zoom: (last !== undefined && last.zoomIn === zoomIn ? last.zoom : camera.zoom) + delta,
    };
    this.step = step;
    controller.updateCamera({ zoom: step.zoom }, { mode: CameraTransitionMode.EASE, durationMs: GESTURE_ANIMATION_MS })
      .catch((error: Error) => logError(error.message))
      .finally(() => {
        if (this.step === step) {
          this.step = undefined;
        }
      });
  }
}
