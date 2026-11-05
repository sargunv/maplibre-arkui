# @maplibre/arkui

ArkUI components for [MapLibre Native] maps on HarmonyOS and OpenHarmony, built
on [MapLibre Native FFI]:

- `MapLibreMap`, a map that moves with touch, mouse, touchpad, and keyboard
  gestures, with a compass, scale bar, attribution, and zoom buttons
- `MapController`, which reads and moves the camera, with observable state
- `MapMarker`, ArkUI content pinned to a coordinate
- The user's location from Location Kit, and a camera that follows it
- Map content (sources, layers, and images) declared as data from the app's
  state, and functions that build style expressions
- `snapshot()`, a still image of a map
- MapLibre Native FFI's style API, request handlers, offline regions, and logs

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
`ohos.permission.INTERNET` in its `module.json5`.

## Quick start

```ets
import { CameraUpdateMode, MapController, MapLibreMap } from '@maplibre/arkui';

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
          this.controller.updateCamera({
            mode: CameraUpdateMode.fly,
            camera: { center: { latitude: 40.7128, longitude: -74.006 }, zoom: 12 },
            animation: { durationMs: 3000 },
          }).catch((error: Error) => console.error(error.message));
        })
    }
    .width('100%')
    .height('100%')
  }
}
```

## Guide

The [repository's README][guide] is the guide: the map and its camera, gestures,
ornaments and markers, map content and expressions, the style API, the user's
location, snapshots, requests, offline regions, and logs. Its examples build in
the repository's demo app, which shows each feature.

[guide]: https://github.com/sargunv/maplibre-arkui#readme
[MapLibre Native]: https://github.com/maplibre/maplibre-native
[MapLibre Native FFI]: https://maplibre.org/maplibre-native-ffi/
