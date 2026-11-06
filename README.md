# MapLibre ArkUI

[![Documentation](https://img.shields.io/badge/Documentation-blue?logo=astro&logoColor=white)](https://code.sargunv.dev/maplibre-arkui/)
[![API Reference](https://img.shields.io/badge/API_Reference-blue?logo=typescript&logoColor=white)](https://code.sargunv.dev/maplibre-arkui/api/)
[![License](https://img.shields.io/github/license/sargunv/maplibre-arkui?label=License)](./LICENSE)

An ArkUI library for [MapLibre Native] on HarmonyOS and OpenHarmony, built on
the ArkTS bindings of [MapLibre Native FFI]. It is a cousin of [MapLibre
Compose]. The package, `@maplibre/arkui`, has a `MapLibreMap` component that
moves with touch, mouse, touchpad, and keyboard gestures, a `MapController` that
reads and moves its camera, ornaments, markers made of ArkUI content, the user's
location, map content that the app declares from its state, style expressions,
and snapshots. It passes on FFI's style API, request handlers, offline regions,
and logs as they are.

It's a preview, and it isn't on [ohpm] yet: it waits for FFI to publish its
packages there ([#26]). See [the changelog](library/CHANGELOG.md).

The [documentation] has the guides and the API reference.

## Install

The library is a source HAR for API 20 and later. Once it and FFI are on ohpm,
install it with one FFI backend, whose version must be the one that
`@maplibre/arkui` names:

```sh
ohpm install @maplibre/arkui @maplibre/native-ffi-opengl@<FFI version>
```

Until then, build the library and the demo from this repository (see [Build from
source]). [Getting started] has the details.

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

The library uses state management V2 only: put it in `@ComponentV2` structs. The
[documentation] goes on from here: the map and its camera, gestures, ornaments
and markers, map content and expressions, the style API, the user's location,
snapshots, requests, offline regions, and logs.

## Developing

[mise] installs everything, including the OpenHarmony SDK and an Oniro emulator
image. [Build from source] lists the tasks, and [AGENTS.md](AGENTS.md) describes
the layout, how the build works without hvigor, and how to release.

[#26]: https://github.com/sargunv/maplibre-arkui/issues/26
[Build from source]: https://code.sargunv.dev/maplibre-arkui/development/
[documentation]: https://code.sargunv.dev/maplibre-arkui/
[Getting started]: https://code.sargunv.dev/maplibre-arkui/getting-started/
[MapLibre Compose]: https://maplibre.org/maplibre-compose/
[MapLibre Native]: https://github.com/maplibre/maplibre-native
[MapLibre Native FFI]: https://maplibre.org/maplibre-native-ffi/
[mise]: https://mise.jdx.dev
[ohpm]: https://ohpm.openharmony.cn/
