import { controlKey, findScope, MapScope } from '../map/internal/MapScope';
import { AttributionText } from './AttributionText';

/**
 * The attribution of the map's sources, which the sources' terms usually
 * require, behind a button. It starts expanded; a tap on the button folds or
 * unfolds it, and it folds as the user starts a gesture. It shows the
 * attribution as `AttributionText` does. It draws nothing while the style has
 * no attribution.
 *
 * Place it in a `MaplibreMap`'s overlay. Anywhere else, it logs an error and
 * draws nothing.
 */
@ComponentV2
export struct AttributionButton {
  @Local scope: MapScope | undefined = undefined;
  private readonly nodeId: string = controlKey();
  @Local expanded: boolean = true;

  // ets-loader's webpack build warns that this watches no state variable. Its
  // checker types every member as `any` there, so it can't follow a path
  // through the scope, but the monitor runs as the value changes. It folds as
  // a gesture starts, not as one goes on, so a tap that unfolds it during a
  // gesture keeps it open.
  @Monitor('scope.gesturing')
  gesturingChanged(): void {
    if (this.scope?.gesturing === true) {
      this.expanded = false;
    }
  }

  @Computed
  get attributions(): string[] {
    return this.scope?.controller.attributions ?? [];
  }

  build() {
    Stack() {
      if (this.attributions.length > 0) {
        Flex({ alignItems: ItemAlign.Center }) {
          if (this.expanded) {
            AttributionText({ attributions: this.attributions })
              .flexShrink(1)
              .padding({ left: 12, top: 6, bottom: 6 })
          }
          Button({ type: ButtonType.Circle }) {
            Text('i')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.icon_secondary'))
              .textAlign(TextAlign.Center)
              .width(20)
              .height(20)
              .borderRadius(10)
              .border({ width: 1.5, color: $r('sys.color.icon_secondary') })
          }
          .width(32)
          .height(32)
          .flexShrink(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.maplibre_attribution'))
          .onClick(() => {
            this.expanded = !this.expanded;
          })
        }
        .width('auto')
        .padding(4)
        .borderRadius(20)
        .backgroundColor($r('sys.color.comp_background_primary'))
        .shadow(ShadowStyle.OUTER_DEFAULT_XS)
      }
    }
    .id(this.nodeId)
    .onAttach(() => {
      this.scope = findScope(this.getUIContext(), this.nodeId, 'AttributionButton');
    })
  }
}
