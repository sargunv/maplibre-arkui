import { RuntimeStatus } from '@maplibre/arkui';

@Entry
@ComponentV2
struct Index {
  build() {
    Column({ space: 12 }) {
      Text('MapLibre ArkUI')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
      RuntimeStatus()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
