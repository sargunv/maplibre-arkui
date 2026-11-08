# MapLibre ArkUI

[![Documentation](https://img.shields.io/badge/Documentation-blue?logo=astro&logoColor=white)](https://code.sargunv.dev/maplibre-arkui/)
[![API Reference](https://img.shields.io/badge/API_Reference-blue?logo=typescript&logoColor=white)](https://code.sargunv.dev/maplibre-arkui/api/)
[![License](https://img.shields.io/github/license/sargunv/maplibre-arkui?label=License)](./LICENSE)

Interactive vector maps for ArkUI apps on HarmonyOS and OpenHarmony, rendered by
[MapLibre Native] through [MapLibre Native FFI]. Its sibling library, [MapLibre
Compose], brings the same engine to Compose Multiplatform.

The library is a preview and isn't on [ohpm] yet ([#26]). Until then, build it
from this repository; see [Build from source].

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

The [documentation] has the guides and the API reference.

## Developing

[mise] installs every tool, including the OpenHarmony SDK and an emulator image.
[Build from source] lists the everyday tasks, and [AGENTS.md](AGENTS.md) has the
guidance for contributors.

[#26]: https://github.com/sargunv/maplibre-arkui/issues/26
[Build from source]: https://code.sargunv.dev/maplibre-arkui/development/
[documentation]: https://code.sargunv.dev/maplibre-arkui/
[MapLibre Compose]: https://maplibre.org/maplibre-compose/
[MapLibre Native]: https://github.com/maplibre/maplibre-native
[MapLibre Native FFI]: https://maplibre.org/maplibre-native-ffi/
[mise]: https://mise.jdx.dev
[ohpm]: https://ohpm.openharmony.cn/
