# Repository guidance

maplibre-arkui is an ArkUI library for MapLibre Native on HarmonyOS and
OpenHarmony, built on the ArkTS bindings of [MapLibre Native FFI][ffi]. It is a
cousin of [MapLibre Compose][compose], whose `maplibreNativeMain` source set
also runs on FFI.

## Priorities

In order:

- Simple, clear code. A map that behaves well with simple code beats one that
  matches MapLibre Compose or any other reference exactly.
- Idiomatic ArkTS and ArkUI over imitating MapLibre Compose. Compose is a
  reference for what a map library needs; when its shape conflicts with what
  ArkUI developers expect, follow ArkUI.
- Modern over legacy: state management V2 and current APIs only. The API floor
  is FFI's, 20.
- Wrap FFI only where wrapping helps. Re-export FFI types and expose FFI handles
  where that already reads as ArkTS.
- Build the imperative core first. Every declarative feature sits on imperative
  operations that apps can also call. FFI renders, paces frames, and moves the
  camera; this library adds input, widgets, and declarative UI for ArkUI.
- Avoid native code. FFI's packages attach to an XComponent surface from ArkTS.
- Gestures are intricate. Study ArkUI's gesture idioms and Compose's
  [interaction source][compose-interaction] before changing them.

Nothing is published, so the public API has no users to keep working. When a
better name or shape appears, change it everywhere: no deprecations, aliases, or
compatibility shims until the first release.

Report FFI gaps and bugs upstream in [maplibre-native-ffi][ffi-issues] instead
of working around them with complex code.

## Development

Public API is what `library/Index.ets` exports, and it follows the
[API guidelines](docs/src/content/docs/api-guidelines.md). `library/` is the
source HAR, `demo/` the demo app, `docs/` the documentation site, and `scripts/`
what the mise tasks run.

