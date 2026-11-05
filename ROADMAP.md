# maplibre-arkui roadmap

maplibre-arkui is a planned ArkUI library for MapLibre Native on HarmonyOS and
OpenHarmony. It is a cousin of [MapLibre Compose][compose], and it builds on the
ArkTS bindings of [MapLibre Native FFI][ffi]. MapLibre Compose now runs on FFI
too ([#1817][compose-1817]), so its `maplibreNativeMain` source set is the
closest prior art.

This roadmap orders the work and collects references for each stage. It does not
fix the API. Each stage settles its own API by prototyping against the
references listed for it.

## Guiding ideas

In order of priority:

- Simple, clear code. A map that behaves well with simple code beats one that
  matches MapLibre Compose, this roadmap, or any other reference exactly.
- Idiomatic ArkTS and ArkUI over imitating MapLibre Compose. Compose is a
  sibling toolkit and a reference for what a map library needs. When its shape
  conflicts with what ArkUI developers expect, follow ArkUI.
- Modern over legacy. Use state management V2 (`@ComponentV2`, `@ObservedV2`,
  `@Param`, `@Event`) and current APIs, and don't support V1 idioms. The minimum
  API level is the one FFI requires.
- Wrap FFI only where wrapping helps. MapLibre Compose wraps all of its engine
  because it shares one API with MapLibre GL JS. This library has no such
  constraint, so it can re-export FFI types and expose FFI handles where that is
  already idiomatic ArkTS.
- Gestures are intricate. Study ArkUI's gesture idioms and the MapLibre Compose
  [interaction source][compose-interaction-src] before designing them.
- Build the imperative core first. Every declarative feature sits on imperative
  operations that apps can also call. MapLibre Native FFI renders, paces frames,
  and moves the camera, but it doesn't recognize input or provide widgets or
  declarative UI ([platform integrations, #1601][ffi-1601]; [camera
  guide][ffi-camera]); this library is that layer for ArkUI.
- Avoid native code until a stage needs it. FFI's ArkTS packages attach to an
  XComponent surface from ArkTS, and its [ArkUI example][ffi-example-arkui] has
  no native code of its own.
- ArkUI has no equivalent of a custom Compose composition. There is no custom
  applier, and builders emit only UI nodes. Stage 7 decides how declarative map
  content works without one.
- ArkTS is stricter than TypeScript. Check each API idea against the [TypeScript
  to ArkTS migration rules][arkts-migration] before building on it. Examples: no
  object spread, no `as const`, no string-indexed property access, no
  destructuring, no structural typing, no `#private` fields, and object literals
  only for declared interfaces without methods. The guide also forbids literal
  types, but string-literal unions compile and ship in third-party libraries;
  check them against static ArkTS before relying on them.

## Stage 0: Build against FFI main

MapLibre Native FFI's ArkTS bindings are done on main, but the released version
doesn't have what this library needs yet. This library doesn't wait for a
release. It builds against FFI main, and what it learns informs that release.

Status:

- The TypeScript binding ([#826][ffi-826]) closed [#208][ffi-208] and
  [#50][ffi-50]. It has one generated Node-API binding for Node, Bun, Deno, and
  ArkTS. Callbacks and events are queued on the native side and delivered on the
  ArkTS thread.
- [#1550][ffi-1550] splits the OHPM packages into a backend-free facade,
  `@maplibre/native-ffi`, plus one backend package, `-opengl` or `-vulkan`. Each
  backend package carries every ABI, so one install serves devices and the
  emulator.
- [#1621][ffi-1621] paces frames with the native VSync, and [#1622][ffi-1622]
  attaches an XComponent surface with a graphics context that the library makes.
  Rendering runs on a library thread.
- [#1655][ffi-1655] adds an [ArkUI example][ffi-example-arkui]: a map page with
  touch gestures, in under 500 lines of ArkTS.
- [v0.202610.3][ffi-release] includes the TypeScript binding but predates the
  facade, the VSync pacing, the window attach, and the example. Its backend
  packages are the older, self-contained form, and the facade isn't on OHPM yet.
- [HarmonyOS platform support in MapLibre Native (#4315)][native-4315], merged.

Until FFI publishes these packages, the library uses the `ohpm-packages-*` HARs
that FFI's CI uploads, or HARs packed from a checkout of FFI main ([install
guide][ffi-install-ts]). The documented `pack-ohpm` command packs
`ohos-arm64-egl` only; the emulator needs `ohos-x64-egl`. Record each FFI gap or
bug the library hits, so it can be fixed upstream before the release.

Read first: the [ArkUI example][ffi-example-arkui], the [OpenHarmony platform
header][ffi-ohos-h], and the guides to [create a map][ffi-create-map] and [show
a map in a window][ffi-window].

## Stage 1: Project setup

Goal: an empty library package, a demo app, and CI that builds both and runs
tests on an emulator.

Questions:

- Package layout: one HAR, or a core HAR plus a separate HAR for styled controls
  (as MapLibre Compose separates [its Material 3 module][compose-material3]).
- Source HAR or bytecode HAR. The ohpm central repository accepts HARs only, not
  HSPs ([publishing a HAR][hw-har-publish]).
- How apps pick a backend. ohpm has no peer dependencies, so the library depends
  on the FFI facade and the app installs `-opengl` or `-vulkan`. Only OpenGL
  presentation is tested in FFI so far.
- How to pin FFI. It is pre-1.0 and most releases break its API, so the library,
  the facade, and the backend need matching versions.
- Minimum API level. FFI's packages require API 20 ([#1310][ffi-1310]), which is
  above what state management V2 needs. Note any newer APIs that later stages
  need. After API 24, versions are numbered from 26.0.0.
- Emulator and device testing: the Oniro emulator that FFI CI uses, or the
  DevEco Studio emulator.
- Build tooling. FFI builds HAPs without hvigor, whose packages have no clear
  license, and ets-loader there doesn't rewrite `@kit.*` imports ([ArkUI
  example][ffi-example-arkui]).
- Test framework. FFI runs its ArkTS suite with hypium on the emulator.

Decided (see `AGENTS.md`):

- One source HAR, `@maplibre/arkui` in `library/`, at API 20. It depends on the
  facade; the demo installs the facade and `-opengl`. A separate controls HAR
  waits for stage 8.
- FFI is pinned by commit in `mise.toml`. CI downloads the `ohpm-packages-*`
  artifact of FFI's CI run for that commit, which expires after 30 days, so the
  pin moves with FFI main; locally `ffi:pack` packs them from a checkout.
- HAPs build without hvigor, adapting FFI's scripts. ets-loader's webpack build
  needs two small patches, for imported `@ComponentV2` structs and for source
  HAR record names. It ignores `@kit.*` imports.
- The Oniro emulator through devices-cli, and hypium in a test ability with a
  window, following DevEco's ohosTest layout. CI builds the HAR and both HAPs
  but doesn't boot the emulator yet.
- No formatter understands `.ets`; ets-loader's ArkTS checks run in the build.

References:

- [HAR packages][oh-har], [converting HAR to HSP][oh-har-to-hsp], and
  [publishing a HAR][hw-har-publish]
- [Modular design best practices][hw-modular-design] and [multi-device
  layering][hw-multi-device]: the common layer is published as HAR or HSP and
  can't depend on feature layers
- [Third-party library guide for ohpm][oh-ohpm-guide], the [ohpm
  registry][ohpm], and publishing walkthroughs from the [OpenHarmony
  forum][oh-forum-publish] and [OpenHarmony developers][oh-publish-blog]
- [Unit test guidelines][oh-unittest]
- [ArkTS coding style guide][oh-arkts-style] and [ArkTS high-performance
  programming][oh-arkts-perf]
- [Oniro emulator images][oniro], how FFI provisions the OpenHarmony SDK
  ([`mise.ohos.toml`][ffi-mise-ohos]), and how it builds the [ArkUI
  example][ffi-example-arkui] (`scripts/build-hap.sh`)
- The [MapLibre Compose demo app][compose-demo], as a model for the demo

## Stage 2: A map on screen

Goal: a component that shows a style, resizes, and survives page and app
lifecycle changes.

FFI and its [ArkUI example][ffi-example-arkui] answer most of the setup. An
`XComponentController` subclass hands each surface ID to the FFI render session,
FFI paces frames with the native VSync on its own thread, the scale factor is
`vp2px(1)`, and the session can release a surface and take a new one without
losing tiles.

Questions:

- XComponent type: `SURFACE` performs better; `TEXTURE` composites with ArkUI
  content and animations, but FFI hasn't tested it. Since API 18, `SURFACE`
  rejects some attributes set dynamically through `attributeModifier`.
- Behavior when the page is hidden or the app goes to the background.
  `onPageShow` fires only on `@Entry` pages, not in `Navigation` or
  `BuilderNode` hosts.
- Several maps on one runtime.
- Density changes. A map's scale factor is fixed, so moving to a display of
  another density needs a new map.
- Vulkan or OpenGL on devices. FFI hasn't tested Vulkan presentation.

References:

- [XComponent reference][oh-xcomponent] and the [XComponent native rendering
  guide][oh-xcomponent-guide]
- FFI: the [ArkUI example][ffi-example-arkui], the [OpenHarmony platform
  header][ffi-ohos-h], and the guides to [create a map][ffi-create-map], [load a
  style][ffi-load-style], and [show a map in a window][ffi-window]
- How MapLibre Compose [presents a map outside Compose
  UI][compose-presentation], the closest analog to an XComponent
- [Custom component lifecycle][oh-component-lifecycle] and [UIAbility
  lifecycle][oh-uiability-lifecycle]
- [Node-API thread safety][oh-napi-thread-safety] and the [Node-API development
  rules][oh-napi-guidelines]
- Other libraries that render into an XComponent: [TPC MapLibre][tpc-maplibre],
  a port of MapLibre Native, and [lottie-turbo][lottie-turbo], which builds its
  XComponent natively in a `ContentSlot`

## Stage 3: Map state and camera

Goal: app code can read and move the camera, from inside and outside the map
component.

Questions:

- One state object, or a controller in the ArkUI style. ArkUI names imperative
  handles `Controller` (`XComponentController`, `TextInputController`) or after
  their role (`Scroller`, `NavPathStack`), and Map Kit hands out a
  `MapComponentController`. MapLibre Compose has settled on three objects: a
  runtime that maps share, a map state that is also the controller and outlives
  surfaces, and a presentation ([#1142][compose-1142], [#1162][compose-1162]).
  That split is the leading candidate.
- How engine state is observed. V2 observation works in plain classes, not only
  in components. FFI reads the camera synchronously, so per-frame values needn't
  be traced. MapLibre Compose puts per-frame geometry in one immutable
  `Viewport` value ([#1909][compose-1909]).
- Camera animations as Promises, and how they are cancelled. FFI reports when
  each camera transition completes, is cancelled, or is replaced.
- Camera constraints, and camera padding apart from viewport insets
  ([#1428][compose-1428]).
- Access to the FFI map and render session for features this library doesn't
  wrap. MapLibre Compose lends the platform map to a callback, marked delicate
  and experimental ([#1184][compose-1184]); here, exposing the FFI handles
  directly may be simpler.

References:

- [MapLibre Compose camera guide][compose-camera] (on main:
  [camera][compose-camera-main], [`MapRuntime`][compose-runtime-src]), and the
  State section of the [MapLibre Compose API guidelines][compose-api-guidelines]
- FFI: [move the camera][ffi-move-camera] and the [camera guide][ffi-camera]
- State management V2: [overview][oh-state-overview],
  [@ComponentV2][oh-componentv2], [@ObservedV2 and @Trace][oh-observedv2],
  [@Param][oh-param], [@Event][oh-event], [@Computed][oh-computed],
  [@Monitor][oh-monitor], [addMonitor and clearMonitor][oh-addmonitor], and
  [MVVM with V2][oh-mvvm-v2]
- [State management best practices][hw-state-best-practices]: don't make values
  the UI never reads into state, and group fields that change together
- [Map Kit `MapComponent`][hw-mapkit]

Watch for: `@Monitor` runs asynchronously, and `@Computed` in an `@ObservedV2`
class initializes asynchronously after construction. Check both against camera
updates on every frame. Synchronous options exist: `addMonitor` with
`isSynchronous` (API 20), `applySync` and `flushUpdates` (API 22), and
`@SyncMonitor` (API 23, above FFI's minimum).

## Stage 4: Gestures and input

Goal: pan, zoom, rotate, pitch, fling, and double-tap that cooperate with parent
scroll containers, plus mouse, keyboard, and scroll input on 2-in-1 devices.

Questions:

- ArkUI gestures, raw XComponent touch events (as the [FFI
  example][ffi-example-arkui] uses), or NDK gesture recognizers (as [TPC
  MapLibre][tpc-maplibre] uses, which would mean shipping native code). FFI
  applies camera deltas with gesture phases; recognizing gestures is up to this
  library.
- Gesture priority, arbitration, and nested scrolling. A custom component can't
  join the nested-scroll protocol, so a map inside a scroll container relies on
  gesture arbitration such as `shouldBuiltInRecognizerParallelWith`.
- Whether apps can attach map gestures to other components, as MapLibre
  Compose's `Modifier.mapInput` does ([#1898][compose-1898]).
- How much of the MapLibre Compose interaction model to port: bindings,
  mappings, momentum, bearing snapping, haptics.

References:

- [MapLibre Compose interaction guide][compose-interaction] and its [interaction
  source][compose-interaction-src]
- ArkUI gestures: [binding][oh-gesture-binding], [combined
  gestures][oh-gesture-combined], [gesture judging][oh-gesture-judge],
  [multi-level gestures][oh-gesture-multi-level], [pan][oh-pan],
  [pinch][oh-pinch], [rotation][oh-rotation]
- [Scroll container][oh-scroll], for nested scrolling
- [FFI camera guide][ffi-camera], on applying gestures as camera deltas

## Stage 5: Imperative style API

Goal: read and change the loaded style: sources, layers, images, feature state,
and queries.

Questions:

- Which parts of FFI's style API to wrap and which to re-export.
- Handle lifetime across style reloads. In MapLibre Compose, a handle is null
  until the style is ready, each loaded style publishes new handles
  ([#1157][compose-1157]), and an expired handle reads null and ignores writes
  ([#1737][compose-1737]).
- Errors, nulls, and logging, following section 3 of the [MapLibre Compose API
  guidelines][compose-api-guidelines].
- How GeoJSON and other bulk data cross the native boundary.
- Named style-spec values without literal types. MapLibre Compose now uses
  sealed types for names that the library defines, and reserves "open identity"
  (a value class with an internal constructor) for raw values from outside the
  library ([#1701][compose-1701], [#1703][compose-1703]). ArkTS has no
  `internal`; a HAR controls its public API only through what `Index.ets`
  exports.
- Feature queries need an attached render session, which can use a window or an
  offscreen target.

References:

- FFI guides: [add GeoJSON data][ffi-geojson], [add tile sources][ffi-tiles],
  [update data][ffi-update-data], [style layers by data][ffi-style-by-data],
  [set feature state][ffi-feature-state], [query a map][ffi-query-map], [query a
  source][ffi-query-source]
- MapLibre Compose: [handles][compose-composition], [styling][compose-styling],
  [images][compose-images], [features][compose-features],
  [clustering][compose-clustering]
- A warning from Flutter: in `maplibre_gl`, `setStyle()` [removes every layer
  the app added][flutter-maplibre-gl-styles]. The [`maplibre`
  package][flutter-maplibre] uses a style controller.

## Stage 6: Expressions

Goal: a typed way to write style expressions.

Questions:

- How much of MapLibre Compose's typed DSL survives without infix functions,
  operator overloading, extension functions, literal types, or conditional
  types.
- Structural equality on expressions, which stage 7 needs for cheap diffing.
- Serialization to style-spec JSON. MapLibre Compose now emits bare JSON where
  the style spec allows it ([#1881][compose-1881]).
- Unit conversion. MapLibre Compose converts `dp` and `sp` when it compiles an
  expression; ArkUI has the same problem with `vp` and `fp`.
- Testing expressions without a map. FFI's style expression handle parses and
  evaluates them on its own.

References:

- [MapLibre Compose expressions guide][compose-expressions] and its [expressions
  source][compose-expressions-src]
- [Style spec expressions][style-spec-expressions]
- [ArkTS migration rules][arkts-migration], especially the rules on generics,
  utility types, enums, and type predicates

## Stage 7: Declarative map content

Goal: apps declare sources and layers from app state. The library applies
changes, keeps content across style switches, controls order, and lets a
snapshotter use the same content.

MapLibre Compose does this with a custom composition ([how the map
composes][compose-composition]), but its applier is now thin: the composition
builds an immutable style snapshot, and a reconciler diffs it by ID against the
loaded style ([#1817][compose-1817]; [`StyleSnapshot`][compose-style-snapshot],
[`StyleReconciler`][compose-style-reconciler]). That reconciler could be ported
whatever produces the snapshot.

[TPC MapLibre][tpc-maplibre] built a declarative API on ArkUI and removed it,
citing property-name clashes and the lack of `@Watch`
(`platform/ohos/library/index.ets`). V2's `@Monitor` and prefixed property names
may avoid both.

Approaches from other ecosystems:

- Content as data, diffed by ID:
  - deck.gl [layers][deckgl-using-layers] and [`updateTriggers`][deckgl-layer]
  - Mapbox [declarative map styling][mapbox-declarative], where each call
    replaces the whole content, the library diffs it, and the same content works
    for snapshots; and [Mapbox in SwiftUI][mapbox-swiftui]
  - SwiftUI result builders, which produce value trees: [MapKit
    `MapContentBuilder`][apple-mapcontentbuilder], [Swift Charts][apple-charts],
    and [MapLibre's SwiftUI DSL][swiftui-dsl]
  - MapLibre GL JS [`setStyle` with diffing][gljs-setstyle] ([style
    source][gljs-style-src])
  - In ArkUI, the [VChart][vchart] `spec` and [mccharts][mccharts] `options`
- Components that render nothing and use context and effects:
  - react-map-gl's [`Layer`][react-map-gl-layer]: it renders null, adds the
    layer again after `styledata`, compares props one key at a time, and orders
    layers with `beforeId` and `moveLayer`
  - [react-leaflet core architecture][react-leaflet],
    [svelte-maplibre][svelte-maplibre], [vue-maplibre-gl][vue-maplibre-gl], and
    [@rnmapbox/maps][rnmapbox]
- Retained objects with observable properties: ArkUI V2 observation in plain
  classes ([@ObservedV2][oh-observedv2], [@Monitor][oh-monitor])
- Retained objects that apps change imperatively: ArkGraphics 3D, Huawei's own
  native scene graph ([overview][oh-graphics3d], [scenes][oh-graphics3d-scene])
- Imperative create and update closures:
  [`UIViewRepresentable`][apple-uiviewrepresentable] and
  [`RealityView`][apple-realityview]
- Full custom reconcilers, for contrast: [react-three-fiber][r3f], [Google Maps
  Compose][android-maps-compose], and React Native for OpenHarmony, which drives
  ArkUI's C API from React ([architecture][rnoh-arch], [C API move][rnoh-capi])

ArkUI behavior to prototype before choosing. The docs and the framework source
predict some answers, noted here; confirm them on a device.

- [`@Builder`][oh-builder] and [`@BuilderParam`][oh-builderparam] semantics, and
  whether [`@Consumer`][oh-provider-consumer] inside `@BuilderParam` content
  resolves to the map's `@Provider`. For V1 `@Consume`, the docs say content in
  a trailing closure resolves against the page that wrote it, not the component
  that renders it. Workarounds are passing the map state as a `@Param`, or a
  `BuilderNode` with `enableProvideConsumeCrossing`.
- Components whose `build()` draws nothing. They have no frame node until they
  have children, so the library can't find them by walking the node tree.
- Order of `aboutToAppear` when content is inserted conditionally
- [BuilderNode][oh-buildernode] ([API][oh-buildernode-api]) building a tree that
  isn't on screen, as a stand-in for a separate composition
- [ForEach][oh-foreach] key semantics
- `@Computed` getters that return arrays, and the cost of rebuilding them
- Snapshots. FFI has no snapshotter; a snapshot is an offscreen render target
  plus a still-image request.

## Stage 8: Ornaments and overlays

Goal: compass, scale bar, attribution, logo, and zoom buttons, plus ArkUI
components placed at geographic positions.

Questions:

- How apps style ornaments. Huawei's guidance for wrapper components is to
  accept an `AttributeModifier` for each inner part.
- Whether styled controls live in a separate package.
- Dark mode and resources.
- Drawing ArkUI content over a `SURFACE` XComponent, and keeping overlays on the
  same frame as the map. MapLibre Compose solved this on desktop
  ([#1417][compose-1417]) but not yet on Android ([#1368][compose-1368]).
- Positioning ArkUI content every frame without rebuilding it. Tencent Maps uses
  an `AttributeUpdater`, and TPC MapLibre places `ComponentContent` with
  `FrameNode`s.
- Map SDKs on HarmonyOS configure ornaments with enable flags and position
  setters, not modifiers.

References:

- MapLibre Compose: [controls guide][compose-controls], [overlay
  source][compose-overlay-src], [Material 3 module][compose-material3]
- AttributeModifier: [guide][oh-attributemodifier-guide],
  [reference][oh-attributemodifier-ref], [FAQ][oh-attributemodifier-faq]
- Huawei's [component encapsulation guide][hw-component-encapsulation]
- [ContentSlot][oh-contentslot-ref] ([guide][oh-contentslot-guide]),
  [FrameNode][oh-framenode], and [NDK custom components][oh-ndk-custom], for
  mixing native and ArkTS nodes
- Map Kit's [custom info window][hw-mapkit], a `@BuilderParam`
- [Dark and light color adaptation][oh-dark-light] and [resource
  categories][oh-resources]

## Stage 9: Location

Goal: show the user's location and let the camera follow it.

References:

- [MapLibre Compose location guide][compose-location] and its [HMS location
  runtime][compose-location-hms], which uses HMS Core on Android, not HarmonyOS
  Location Kit
- Location Kit: [introduction][oh-location-intro],
  [guidelines][oh-location-guidelines]
- [Requesting user authorization][oh-request-permission]

## Stage 10: Requests, offline, snapshots, logging, terrain

Goal: the remaining engine features of MapLibre Compose. Request handlers are
fixed when a runtime is created, in FFI and in MapLibre Compose
([#1287][compose-1287]). MapLibre Compose's terrain guide covers 3D buildings,
hillshade, and globe; it has no 3D terrain yet ([#1772][compose-1772]).

References:

- FFI guides: [intercept network requests][ffi-requests], [work
  offline][ffi-offline], [render a static image][ffi-static-image], [capture
  logs][ffi-logs]
- MapLibre Compose: [requests][compose-requests], [offline][compose-offline],
  [snapshotter][compose-snapshotter], [3D buildings and relief][compose-terrain]

## Stage 11: Guidelines, documentation, and release

Goal: written API guidelines, a documentation site, and publication on ohpm.
Early previews can ship from any earlier stage.

Questions:

- Which parts of the [MapLibre Compose API guidelines][compose-api-guidelines]
  carry over. Known differences: the ArkTS style guide uses UPPER_SNAKE
  constants; `Partial<T>` is allowed but object spread isn't, which affects the
  options pattern; options are interfaces without methods; open structures are
  matched with `instanceof`.
- Package scope and naming on ohpm. `@maplibre/arkui` fits next to FFI's
  `@maplibre/native-ffi`; TPC MapLibre plans `@ohos/maplibre`.
- Release cadence. ohpm lists a version only after review ([FFI
  #1365][ffi-1365]).
- Documentation comment conventions.

References:

- [ArkTS coding style guide][oh-arkts-style]
- [OpenHarmony API design specification v0.1][csdn-api-design-spec], from the
  API SIG (2022 trial version, republished)
- [arkui-api-design][arkui-api-design], an unofficial skill. It notes that the
  ArkUI SDK now declares APIs in both static and dynamic forms.
- [ohpm third-party guide][oh-ohpm-guide] and [publishing
  requirements][oh-forum-publish]
- [awesome-harmony-library][awesome-harmony], to compare popular packages

## Later

- **Android and iOS through ArkUI-X.** ArkUI-X added cross-platform XComponent
  in 2.0.0 Beta1 and 5.0.1, and 6.1.1 tracks API 24 and adds `TEXTURE`. It has
  no surface holder, so the surface ID path matters here. It would need FFI
  runtime packages for ArkUI-X on Android and iOS. Community reports describe
  slow maintenance and API gaps. ([GitCode][arkuix], [docs][arkuix-docs], [6.0.0
  release][arkuix-600], [overview][arkuix-overview])
- **Static ArkTS.** Find out what the SDK's static and dynamic declaration split
  means for third-party HARs. Static ArkTS may reach native code through ANI
  rather than Node-API, which FFI's binding uses.
- **Native components.** Use ContentSlot and the NDK node API if hosting from
  ArkTS limits performance.
- **Compose on HarmonyOS.** [ovCompose][ovcompose], [KuiklyUI][kuikly], and
  [`@cpf-kmp-cmp/compose`][cpf-compose] run Compose Multiplatform on HarmonyOS
  with a custom Kotlin/Native target. That is another path for MapLibre Compose,
  and could share the native layer.
- **OpenHarmony devices.** They have no Map Kit, so MapLibre fills a gap there.
  [TPC MapLibre][tpc-maplibre] already targets them.

## Other maps on HarmonyOS

All of these are imperative controller APIs:

- [Map Kit `MapComponent`][hw-mapkit] (HarmonyOS only)
- [AMap][amap], [Baidu Maps][bdmap], and [Tencent Maps][tencentmap] on ohpm.
  Baidu's component uses state management V2, and Tencent ships V1 and V2
  versions of its component.
- [TPC MapLibre][tpc-maplibre], a port of MapLibre Native on GitCode, not yet on
  ohpm

[amap]: https://ohpm.openharmony.cn/#/cn/detail/@amap%2Famap_lbs_map3d
[android-maps-compose]: https://github.com/googlemaps/android-maps-compose
[apple-charts]: https://developer.apple.com/documentation/charts
[apple-mapcontentbuilder]:
  https://developer.apple.com/documentation/mapkit/mapcontentbuilder
[apple-realityview]:
  https://developer.apple.com/documentation/realitykit/realityview
[apple-uiviewrepresentable]:
  https://developer.apple.com/documentation/swiftui/uiviewrepresentable
[arkts-migration]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/typescript-to-arkts-migration-guide.md
[arkui-api-design]: https://gitcode.com/openharmony-skills/arkui-api-design
[arkuix]: https://gitcode.com/arkui-x
[arkuix-600]: https://zhuanlan.zhihu.com/p/1987439206830732324
[arkuix-docs]: https://github.com/arkui-x/docs
[arkuix-overview]: https://cloud.tencent.com/developer/article/2544591
[awesome-harmony]: https://github.com/Madixin/awesome-harmony-library
[bdmap]: https://ohpm.openharmony.cn/#/cn/detail/@bdmap%2Fmap
[compose]: https://maplibre.org/maplibre-compose/
[compose-1142]: https://github.com/maplibre/maplibre-compose/pull/1142
[compose-1157]: https://github.com/maplibre/maplibre-compose/pull/1157
[compose-1162]: https://github.com/maplibre/maplibre-compose/pull/1162
[compose-1184]: https://github.com/maplibre/maplibre-compose/pull/1184
[compose-1287]: https://github.com/maplibre/maplibre-compose/pull/1287
[compose-1368]: https://github.com/maplibre/maplibre-compose/issues/1368
[compose-1417]: https://github.com/maplibre/maplibre-compose/pull/1417
[compose-1428]: https://github.com/maplibre/maplibre-compose/pull/1428
[compose-1701]: https://github.com/maplibre/maplibre-compose/pull/1701
[compose-1703]: https://github.com/maplibre/maplibre-compose/pull/1703
[compose-1737]: https://github.com/maplibre/maplibre-compose/pull/1737
[compose-1772]: https://github.com/maplibre/maplibre-compose/issues/1772
[compose-1817]: https://github.com/maplibre/maplibre-compose/pull/1817
[compose-1881]: https://github.com/maplibre/maplibre-compose/pull/1881
[compose-1898]: https://github.com/maplibre/maplibre-compose/pull/1898
[compose-1909]: https://github.com/maplibre/maplibre-compose/pull/1909
[compose-api-guidelines]: https://maplibre.org/maplibre-compose/api-guidelines/
[compose-camera]: https://maplibre.org/maplibre-compose/camera/
[compose-camera-main]:
  https://github.com/maplibre/maplibre-compose/blob/main/docs/src/content/docs/camera.mdx
[compose-clustering]:
  https://github.com/maplibre/maplibre-compose/blob/main/docs/src/content/docs/clustering.mdx
[compose-composition]: https://maplibre.org/maplibre-compose/composition/
[compose-controls]: https://maplibre.org/maplibre-compose/controls/
[compose-demo]: https://github.com/maplibre/maplibre-compose/tree/main/demo-app
[compose-expressions]: https://maplibre.org/maplibre-compose/expressions/
[compose-expressions-src]:
  https://github.com/maplibre/maplibre-compose/tree/main/lib/maplibre-compose/src/commonMain/kotlin/org/maplibre/compose/expressions
[compose-features]:
  https://github.com/maplibre/maplibre-compose/blob/main/docs/src/content/docs/features.mdx
[compose-images]: https://maplibre.org/maplibre-compose/images/
[compose-interaction]: https://maplibre.org/maplibre-compose/interaction/
[compose-interaction-src]:
  https://github.com/maplibre/maplibre-compose/tree/main/lib/maplibre-compose/src/commonMain/kotlin/org/maplibre/compose/interaction
[compose-location]: https://maplibre.org/maplibre-compose/location/
[compose-location-hms]:
  https://github.com/maplibre/maplibre-compose/tree/main/lib/location-runtime-hms
[compose-material3]:
  https://github.com/maplibre/maplibre-compose/tree/main/lib/maplibre-compose-material3
[compose-offline]: https://maplibre.org/maplibre-compose/offline/
[compose-overlay-src]:
  https://github.com/maplibre/maplibre-compose/tree/main/lib/maplibre-compose/src/commonMain/kotlin/org/maplibre/compose/overlay
[compose-presentation]: https://maplibre.org/maplibre-compose/presentation/
[compose-requests]: https://maplibre.org/maplibre-compose/requests/
[compose-runtime-src]:
  https://github.com/maplibre/maplibre-compose/blob/main/lib/maplibre-compose/src/commonMain/kotlin/org/maplibre/compose/map/MapRuntime.kt
[compose-snapshotter]: https://maplibre.org/maplibre-compose/snapshotter/
[compose-style-reconciler]:
  https://github.com/maplibre/maplibre-compose/blob/main/lib/maplibre-compose/src/commonMain/kotlin/org/maplibre/compose/style/StyleReconciler.kt
[compose-style-snapshot]:
  https://github.com/maplibre/maplibre-compose/blob/main/lib/maplibre-compose/src/commonMain/kotlin/org/maplibre/compose/style/StyleSnapshot.kt
[compose-styling]: https://maplibre.org/maplibre-compose/styling/
[compose-terrain]:
  https://github.com/maplibre/maplibre-compose/blob/main/docs/src/content/docs/terrain.mdx
[cpf-compose]: https://gitcode.com/CPF-KMP-CMP/compose-multiplatform-core
[csdn-api-design-spec]:
  https://blog.csdn.net/benco1986/article/details/145205715
[deckgl-layer]: https://deck.gl/docs/api-reference/core/layer
[deckgl-using-layers]: https://deck.gl/docs/developer-guide/using-layers
[ffi]: https://maplibre.org/maplibre-native-ffi/
[ffi-1310]: https://github.com/maplibre/maplibre-native-ffi/pull/1310
[ffi-1365]: https://github.com/maplibre/maplibre-native-ffi/issues/1365
[ffi-1550]: https://github.com/maplibre/maplibre-native-ffi/pull/1550
[ffi-1601]: https://github.com/maplibre/maplibre-native-ffi/issues/1601
[ffi-1621]: https://github.com/maplibre/maplibre-native-ffi/pull/1621
[ffi-1622]: https://github.com/maplibre/maplibre-native-ffi/pull/1622
[ffi-1655]: https://github.com/maplibre/maplibre-native-ffi/pull/1655
[ffi-208]: https://github.com/maplibre/maplibre-native-ffi/issues/208
[ffi-50]: https://github.com/maplibre/maplibre-native-ffi/issues/50
[ffi-826]: https://github.com/maplibre/maplibre-native-ffi/pull/826
[ffi-camera]:
  https://github.com/maplibre/maplibre-native-ffi/blob/main/docs/src/content/docs/guides/camera.mdx
[ffi-create-map]: https://maplibre.org/maplibre-native-ffi/guides/create-a-map/
[ffi-example-arkui]:
  https://github.com/maplibre/maplibre-native-ffi/tree/main/examples/arkui
[ffi-feature-state]:
  https://maplibre.org/maplibre-native-ffi/guides/set-feature-state/
[ffi-geojson]: https://maplibre.org/maplibre-native-ffi/guides/add-geojson-data/
[ffi-install-ts]:
  https://github.com/maplibre/maplibre-native-ffi/blob/main/docs/src/content/docs/install/typescript.mdx
[ffi-load-style]: https://maplibre.org/maplibre-native-ffi/guides/load-a-style/
[ffi-logs]: https://maplibre.org/maplibre-native-ffi/guides/capture-logs/
[ffi-mise-ohos]:
  https://github.com/maplibre/maplibre-native-ffi/blob/main/.config/mise.ohos.toml
[ffi-move-camera]:
  https://maplibre.org/maplibre-native-ffi/guides/move-the-camera/
[ffi-offline]: https://maplibre.org/maplibre-native-ffi/guides/work-offline/
[ffi-ohos-h]:
  https://github.com/maplibre/maplibre-native-ffi/blob/main/include/maplibre_native_c/platform/ohos.h
[ffi-query-map]: https://maplibre.org/maplibre-native-ffi/guides/query-a-map/
[ffi-query-source]:
  https://maplibre.org/maplibre-native-ffi/guides/query-a-source/
[ffi-release]:
  https://github.com/maplibre/maplibre-native-ffi/releases/tag/v0.202610.3
[ffi-requests]:
  https://maplibre.org/maplibre-native-ffi/guides/intercept-network-requests/
[ffi-static-image]:
  https://maplibre.org/maplibre-native-ffi/guides/render-a-static-image/
[ffi-style-by-data]:
  https://maplibre.org/maplibre-native-ffi/guides/style-layers-by-data/
[ffi-tiles]: https://maplibre.org/maplibre-native-ffi/guides/add-tile-sources/
[ffi-update-data]: https://maplibre.org/maplibre-native-ffi/guides/update-data/
[ffi-window]:
  https://github.com/maplibre/maplibre-native-ffi/blob/main/docs/src/content/docs/guides/window.mdx
[flutter-maplibre]: https://pub.dev/packages/maplibre
[flutter-maplibre-gl-styles]:
  https://maplibre.org/flutter-maplibre-gl/concepts/styles/
[gljs-setstyle]:
  https://maplibre.org/maplibre-gl-js/docs/API/classes/Map/#setstyle
[gljs-style-src]:
  https://github.com/maplibre/maplibre-gl-js/blob/main/src/style/style.ts
[hw-component-encapsulation]:
  https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-component-encapsulation
[hw-har-publish]:
  https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-har-publish
[hw-mapkit]:
  https://developer.huawei.com/consumer/cn/doc/harmonyos-references/map-mapcomponent
[hw-modular-design]:
  https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-modular-design
[hw-multi-device]:
  https://developer.huawei.com/consumer/cn/doc/doccenter-multi-device/bpta-multi-device-overview
[hw-state-best-practices]: https://www.cnblogs.com/strengthen/p/18498287
[kuikly]: https://github.com/Tencent-TDS/KuiklyUI
[lottie-turbo]: https://gitcode.com/CPF-ApplicationTPC/lottie_turbo
[mapbox-declarative]:
  https://docs.mapbox.com/ios/maps/guides/styles/declarative-map-styling/
[mapbox-swiftui]: https://docs.mapbox.com/ios/maps/guides/swift-ui/
[mccharts]: https://ohpm.openharmony.cn/#/cn/detail/@mcui%2Fmccharts
[native-4315]: https://github.com/maplibre/maplibre-native/pull/4315
[oh-addmonitor]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-addMonitor-clearMonitor.md
[oh-arkts-perf]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/arkts-high-performance-programming.md
[oh-arkts-style]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/arkts-coding-style-guide.md
[oh-attributemodifier-faq]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-attribute-modifier-faq.md
[oh-attributemodifier-guide]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-user-defined-extension-attributeModifier.md
[oh-attributemodifier-ref]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-attribute-modifier.md
[oh-builder]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-builder.md
[oh-buildernode]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-user-defined-arktsNode-builderNode.md
[oh-buildernode-api]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/js-apis-arkui-builderNode.md
[oh-builderparam]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-builderparam.md
[oh-component-lifecycle]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-page-custom-components-lifecycle.md
[oh-componentv2]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-componentV2.md
[oh-computed]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-computed.md
[oh-contentslot-guide]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/rendering-control/arkts-rendering-control-contentslot.md
[oh-contentslot-ref]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-components-contentSlot.md
[oh-dark-light]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/ui-dark-light-color-adaptation.md
[oh-event]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-event.md
[oh-foreach]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/rendering-control/arkts-rendering-control-foreach.md
[oh-forum-publish]:
  https://forums.openharmony.cn/forum.php?mod=viewthread&tid=397
[oh-framenode]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-user-defined-arktsNode-frameNode.md
[oh-gesture-binding]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-gesture-events-binding.md
[oh-gesture-combined]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-gesture-events-combined-gestures.md
[oh-gesture-judge]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-gesture-events-gesture-judge.md
[oh-gesture-multi-level]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-gesture-events-multi-level-gesture.md
[oh-graphics3d]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/graphics3d/arkgraphics3D-overview.md
[oh-graphics3d-scene]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/graphics3d/arkgraphics3D-scene.md
[oh-har]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/har-package.md
[oh-har-to-hsp]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/har-to-hsp.md
[oh-location-guidelines]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/device/location/location-guidelines.md
[oh-location-intro]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/device/location/location-kit-intro.md
[oh-monitor]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-monitor.md
[oh-mvvm-v2]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-mvvm-V2.md
[oh-napi-guidelines]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/napi/napi-guidelines.md
[oh-napi-thread-safety]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/napi/use-napi-thread-safety.md
[oh-ndk-custom]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/ndk-build-custom-components.md
[oh-observedv2]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-observedV2-and-trace.md
[oh-ohpm-guide]:
  https://github.com/openharmony/docs/blob/master/en/third-party-components/ohpm-third-party-guide.md
[oh-pan]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-gestures-pangesture.md
[oh-param]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-param.md
[oh-pinch]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-gestures-pinchgesture.md
[oh-provider-consumer]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-provider-and-consumer.md
[oh-publish-blog]: https://www.cnblogs.com/openharmony/p/17829637.html
[oh-request-permission]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/security/AccessToken/request-user-authorization.md
[oh-resources]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/resource-categories-and-access.md
[oh-rotation]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-gestures-rotationgesture.md
[oh-scroll]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-container-scroll.md
[oh-state-overview]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-state-management-overview.md
[oh-uiability-lifecycle]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/application-models/uiability-lifecycle.md
[oh-unittest]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/application-test/unittest-guidelines.md
[oh-xcomponent]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-xcomponent.md
[oh-xcomponent-guide]:
  https://github.com/openharmony/docs/blob/master/en/application-dev/ui/napi-xcomponent-guidelines.md
[ohpm]: https://ohpm.openharmony.cn/
[oniro]: https://github.com/eclipse-oniro4openharmony/device_board_oniro
[ovcompose]: https://github.com/Tencent-TDS/ovCompose-sample
[r3f]: https://github.com/pmndrs/react-three-fiber
[react-leaflet]: https://react-leaflet.js.org/docs/core-architecture/
[react-map-gl-layer]:
  https://github.com/visgl/react-map-gl/blob/master/modules/react-maplibre/src/components/layer.ts
[rnmapbox]: https://github.com/rnmapbox/maps
[rnoh-arch]: https://blog.csdn.net/qq_44924880/article/details/143364672
[rnoh-capi]: https://zhuanlan.zhihu.com/p/719918885
[style-spec-expressions]: https://maplibre.org/maplibre-style-spec/expressions/
[svelte-maplibre]: https://github.com/dimfeld/svelte-maplibre
[swiftui-dsl]: https://github.com/maplibre/swiftui-dsl
[tencentmap]: https://ohpm.openharmony.cn/#/cn/detail/@tencentmap%2Fmap
[tpc-maplibre]: https://gitcode.com/CPF-ApplicationTPC/ohos_maplibre-native
[vchart]: https://ohpm.openharmony.cn/#/cn/detail/@visactor%2Fharmony-vchart
[vue-maplibre-gl]: https://github.com/razorness/vue-maplibre-gl
