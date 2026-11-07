import {
  CameraTransitionMode,
  LatLng,
  LatLngBounds,
  MapController,
  MapFullOverlay,
  MapLibreMap,
  MapPlacedAt,
  MapPointerPinButton,
} from '@maplibre/arkui';

import { DocExamples } from '../docs/Examples';
import { LIBERTY, PANEL } from './common';
import { LocationDemo } from './LocationDemo';
import { RuntimeDemo } from './RuntimeDemo';
import { ScrollingMap } from './ScrollingMap';
import { StyleDemo } from './StyleDemo';
import { TwoMaps } from './TwoMaps';

const EIFFEL_TOWER: LatLng = { latitude: 48.8584, longitude: 2.2945 };

const SWITZERLAND: LatLngBounds = {
  southwest: { latitude: 45.82, longitude: 5.96 },
  northeast: { latitude: 47.81, longitude: 10.49 },
};

interface City {
  name: string;
  coordinate: LatLng;
}

// The cities that the map pins labels to.
const CITIES: City[] = [
  { name: 'Paris', coordinate: { latitude: 48.8566, longitude: 2.3522 } },
  { name: 'London', coordinate: { latitude: 51.5072, longitude: -0.1276 } },
  { name: 'New York', coordinate: { latitude: 40.7128, longitude: -74.006 } },
  { name: 'Tokyo', coordinate: { latitude: 35.6764, longitude: 139.65 } },
];

@Entry
@ComponentV2
struct Index {
  @Local stack: NavPathStack = new NavPathStack();
  @Local showMap: boolean = true;
  @Local message: string = '';
  // The panel's height, which the map keeps its controls and the camera's
  // center above.
  @Local panelHeight: number = 0;
  @Local gesturing: boolean = false;
  private map: MapController = new MapController({
    camera: { center: EIFFEL_TOWER, zoom: 14 },
  });

