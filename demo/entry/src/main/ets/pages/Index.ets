import {
  CameraTransitionOutcome,
  CameraUpdateMode,
  LatLngBounds,
  MapController,
  MapLibreMap,
} from '@maplibre/arkui';

import { Engine } from './Engine';
import { StyleDemo } from './StyleDemo';
import { LIBERTY, TwoMaps } from './TwoMaps';

const SWITZERLAND: LatLngBounds = {
  southwest: { latitude: 45.82, longitude: 5.96 },
  northeast: { latitude: 47.81, longitude: 10.49 },
};

@Entry
@ComponentV2
struct Index {
  @Local stack: NavPathStack = new NavPathStack();
  @Local showMap: boolean = true;
  @Local message: string = '';
  private map: MapController = new MapController({
    camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
  });

  build() {
    Navigation(this.stack) {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.showMap) {
          MapLibreMap({
            controller: this.map,
            style: LIBERTY,
            onMapError: (error: Error) => {
              this.message = error.message;
            },
          })
        } else {
          Text('The map is hidden')
            .width('100%')
            .height('100%')
            .textAlign(TextAlign.Center)
        }
        Column({ space: 8 }) {
          Text(this.describeCamera())
            .fontSize(14)
          if (this.message !== '') {
            Text(this.message)
              .fontSize(14)
          }
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            Button('Jump').margin(4).onClick(() => this.jump())
            Button('Fly').margin(4).onClick(() => this.fly())
            Button('Fit').margin(4).onClick(() => this.fit())
            Button('Cancel').margin(4).onClick(() => {
              this.map.cancelCameraTransitions().catch((error: Error) => this.message = error.message);
            })
            Button(this.showMap ? 'Hide map' : 'Show map').margin(4).onClick(() => {
              this.showMap = !this.showMap;
            })
            Button('Two maps').margin(4).onClick(() => {
              this.stack.pushPathByName('two-maps', null);
            })
            Button('Snapshots, offline').margin(4).onClick(() => {
              this.stack.pushPathByName('engine', null);
            })
            Button('Style').margin(4).onClick(() => {
              this.stack.pushPathByName('style', null);
            })
          }
        }
        .padding(12)
        .margin({ left: 12, right: 12, bottom: 32 })
        .borderRadius(16)
        .backgroundColor('#e6ffffff')
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pages)
  }

  @Builder
  pages(name: string) {
    if (name === 'two-maps') {
      TwoMaps()
    } else if (name === 'engine') {
      Engine()
    } else if (name === 'style') {
      StyleDemo()
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

  private jump(): void {
    this.report(this.map.updateCamera({
      mode: CameraUpdateMode.jump,
      camera: { center: { latitude: 35.6764, longitude: 139.65 }, zoom: 12, bearing: 0, pitch: 0 },
    }));
  }

  private fly(): void {
    this.report(this.map.updateCamera({
      mode: CameraUpdateMode.fly,
      camera: { center: { latitude: 40.7128, longitude: -74.006 }, zoom: 13, bearing: 30, pitch: 45 },
      animation: { durationMs: 4000 },
    }));
  }

  private fit(): void {
    this.report(this.map.fitCameraToLatLngBounds(SWITZERLAND, {
      mode: CameraUpdateMode.ease,
      fit: { padding: { top: 48, left: 24, bottom: 240, right: 24 }, bearing: 0, pitch: 0 },
      animation: { durationMs: 1500 },
    }));
  }

  private report(transition: Promise<CameraTransitionOutcome>): void {
    this.message = 'Moving…';
    transition.then((outcome: CameraTransitionOutcome) => {
      this.message = `The camera move ${outcomeName(outcome)}`;
    }).catch((error: Error) => {
      this.message = error.message;
    });
  }
}

function outcomeName(outcome: CameraTransitionOutcome): string {
  switch (outcome) {
    case CameraTransitionOutcome.completed:
      return 'completed';
    case CameraTransitionOutcome.cancelled:
      return 'was cancelled';
    case CameraTransitionOutcome.replaced:
      return 'was replaced';
    default:
      return 'ended as the map closed';
  }
}
