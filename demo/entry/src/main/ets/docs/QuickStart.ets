// The quick start of README.md, library/README.md, and the documentation site,
// as they write it. The demo's "Quick start" button opens it.

// #region quick-start
import { CameraTransitionMode, MapController, MapLibreMap } from '@maplibre/arkui';

@Entry
@ComponentV2
struct MapPage {
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
  });

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MapLibreMap({
        controller: this.controller,
        style: 'https://tiles.openfreemap.org/styles/liberty',
        onMapError: (error: Error) => console.error(error.message),
      })
      Button('Fly to New York')
        .margin(64)
        .onClick(() => {
          this.controller.updateCamera(
            { center: { latitude: 40.7128, longitude: -74.006 }, zoom: 12 },
            { mode: CameraTransitionMode.FLY, durationMs: 3000 },
          ).catch((error: Error) => console.error(error.message));
        })
    }
    .width('100%')
    .height('100%')
  }
}
// #endregion quick-start
