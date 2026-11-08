# @maplibre/arkui

Interactive vector maps for ArkUI apps on HarmonyOS and OpenHarmony, rendered by
[MapLibre Native] through [MapLibre Native FFI]. Needs API 20 or later and
ArkUI's state management V2.

## Install

```sh
ohpm install @maplibre/arkui @maplibre/native-ffi-opengl@<FFI version>
```

The backend's version must match the version of `@maplibre/native-ffi` that this
package depends on; `ohpm list` shows it. To load styles and tiles from the
network, request `ohos.permission.INTERNET` and
`ohos.permission.GET_NETWORK_INFO` in your app's `module.json5`.

## Quick start

```ets
import { CameraTransitionMode, MapController, MapError, MaplibreMap } from '@maplibre/arkui';

@Entry
@ComponentV2
struct MapPage {
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
  });

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MaplibreMap({
        style: 'https://tiles.openfreemap.org/styles/liberty',
        controller: this.controller,
        onError: (error: MapError) => console.error(error.message),
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
```

## Documentation

The [documentation] has the guides, and the [API reference] has every public
component, class, and function.

[API reference]: https://code.sargunv.dev/maplibre-arkui/api/
[documentation]: https://code.sargunv.dev/maplibre-arkui/
[MapLibre Native]: https://github.com/maplibre/maplibre-native
[MapLibre Native FFI]: https://maplibre.org/maplibre-native-ffi/
