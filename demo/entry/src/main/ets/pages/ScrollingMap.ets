import { MapController, MaplibreMap } from '@maplibre/arkui';

import { LIBERTY } from './common';

// A map in a scrolling page. Drags that start on the map move it, and the page
// scrolls from elsewhere. In cooperative mode, one finger scrolls the page
// over the map too, and two fingers move the map.
@ComponentV2
export struct ScrollingMap {
  @Local cooperative: boolean = false;
  private map: MapController = new MapController({
    camera: { center: { latitude: 52.52, longitude: 13.405 }, zoom: 12 },
  });

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            Text('Cooperative gestures')
            Toggle({ type: ToggleType.Switch, isOn: this.cooperative })
              .onChange((isOn: boolean) => {
                this.cooperative = isOn;
              })
          }

          Text(this.cooperative ?
            'One finger scrolls the page, even over the map. Two fingers move the map.' :
            'Drags that start on the map move it. Drag elsewhere to scroll the page.')
            .fontSize(14)
          MaplibreMap({
            controller: this.map,
            style: LIBERTY,
            interactions: { cooperative: this.cooperative },
          })
            .height(320)
          this.filler('More of the page')
          this.filler('Scroll down from here')
          this.filler('The end of the page')
        }
        .padding(12)
      }
      .width('100%')
      .height('100%')
    }
    .title('Map in a scroll')
  }

  @Builder
  filler(label: string) {
    Text(label)
      .width('100%')
      .height(160)
      .padding(12)
      .borderRadius(12)
      .backgroundColor('#eeeeee')
  }
}
