# maplibre-arkui

An ArkUI library for [MapLibre Native] on HarmonyOS and OpenHarmony, built on
the ArkTS bindings of [MapLibre Native FFI]. It is a cousin of [MapLibre
Compose]. It's early: the package, `@maplibre/arkui`, shows a map, moves its
camera, and builds style expressions, without gestures yet. See
[ROADMAP.md](ROADMAP.md) for the plan.

## Using it

The library will be published on [ohpm] as a source HAR that requires API 20. It
depends on FFI's backend-free facade, `@maplibre/native-ffi`, and an app
installs one backend next to it, `@maplibre/native-ffi-opengl`, since ohpm has
no peer dependencies. Until FFI publishes those packages, build against FFI main
as below.

```ts
import { CameraUpdateMode, MapController, MapLibreMap } from '@maplibre/arkui';

@Entry
@ComponentV2
struct MapPage {
  private map: MapController = new MapController({
    camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
  });

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MapLibreMap({
        controller: this.map,
        style: 'https://tiles.openfreemap.org/styles/liberty',
        onMapError: (error: Error) => console.error(error.message),
      })
      Button('Fly to New York').onClick(() => {
        this.map.updateCamera({
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

An app that loads styles or tiles from the network requests
`ohos.permission.INTERNET` in its `module.json5`.

`MapController` reads and moves the camera from anywhere: its `camera` and
`styleLoaded` are observable, `getCamera()` reads the camera right now, and its
camera methods resolve with how the move ended. It also exposes the FFI runtime,
map, and render session for what this library doesn't wrap yet.

## Developing

[mise] installs everything, including the OpenHarmony SDK and an Oniro emulator
image:

```sh
mise install
mise run ffi:download   # FFI's packages at the pinned commit
mise run demo           # build the demo and start it on an emulator
mise run test           # run the hypium suite on the emulator
mise run check
```

[AGENTS.md](AGENTS.md) describes the layout, the tasks, and how the build works
without hvigor.

[MapLibre Compose]: https://maplibre.org/maplibre-compose/
[MapLibre Native]: https://github.com/maplibre/maplibre-native
[MapLibre Native FFI]: https://maplibre.org/maplibre-native-ffi/
[mise]: https://mise.jdx.dev
[ohpm]: https://ohpm.openharmony.cn/