  build() {
    Navigation(this.stack) {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.showMap) {
          MapLibreMap({
            controller: this.map,
            style: LIBERTY,
            viewportInsets: { bottom: this.panelHeight },
            onMapError: (error: Error) => {
              this.message = error.message;
            },
            onGestureStart: () => {
              this.gesturing = true;
            },
            onGestureEnd: () => {
              this.gesturing = false;
            },
          }) {
            // The webpack build rejects components written in a ForEach item,
            // so the item calls a builder.
            ForEach(CITIES, (city: City) => {
              this.cityLabel(city)
            }, (city: City) => city.name)
            // The controls stay clear of the viewport insets.
            MapFullOverlay()
            // A pin that points home once the Eiffel Tower is off the screen,
            // on an oval above the panel.
            Stack() {
              MapPointerPinButton({
                coordinate: EIFFEL_TOWER,
                onTap: () => this.goHome(),
              }) {
                Image($r('sys.media.ohos_ic_public_location'))
                  .width(24)
                  .height(24)
                  .fillColor($r('sys.color.icon_primary'))
              }
            }
            .padding({ bottom: this.panelHeight })
            .hitTestBehavior(HitTestMode.Transparent)
          }
        } else {
          Text('The map is hidden')
            .width('100%')
            .height('100%')
            .textAlign(TextAlign.Center)
        }
        Column({ space: 8 }) {
          Text(this.gesturing ? 'Moving with a gesture…' : this.describeCamera())
            .fontSize(14)
          if (this.message !== '') {
            Text(this.message)
              .fontSize(14)
          }
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            Button('Jump').margin(4).onClick(() => this.jump())
            Button('Fly').margin(4).onClick(() => this.fly())
            Button('Fit').margin(4).onClick(() => this.fit())
            Button('Europe').margin(4).onClick(() => this.flyOverEurope())
            Button('Rotate').margin(4).onClick(() => this.turn())
            Button('Cancel').margin(4).onClick(() => {
              this.map.cancelCameraTransitions().catch((error: Error) => this.message = error.message);
            })
            Button(this.showMap ? 'Hide map' : 'Show map').margin(4).onClick(() => {
              this.showMap = !this.showMap;
            })
            Button('Two maps').margin(4).onClick(() => {
              this.stack.pushPathByName('two-maps', null);
            })
            Button('Runtime').margin(4).onClick(() => {
              this.stack.pushPathByName('runtime', null);
            })
            Button('Style').margin(4).onClick(() => {
              this.stack.pushPathByName('style', null);
            })
            Button('In a scroll').margin(4).onClick(() => {
              this.stack.pushPathByName('scrolling-map', null);
            })
            Button('Location').margin(4).onClick(() => {
              this.stack.pushPathByName('location', null);
            })
            Button('Quick start').margin(4).onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'docs/QuickStart' })
                .catch((error: Error) => this.message = error.message);
            })
            Button('Guide examples').margin(4).onClick(() => {
              this.stack.pushPathByName('docs', null);
            })
          }
        }
        .attributeModifier(PANEL)
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.panelHeight = (newArea.height as number) + 32;
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pages)
  }

  // A label with the city's name, whose bottom tip is on the city.
  @Builder
  cityLabel(city: City) {
    MapPlacedAt({ coordinate: city.coordinate, alignment: Alignment.Bottom }) {
      this.label(city.name)
    }
  }

  @Builder
  label(name: string) {
    Column() {
      Text(name)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor('#d81b60')
      Polygon({ width: 12, height: 8 })
        .points([[0, 0], [12, 0], [6, 8]])
        .fill('#d81b60')
    }
  }

  @Builder
  pages(name: string) {
    if (name === 'two-maps') {
      TwoMaps()
    } else if (name === 'runtime') {
      RuntimeDemo()
    } else if (name === 'style') {
      StyleDemo()
    } else if (name === 'scrolling-map') {
      ScrollingMap()
    } else if (name === 'location') {
      LocationDemo()
    } else if (name === 'docs') {
      DocExamples()
    }
  }

  // Reads the observable camera, so the text updates when the camera comes to
  // rest.
  private describeCamera(): string {
    const camera = this.map.camera;
    if (camera === undefined) {
      return 'Loading…';
    }
    return `${camera.center.latitude.toFixed(4)}, ${camera.center.longitude.toFixed(4)} ` +
      `at zoom ${camera.zoom.toFixed(2)}`;
  }

  private goHome(): void {
    this.report(this.map.updateCamera({ center: EIFFEL_TOWER, zoom: 14 }, { mode: CameraTransitionMode.FLY }));
  }

  private jump(): void {
    this.report(this.map.updateCamera({
      center: { latitude: 35.6764, longitude: 139.65 },
      zoom: 12,
      bearing: 0,
      pitch: 0,
    }));
  }

  private fly(): void {
    this.report(this.map.updateCamera({
      center: { latitude: 40.7128, longitude: -74.006 },
      zoom: 13,
      bearing: 30,
      pitch: 45,
    }, { mode: CameraTransitionMode.FLY, durationMs: 4000 }));
  }

  private fit(): void {
    this.report(this.map.fitCameraToBounds(SWITZERLAND, {
      mode: CameraTransitionMode.EASE,
      durationMs: 1500,
      fitPadding: { top: 24, left: 24, bottom: 24, right: 24 },
      bearing: 0,
      pitch: 0,
    }));
  }

  // Flies out from Paris until London shows too, with both pinned.
  private flyOverEurope(): void {
    this.report(this.map.updateCamera({
      center: { latitude: 50.2, longitude: 1.2 },
      zoom: 5,
      bearing: 0,
      pitch: 0,
    }, { mode: CameraTransitionMode.FLY, durationMs: 5000 }));
  }

  // Turns the map, which shows the compass. Tapping it turns the map north.
  private turn(): void {
    const camera = this.map.getCamera();
    this.report(this.map.updateCamera({ bearing: (camera?.bearing ?? 0) + 45 },
      { mode: CameraTransitionMode.EASE, durationMs: 1000 }));
  }

  private report(transition: Promise<boolean>): void {
    this.message = 'Moving…';
    transition.then((completed: boolean) => {
      this.message = completed ? 'The camera move completed' : 'The camera move was stopped';
    }).catch((error: Error) => {
      this.message = error.message;
    });
  }
}
