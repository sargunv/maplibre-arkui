# @maplibre/arkui

ArkUI components for [MapLibre Native] maps on HarmonyOS and OpenHarmony, built
on [MapLibre Native FFI]:

- `MaplibreMap`, a map that moves with touch, mouse, touchpad, and keyboard
  gestures, with localized controls that follow dark mode: a compass, scale bar,
  attribution, logo, and zoom buttons, in presets or placed by the app
- `MapController`, which reads and moves the camera, with observable state
- `MapPlacedAt` and `MapPointerPinButton`, ArkUI content pinned to a coordinate,
  or pointing to one off the screen
- The user's location from Location Kit, and a camera that follows it
- Map content (sources, layers, and images) declared as data from the app's
  state, and functions that build style expressions
- `snapshot()`, a still image of a map
- Feature queries, and MapLibre Native FFI's map for the rest of its style API
- MapLibre Native FFI's request handlers, offline regions, and logs

This is a preview. It uses state management V2 (`@ComponentV2`) and needs API 20
or later.

## Install

```sh
ohpm install @maplibre/arkui @maplibre/native-ffi-opengl@<FFI version>
```

`@maplibre/arkui` depends on FFI's facade, `@maplibre/native-ffi`, and the app
installs one backend for it, `@maplibre/native-ffi-opengl`, since ohpm has no
peer dependencies. The backend's version must be the facade's, which this
package's `oh-package.json5` names; `ohpm list` shows it.

An app that loads styles or tiles from the network requests
`ohos.permission.INTERNET` in its `module.json5`, and
`ohos.permission.GET_NETWORK_INFO`, so that maps follow the device's
connectivity.

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

The [documentation] has the guides, from the map and its camera to requests,
offline regions, and logs, and the [API reference]. Its examples build in the
repository's demo app, which shows each feature.

[API reference]: https://code.sargunv.dev/maplibre-arkui/api/
[documentation]: https://code.sargunv.dev/maplibre-arkui/
[MapLibre Native]: https://github.com/maplibre/maplibre-native
[MapLibre Native FFI]: https://maplibre.org/maplibre-native-ffi/
