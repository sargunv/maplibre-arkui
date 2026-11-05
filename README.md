# maplibre-arkui

An ArkUI library for [MapLibre Native] on HarmonyOS and OpenHarmony, built on
the ArkTS bindings of [MapLibre Native FFI]. It is a cousin of [MapLibre
Compose]. It's early: the package, `@maplibre/arkui`, has style expressions but
no map yet. See [ROADMAP.md](ROADMAP.md) for the plan.

## Using it

The library will be published on [ohpm] as a source HAR that requires API 20. It
depends on FFI's backend-free facade, `@maplibre/native-ffi`, and an app
installs one backend next to it, `@maplibre/native-ffi-opengl`, since ohpm has
no peer dependencies. Until FFI publishes those packages, build against FFI main
as below.

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