Run `mise install` once. It installs the OpenHarmony SDK (about 4 GB, through
the [mise-ohos-sdk](https://github.com/sargunv/mise-ohos-sdk) plugin) and the
Oniro emulator image (1.4 GB). `mise tasks` lists the tasks:

- `mise run check` / `mise run fix`: formatters and linters through hk.
- `mise run ffi:download`: fetch FFI's packages into `build/ffi`, which the
  build tasks need. `FFI_DIR=<checkout> mise run ffi:pack [preset]` packs them
  from an FFI checkout instead.
- `mise run pack`, `demo:build`, `test:build`, `docs:build`: build the HAR, the
  demo HAP, the test HAP, or the site. The HAPs take `--abi x86_64` (the
  default, for the Oniro emulator and CI) or `--abi arm64-v8a`.
- `mise run demo` / `mise run test`: build for the device's ABI, then start the
  demo or run the hypium suite on this worktree's Oniro emulator, or on the
  device that `--device <key>` names. The test task fails unless hypium reports
  every case passed.
- `mise run docs:dev`: serve the site with live reload.

The Oniro emulator's llvmpipe crashes the app in most full suite runs
([maplibre-native-ffi#1692][ffi-1692]); a run that ends without hypium's tally
crashed, which isn't a reason to retry. DevEco Studio's emulator has a GPU and
finishes the suite. `scripts/ohos-key.sh` prints this worktree's emulator key,
booting it and waking it if needed; `devices-cli release` stops it. Don't run
`power-shell suspend`, which hangs `hdc shell`. Screenshot with
`hdc -t <key> shell snapshot_display -f /data/local/tmp/x.jpeg`, then
`hdc -t <key> file recv /data/local/tmp/x.jpeg .proof/x.jpeg`.

`vars.ffi_commit` in `mise.toml` pins the FFI main commit whose CI packages
`ffi:download` fetches. FFI keeps them for 30 days, so pick the newest main
commit whose CI has the `ohpm-packages-*` artifact.

HAPs build without hvigor: `scripts/build-hap.sh` runs ets-loader's webpack
build, es2abc, and `scripts/pack-hap.sh`, with the library HAR's sources joined
into the module and FFI's facade and hypium kept as external records.
`scripts/ets-loader-patches.cjs` patches two ets-loader bugs and stops the build
if an SDK update changes the patched text. ets-loader only warns on ArkTS
errors, so `build-hap.sh` fails on its `ArkTSLinter_output.json`.

### ArkTS and ArkUI

- State management V2 only; no V1 decorators.
- Strict ArkTS. Check ideas against the [migration rules][arkts-migration]: no
  object spread, `as const`, destructuring, structural typing, or `#private`
  fields. Style JSON is a `Record<string, Object>` literal with quoted keys,
  each nested object in a variable of its own.
- Import `@ohos.*` modules, not `@kit.*`, which the webpack build doesn't
  rewrite.
- Import FFI's `Camera` type as `CameraPosition`; ArkUI reserves the name.
- The webpack build's tsconfig omits `NodeContainer`, `ContentSlot`, and
  `SymbolGlyph`, and rejects `layoutGravity`. In a `ForEach` item, a built-in
  component fails to build and a custom component's trailing closure is silently
  lost; have the item call a `@Builder`.
- The build has no resource table, so no `$r()`; load files from
  `resources/rawfile` with `getRawFileContentSync()`. Ornaments use `sys.*`
  resources so they follow dark mode.
- No formatter understands `.ets`: format it by hand like the existing files (2
  spaces, single quotes). `oh-package.json5` files stay plain JSON, which the
  scripts read with jq.
- The library declares no permission, since a HAR's `requestPermissions` merge
  into every app. Location comes from the app as a
  `geoLocationManager.Location`.

### Library internals

- The FFI map is usable only once `map.ready` settles; `MapView` exposes it to
  the controller only after that.
- The library owns each runtime's one FFI event handler and its maps' event
  masks. Code that needs events uses `addRuntimeEventListener()` with the map
  events it needs, never `setEventHandler()` or `setEventMask()`.
- Map content is data. `ContentReconciler` runs one pass at a time and awaits
  each FFI command, so its record of the style stays true; don't pipeline
  commands. It owns only what it added, by ID, and starts over on each style
  load.
- Per-frame state lives in one traced field, the controller's frame view. Read
  it through `frameCamera` and the projection methods, in `@Computed` getters.
- The map's ArkUI gestures only claim touches; `MapGestures` moves the camera
  from the raw touches after a claim. Keep camera math out of gesture callbacks,
  except for touchpad pinch. On HarmonyOS 6 only `changedTouches` has correct
  coordinates, so the recognizer reads positions from it.
- Expressions are untyped and immutable; FFI takes them through `toJSON()`. A
  new expression function gets a JSON case and a case that FFI's
  `StyleExpressionHandle` parses and evaluates.

### Tests

The hypium suite is in `library/src/ohosTest/`; `test/helpers.ets` holds what
cases share.

- Wait with frame callbacks, not timers: OpenHarmony's main thread can lose a
  timer's wakeup and hang a `setTimeout` poll.
- Each suite that uses the test page's map calls `testMap.reset()` in its
  `beforeEach` rather than undoing its changes afterward.
- Turn on the scale bar, markers, and compass only while a case needs them; the
  suites that need no map run before any suite shows it. Content moving over a
  map makes the llvmpipe crash likelier.
- hypium's `assertClose` divides by the actual value; use `expectNear()`.
- The map reads layer properties back normalized: colors as
  `["rgba", r, g, b, a]`, expressions wrapped in their type's coercion, unset
  properties as `undefined`.
- Cases may import internal files by path
  (`@maplibre/arkui/src/main/ets/gestures`). `GestureInput.test.ets` injects
  real input through `@ohos.UiTest`, which takes px: aim and time input in vp,
  and measure motion with the map's projection, so cases hold at any density.
- Cases don't need the network, except the resource transform case. The
  emulators have no location fixes, so cases pass made-up locations.

## Documentation

Documentation describes the library as it is, for a reader who doesn't know its
history. Notes about what changed belong in the PR description.

- Site pages in `docs/src/content/docs/` help a user complete a task or
  understand a concept. Exact contracts belong in the doc comments, which become
  the API reference. A struct's members other than its params, and comments that
  start with "Internal:", stay out of it. FFI's re-exports link to FFI's
  reference; name symbols in pages with `<Api of="Name" />`, which fails the
  build on a name the reference doesn't have.
- Each ArkTS example on the site is a `// #region <name>` of
  `demo/entry/src/main/ets/docs/`, which compiles with the demo; the site build
  fails on a missing region. The READMEs keep only the quick start, in an `ets`
  block that is lines of those files; `mise run check` enforces it.
- The API guidelines describe the public API as it is; a change that departs
  from them changes them too.

## Issues and pull requests

Write a short PR title and description for a reviewer who will read the diff.
Say what the diff, its doc comments, and CI can't: open with the problem and
what users can now do, show one small example, and add validation that CI
doesn't run, such as a hypium run on a device. CI runs `mise run check` and the
builds, and deploys the site from `main`; it doesn't run the hypium suite.

When you post AI-contributed GitHub content, append this disclosure:
`*AI-assisted — Tool: <tool>; model: <provider>/<model>*`

## Later

Directions without a plan:

- Android and iOS through [ArkUI-X][arkuix], which has a cross-platform
  XComponent but no surface holder, and would need FFI runtime packages for it.
- Native components through ContentSlot and the NDK node API, if hosting from
  ArkTS limits performance.
- Compose on HarmonyOS ([ovCompose][ovcompose], [KuiklyUI][kuikly]), another
  path for MapLibre Compose that could share the native layer.
- OpenHarmony devices, which have no Map Kit; [TPC MapLibre][tpc-maplibre]
  already targets them.

## References

- FFI: the [ArkUI example][ffi-arkui], the [OpenHarmony header][ffi-ohos-h], and
  the guides to [create a map][ffi-create-map] and [show it in a
  window][ffi-window].
- [MapLibre Compose][compose].
- OpenHarmony: [ArkUI API design][arkui-api-design], [state management
  V2][oh-componentv2], [XComponent][oh-xcomponent], [HAR packages][oh-har],
  [publishing a HAR][hw-har-publish], [unit tests][oh-unittest], and the [Oniro
  emulator][oniro].
- Other maps on HarmonyOS, all imperative controller APIs: [Map Kit][hw-mapkit],
  [AMap][amap], [Baidu Maps][bdmap] (state management V2), and [Tencent
  Maps][tencentmap].

[amap]: https://ohpm.openharmony.cn/#/cn/detail/@amap%2Famap_lbs_map3d
[arkts-migration]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/typescript-to-arkts-migration-guide.md
[arkui-api-design]: https://gitcode.com/openharmony-skills/arkui-api-design
[arkuix]: https://gitcode.com/arkui-x
[bdmap]: https://ohpm.openharmony.cn/#/cn/detail/@bdmap%2Fmap
[compose]: https://maplibre.org/maplibre-compose/
[compose-interaction]:
  https://github.com/maplibre/maplibre-compose/tree/main/lib/maplibre-compose/src/commonMain/kotlin/org/maplibre/compose/interaction
[ffi]: https://maplibre.org/maplibre-native-ffi/
[ffi-1692]: https://github.com/maplibre/maplibre-native-ffi/issues/1692
[ffi-arkui]:
  https://github.com/maplibre/maplibre-native-ffi/tree/main/examples/arkui
[ffi-create-map]: https://maplibre.org/maplibre-native-ffi/guides/create-a-map/
[ffi-issues]: https://github.com/maplibre/maplibre-native-ffi/issues
[ffi-ohos-h]:
  https://github.com/maplibre/maplibre-native-ffi/blob/main/include/maplibre_native_c/platform/ohos.h
[ffi-window]:
  https://github.com/maplibre/maplibre-native-ffi/blob/main/docs/src/content/docs/guides/window.mdx
[hw-har-publish]:
  https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-har-publish
[hw-mapkit]:
  https://developer.huawei.com/consumer/cn/doc/harmonyos-references/map-mapcomponent
[kuikly]: https://github.com/Tencent-TDS/KuiklyUI
[oh-componentv2]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-componentV2.md
[oh-har]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/har-package.md
[oh-unittest]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/application-test/unittest-guidelines.md
[oh-xcomponent]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-xcomponent.md
[oniro]: https://github.com/eclipse-oniro4openharmony/device_board_oniro
[ovcompose]: https://github.com/Tencent-TDS/ovCompose-sample
[tencentmap]: https://ohpm.openharmony.cn/#/cn/detail/@tencentmap%2Fmap
[tpc-maplibre]: https://gitcode.com/CPF-ApplicationTPC/ohos_maplibre-native
