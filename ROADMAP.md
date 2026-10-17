# maplibre-arkui roadmap

maplibre-arkui is a planned ArkUI library for MapLibre Native on HarmonyOS and
OpenHarmony. It is a cousin of [MapLibre Compose][compose], and it builds on the
ArkTS bindings of [MapLibre Native FFI][ffi].

This roadmap orders the work and collects references for each stage. It does not
fix the API. Each stage settles its own API by prototyping against the
references listed for it.

## Guiding ideas

- Keep the concepts of MapLibre Compose, and express them in ArkUI idioms. When
  ArkUI has no equivalent of a Compose feature, follow ArkUI instead of
  imitating Compose.
- Build the imperative core first. Every declarative feature sits on imperative
  operations that apps can also call. MapLibre Native FFI leaves gestures,
  widgets, declarative UI, and lifecycle integration to downstream adapters
  ([README][ffi-readme]); this library is that adapter for ArkUI.
- ArkUI has no equivalent of a custom Compose composition. There is no custom
  applier, and builders emit only UI nodes. Stage 7 decides how declarative map
  content works without one.
- ArkTS is stricter than TypeScript. Check each API idea against the
  [TypeScript to ArkTS migration rules][arkts-migration] before building on it.
  Examples: no object spread, no literal types, no string-indexed property
  access, no destructuring, no structural typing, and object literals only for
  declared interfaces without methods.

## Stage 0: ArkTS bindings in MapLibre Native FFI

Nothing below starts until MapLibre Native FFI ships ArkTS bindings.

Status and plans:

- [Add ArkTS bindings (#208)][ffi-208]
- [The TypeScript binding plan][ffi-50-plan] in #50: one Node-API transport for
  Node, Bun, Deno, React Native, and ArkTS; a facade package plus one runtime
  payload package per target and backend, such as an `ohos-arm64-vulkan`
  payload; callbacks through the C callback adapter rather than direct calls
  from MapLibre threads.
- [Prototype TypeScript bindings (#553)][ffi-553], a draft that includes an
  ArkTS suite run on an OpenHarmony device.
- [Language binding status on OpenHarmony (#525)][ffi-525]. CI runs suites only
  on the Oniro emulator for `ohos-x64-egl`; arm64 targets are build-only.
- [HarmonyOS platform support in MapLibre Native (#4315)][native-4315], merged.

This stage is done when:

- The ArkTS bindings are published, with a runtime payload for devices and one
  for the emulator.
- A render target can be attached to the native window of an ArkUI XComponent.
- Callbacks and events reach the ArkTS thread.

Read while waiting: [FFI concepts][ffi-concepts], the
[binding specification][ffi-binding-spec], and the
[map example specification][ffi-map-example-spec].

## Stage 1: Project setup

Goal: an empty library package, a demo app, and CI that builds both and runs
tests on an emulator.

Questions:

- Package layout: one HAR, or a core HAR plus a separate HAR for styled controls
  (as MapLibre Compose separates [its Material 3 module][compose-material3]).
- HAR or HSP for the published library.
- Minimum API level. State management V2 needs API 12. Note any newer APIs
  that later stages need, such as the native XComponent surface holder.
- Emulator and device testing: the Oniro emulator that FFI CI uses, or the
  DevEco Studio emulator.
- Test framework.

References:

- [HAR packages][oh-har] and [converting HAR to HSP][oh-har-to-hsp]
- [Modular design best practices][hw-modular-design] and
  [multi-device layering][hw-multi-device]: the common layer is published as
  HAR or HSP and can't depend on feature layers
- [Third-party library guide for ohpm][oh-ohpm-guide], the
  [ohpm registry][ohpm], and publishing walkthroughs from the
  [OpenHarmony forum][oh-forum-publish] and [OpenHarmony developers][oh-publish-blog]
- [Unit test guidelines][oh-unittest]
- [ArkTS coding style guide][oh-arkts-style] and
  [ArkTS high-performance programming][oh-arkts-perf]
- [Oniro emulator images][oniro], and how FFI provisions the OpenHarmony SDK
  ([`mise.ohos.toml`][ffi-mise-ohos])
- The [MapLibre Compose demo app][compose-demo], as a model for the demo

## Stage 2: A map on screen

Goal: a component that shows a style, resizes, and survives page and app
lifecycle changes.

Questions:

- XComponent type: `SURFACE` performs better; `TEXTURE` composites with ArkUI
  content and animations.
- Surface lifecycle on the ArkTS side or the native side.
- Who drives the render loop, and how it syncs with display refresh.
- Pixel density and units (ArkUI uses `vp`).
- Behavior when the page is hidden, the app goes to the background, or several
  maps are shown.
- Vulkan or OpenGL on devices.

References:

- [XComponent reference][oh-xcomponent] and the
  [XComponent native rendering guide][oh-xcomponent-guide]
- FFI guides: [create a map][ffi-create-map], [load a style][ffi-load-style],
  [attach a render target][ffi-attach-render-target],
  [run the render loop][ffi-render-loop]
- FFI host examples: [Android][ffi-example-android] and
  [Compose][ffi-example-compose]
- [How MapLibre Compose presents the map][compose-presentation]
- [Custom component lifecycle][oh-component-lifecycle] and
  [UIAbility lifecycle][oh-uiability-lifecycle]
- [Node-API thread safety][oh-napi-thread-safety] and the
  [Node-API development rules][oh-napi-guidelines]
- Native renderers that use XComponent: [libpag][libpag] and
  [REDPlayer][redplayer]

## Stage 3: Map state and camera

Goal: app code can read and move the camera, from inside and outside the map
component.

Questions:

- One state object, or a controller in the ArkUI style. ArkUI names imperative
  handles `Controller` (`XComponentController`, `TextInputController`) or after
  their role (`Scroller`, `NavPathStack`), and Map Kit hands out a
  `MapComponentController`.
- How engine state is observed. V2 observation works in plain classes, not only
  in components.
- Camera animations as Promises, and how they are cancelled.
- Camera constraints and padding.

References:

- [MapLibre Compose camera guide][compose-camera], and the State section of the
  [MapLibre Compose API guidelines][compose-api-guidelines]
- [FFI: move the camera][ffi-move-camera]
- State management V2: [overview][oh-state-overview],
  [@ComponentV2][oh-componentv2], [@ObservedV2 and @Trace][oh-observedv2],
  [@Param][oh-param], [@Event][oh-event], [@Computed][oh-computed],
  [@Monitor][oh-monitor], [addMonitor and clearMonitor][oh-addmonitor],
  [MVVM with V2][oh-mvvm-v2], and [migrating from V1][oh-v1-v2-migration]
- [State management best practices][hw-state-best-practices]: don't make values
  the UI never reads into state, and group fields that change together
- [Map Kit `MapComponent`][hw-mapkit]

Watch for: `@Monitor` runs asynchronously, and `@Computed` in an `@ObservedV2`
class initializes asynchronously after construction. Check both against camera
updates on every frame.

## Stage 4: Gestures and input

Goal: pan, zoom, rotate, pitch, fling, and double-tap that cooperate with parent
scroll containers, plus mouse, keyboard, and scroll input on 2-in-1 devices.

Questions:

- ArkUI gestures or raw XComponent touch events.
- Gesture priority, arbitration, and nested scrolling.
- How much of the MapLibre Compose interaction model to port: bindings,
  mappings, momentum, bearing snapping, haptics.

References:

- [MapLibre Compose interaction guide][compose-interaction] and its
  [interaction source][compose-interaction-src]
- ArkUI gestures: [binding][oh-gesture-binding],
  [combined gestures][oh-gesture-combined], [gesture judging][oh-gesture-judge],
  [multi-level gestures][oh-gesture-multi-level], [pan][oh-pan],
  [pinch][oh-pinch], [rotation][oh-rotation]
- [Scroll container][oh-scroll], for nested scrolling
- [FFI: handle events][ffi-handle-events]

## Stage 5: Imperative style API

Goal: read and change the loaded style: sources, layers, images, feature state,
and queries.

Questions:

- Handle lifetime across style reloads. In MapLibre Compose, a handle is null
  until the style is ready, and each loaded style publishes new handles.
- Errors, nulls, and logging, following section 3 of the
  [MapLibre Compose API guidelines][compose-api-guidelines].
- How GeoJSON and other bulk data cross the native boundary.
- Named style-spec values without literal types. MapLibre Compose's "open
  identity" pattern (a class with a private constructor and named instances)
  may carry over.

References:

- FFI guides: [add GeoJSON data][ffi-geojson], [add tile sources][ffi-tiles],
  [update data][ffi-update-data], [style layers by data][ffi-style-by-data],
  [set feature state][ffi-feature-state], [query a map][ffi-query-map],
  [query a source][ffi-query-source]
- MapLibre Compose: [handles][compose-composition],
  [styling][compose-styling], [images][compose-images],
  [features][compose-features], [clustering][compose-clustering]
- A warning from Flutter: in `maplibre_gl`, `setStyle()`
  [removes every layer the app added][flutter-maplibre-gl-styles]. The
  [`maplibre` package][flutter-maplibre] uses a style controller.

## Stage 6: Expressions

Goal: a typed way to write style expressions.

Questions:

- How much of MapLibre Compose's typed DSL survives without infix functions,
  operator overloading, extension functions, literal types, or conditional
  types.
- Structural equality on expressions, which stage 7 needs for cheap diffing.
- Serialization to style-spec JSON.

References:

- [MapLibre Compose expressions guide][compose-expressions] and its
  [expressions source][compose-expressions-src]
- [Style spec expressions][style-spec-expressions]
- [ArkTS migration rules][arkts-migration], especially the rules on generics,
  utility types, enums, and type predicates

## Stage 7: Declarative map content

Goal: apps declare sources and layers from app state. The library applies
changes, keeps content across style switches, controls order, and lets a
snapshotter use the same content.

MapLibre Compose does this with a custom composition
([how the map composes][compose-composition]). Approaches from other
ecosystems:

- Content as data, diffed by ID:
  - deck.gl [layers][deckgl-using-layers] and
    [`updateTriggers`][deckgl-layer]
  - Mapbox [declarative map styling][mapbox-declarative], where each call
    replaces the whole content, the library diffs it, and the same content
    works for snapshots; and [Mapbox in SwiftUI][mapbox-swiftui]
  - SwiftUI result builders, which produce value trees:
    [MapKit `MapContentBuilder`][apple-mapcontentbuilder],
    [Swift Charts][apple-charts], and [MapLibre's SwiftUI DSL][swiftui-dsl]
  - MapLibre GL JS [`setStyle` with diffing][gljs-setstyle]
    ([style source][gljs-style-src])
- Components that render nothing and use context and effects:
  - react-map-gl's [`Layer`][react-map-gl-layer]: it renders null, adds the
    layer again after `styledata`, compares props one key at a time, and orders
    layers with `beforeId` and `moveLayer`
  - [react-leaflet core architecture][react-leaflet],
    [svelte-maplibre][svelte-maplibre], [vue-maplibre-gl][vue-maplibre-gl], and
    [@rnmapbox/maps][rnmapbox]
- Retained objects with observable properties:
  - ArkUI V2 observation in plain classes ([@ObservedV2][oh-observedv2],
    [@Monitor][oh-monitor])
  - ArkGraphics 3D, Huawei's own native scene graph
    ([overview][oh-graphics3d], [scenes][oh-graphics3d-scene])
- Imperative create and update closures:
  [`UIViewRepresentable`][apple-uiviewrepresentable] and
  [`RealityView`][apple-realityview]
- Full custom reconcilers, for contrast: [react-three-fiber][r3f],
  [Google Maps Compose][android-maps-compose], and React Native for
  OpenHarmony, which drives ArkUI's C API from React
  ([architecture][rnoh-arch], [C API move][rnoh-capi])

ArkUI behavior to prototype before choosing:

- [`@Builder`][oh-builder] and [`@BuilderParam`][oh-builderparam] semantics,
  and whether [`@Consumer`][oh-provider-consumer] inside `@BuilderParam` content
  resolves to the map's `@Provider`
- Components whose `build()` draws nothing
- Order of `aboutToAppear` when content is inserted conditionally
- [BuilderNode][oh-buildernode] ([API][oh-buildernode-api]) building a tree
  that isn't on screen, as a stand-in for a separate composition
- [ForEach][oh-foreach] key semantics
- `@Computed` getters that return arrays, and the cost of rebuilding them

## Stage 8: Ornaments and overlays

Goal: compass, scale bar, attribution, logo, and zoom buttons, plus ArkUI
components placed at geographic positions.

Questions:

- How apps style ornaments. Huawei's guidance for wrapper components is to
  accept an `AttributeModifier` for each inner part.
- Whether styled controls live in a separate package.
- Dark mode and resources.
- Drawing ArkUI content over a `SURFACE` XComponent.

References:

- MapLibre Compose: [controls guide][compose-controls],
  [overlay source][compose-overlay-src], [Material 3 module][compose-material3]
- AttributeModifier: [guide][oh-attributemodifier-guide],
  [reference][oh-attributemodifier-ref], [FAQ][oh-attributemodifier-faq]
- Component wrapping best practices, as community write-ups
  ([CSDN][csdn-component-wrapping], [SegmentFault][sf-component-wrapping]), and
  Huawei's [dynamic component creation][hw-dynamic-creation]
- [ContentSlot][oh-contentslot-ref] ([guide][oh-contentslot-guide]),
  [FrameNode][oh-framenode], and [NDK custom components][oh-ndk-custom], for
  mixing native and ArkTS nodes
- Map Kit's [custom info window][hw-mapkit], a `@BuilderParam`
- [Dark and light color adaptation][oh-dark-light] and
  [resource categories][oh-resources]

## Stage 9: Location

Goal: show the user's location and let the camera follow it.

References:

- [MapLibre Compose location guide][compose-location] and its
  [HMS location runtime][compose-location-hms]
- Location Kit: [introduction][oh-location-intro],
  [guidelines][oh-location-guidelines]
- [Requesting user authorization][oh-request-permission]

## Stage 10: Requests, offline, snapshots, logging, terrain

Goal: the remaining engine features of MapLibre Compose.

References:

- FFI guides: [intercept network requests][ffi-requests],
  [work offline][ffi-offline], [render a static image][ffi-static-image],
  [capture logs][ffi-logs]
- MapLibre Compose: [requests][compose-requests], [offline][compose-offline],
  [snapshotter][compose-snapshotter], [terrain][compose-terrain]

## Stage 11: Guidelines, documentation, and release

Goal: written API guidelines, a documentation site, and publication on ohpm.
Early previews can ship from any earlier stage.

Questions:

- Which parts of the [MapLibre Compose API guidelines][compose-api-guidelines]
  carry over. Known differences: the ArkTS style guide uses UPPER_SNAKE
  constants; `Partial<T>` is allowed but object spread isn't, which affects the
  options pattern; options are interfaces without methods; open structures are
  matched with `instanceof`.
- Package scope and naming on ohpm.
- Documentation comment conventions.

References:

- [ArkTS coding style guide][oh-arkts-style]
- [OpenHarmony API design specification v0.1][csdn-api-design-spec], from the
  API SIG (2022 trial version, republished)
- [arkui-api-design][arkui-api-design], an unofficial skill. It notes that the
  ArkUI SDK now declares APIs in both static and dynamic forms.
- [ohpm third-party guide][oh-ohpm-guide] and
  [publishing requirements][oh-forum-publish]
- [awesome-harmony-library][awesome-harmony], to compare popular packages

## Later

- **Android and iOS through ArkUI-X.** ArkUI-X 5.0.4 added cross-platform
  XComponent, and 6.0.x tracks API 20. It would need runtime payloads for
  ArkUI-X on Android and iOS. Community reports describe slow maintenance and
  API gaps. ([GitCode][arkuix], [docs][arkuix-docs],
  [6.0.0 release][arkuix-600], [overview][arkuix-overview])
- **Static ArkTS.** Find out what the SDK's static and dynamic declaration
  split means for third-party HARs.
- **Native components.** Use ContentSlot and the NDK node API if hosting from
  ArkTS limits performance.
- **Compose on HarmonyOS.** [ovCompose][ovcompose] and [KuiklyUI][kuikly] run
  Compose Multiplatform on HarmonyOS with a custom Kotlin/Native target. That
  is another path for MapLibre Compose, and could share the native layer.
- **OpenHarmony devices.** They have no Map Kit, so MapLibre fills a gap there.

## Other maps on HarmonyOS

All of these are imperative controller APIs:

- [Map Kit `MapComponent`][hw-mapkit] (HarmonyOS only)
- [AMap][amap], [Baidu Maps][bdmap], and [Tencent Maps][tencentmap] on ohpm

[amap]: https://ohpm.openharmony.cn/#/cn/detail/@amap%2Famap_lbs_map3d
[android-maps-compose]: https://github.com/googlemaps/android-maps-compose
[apple-charts]: https://developer.apple.com/documentation/charts
[apple-mapcontentbuilder]: https://developer.apple.com/documentation/mapkit/mapcontentbuilder
[apple-realityview]: https://developer.apple.com/documentation/realitykit/realityview
[apple-uiviewrepresentable]: https://developer.apple.com/documentation/swiftui/uiviewrepresentable
[arkts-migration]: https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/typescript-to-arkts-migration-guide.md
[arkui-api-design]: https://gitcode.com/openharmony-skills/arkui-api-design
[arkuix]: https://gitcode.com/arkui-x
[arkuix-600]: https://zhuanlan.zhihu.com/p/1987439206830732324
[arkuix-docs]: https://github.com/arkui-x/docs
[arkuix-overview]: https://cloud.tencent.com/developer/article/2544591
[awesome-harmony]: https://github.com/Madixin/awesome-harmony-library
[bdmap]: https://ohpm.openharmony.cn/#/cn/detail/@bdmap%2Fmap
[compose]: https://maplibre.org/maplibre-compose/
[compose-api-guidelines]: https://maplibre.org/maplibre-compose/api-guidelines/
[compose-camera]: https://maplibre.org/maplibre-compose/camera/
[compose-clustering]: https://github.com/maplibre/maplibre-compose/blob/main/docs/src/content/docs/clustering.mdx
[compose-composition]: https://maplibre.org/maplibre-compose/composition/
[compose-controls]: https://maplibre.org/maplibre-compose/controls/
[compose-demo]: https://github.com/maplibre/maplibre-compose/tree/main/demo-app
[compose-expressions]: https://maplibre.org/maplibre-compose/expressions/
[compose-expressions-src]: https://github.com/maplibre/maplibre-compose/tree/main/lib/maplibre-compose/src/commonMain/kotlin/org/maplibre/compose/expressions
[compose-features]: https://github.com/maplibre/maplibre-compose/blob/main/docs/src/content/docs/features.mdx
[compose-images]: https://maplibre.org/maplibre-compose/images/
[compose-interaction]: https://maplibre.org/maplibre-compose/interaction/
[compose-interaction-src]: https://github.com/maplibre/maplibre-compose/tree/main/lib/maplibre-compose/src/commonMain/kotlin/org/maplibre/compose/interaction
[compose-location]: https://maplibre.org/maplibre-compose/location/
[compose-location-hms]: https://github.com/maplibre/maplibre-compose/tree/main/lib/location-runtime-hms
[compose-material3]: https://github.com/maplibre/maplibre-compose/tree/main/lib/maplibre-compose-material3
[compose-offline]: https://maplibre.org/maplibre-compose/offline/
[compose-overlay-src]: https://github.com/maplibre/maplibre-compose/tree/main/lib/maplibre-compose/src/commonMain/kotlin/org/maplibre/compose/overlay
[compose-presentation]: https://maplibre.org/maplibre-compose/presentation/
[compose-requests]: https://maplibre.org/maplibre-compose/requests/
[compose-snapshotter]: https://maplibre.org/maplibre-compose/snapshotter/
[compose-styling]: https://maplibre.org/maplibre-compose/styling/
[compose-terrain]: https://github.com/maplibre/maplibre-compose/blob/main/docs/src/content/docs/terrain.mdx
[csdn-api-design-spec]: https://blog.csdn.net/benco1986/article/details/145205715
[csdn-component-wrapping]: https://blog.csdn.net/hzw2017/article/details/139444871
[deckgl-layer]: https://deck.gl/docs/api-reference/core/layer
[deckgl-using-layers]: https://deck.gl/docs/developer-guide/using-layers
[ffi]: https://maplibre.org/maplibre-native-ffi/
[ffi-50-plan]: https://github.com/maplibre/maplibre-native-ffi/issues/50#issuecomment-5150320863
[ffi-208]: https://github.com/maplibre/maplibre-native-ffi/issues/208
[ffi-525]: https://github.com/maplibre/maplibre-native-ffi/issues/525
[ffi-553]: https://github.com/maplibre/maplibre-native-ffi/pull/553
[ffi-attach-render-target]: https://maplibre.org/maplibre-native-ffi/guides/attach-a-render-target/
[ffi-binding-spec]: https://maplibre.org/maplibre-native-ffi/development/binding-specification/
[ffi-concepts]: https://maplibre.org/maplibre-native-ffi/concepts/
[ffi-create-map]: https://maplibre.org/maplibre-native-ffi/guides/create-a-map/
[ffi-example-android]: https://github.com/maplibre/maplibre-native-ffi/tree/main/examples/android-map
[ffi-example-compose]: https://github.com/maplibre/maplibre-native-ffi/tree/main/examples/compose-map
[ffi-feature-state]: https://maplibre.org/maplibre-native-ffi/guides/set-feature-state/
[ffi-geojson]: https://maplibre.org/maplibre-native-ffi/guides/add-geojson-data/
[ffi-handle-events]: https://maplibre.org/maplibre-native-ffi/guides/handle-events/
[ffi-load-style]: https://maplibre.org/maplibre-native-ffi/guides/load-a-style/
[ffi-logs]: https://maplibre.org/maplibre-native-ffi/guides/capture-logs/
[ffi-map-example-spec]: https://maplibre.org/maplibre-native-ffi/development/map-example-specification/
[ffi-mise-ohos]: https://github.com/maplibre/maplibre-native-ffi/blob/main/mise.ohos.toml
[ffi-move-camera]: https://maplibre.org/maplibre-native-ffi/guides/move-the-camera/
[ffi-offline]: https://maplibre.org/maplibre-native-ffi/guides/work-offline/
[ffi-query-map]: https://maplibre.org/maplibre-native-ffi/guides/query-a-map/
[ffi-query-source]: https://maplibre.org/maplibre-native-ffi/guides/query-a-source/
[ffi-readme]: https://github.com/maplibre/maplibre-native-ffi#readme
[ffi-render-loop]: https://maplibre.org/maplibre-native-ffi/guides/run-the-render-loop/
[ffi-requests]: https://maplibre.org/maplibre-native-ffi/guides/intercept-network-requests/
[ffi-static-image]: https://maplibre.org/maplibre-native-ffi/guides/render-a-static-image/
[ffi-style-by-data]: https://maplibre.org/maplibre-native-ffi/guides/style-layers-by-data/
[ffi-tiles]: https://maplibre.org/maplibre-native-ffi/guides/add-tile-sources/
[ffi-update-data]: https://maplibre.org/maplibre-native-ffi/guides/update-data/
[flutter-maplibre]: https://pub.dev/packages/maplibre
[flutter-maplibre-gl-styles]: https://maplibre.org/flutter-maplibre-gl/concepts/styles/
[gljs-setstyle]: https://maplibre.org/maplibre-gl-js/docs/API/classes/Map/#setstyle
[gljs-style-src]: https://github.com/maplibre/maplibre-gl-js/blob/main/src/style/style.ts
[hw-dynamic-creation]: https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-ui-dynamic-operations
[hw-mapkit]: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/map-mapcomponent
[hw-modular-design]: https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-modular-design
[hw-multi-device]: https://developer.huawei.com/consumer/cn/doc/doccenter-multi-device/bpta-multi-device-overview
[hw-state-best-practices]: https://www.cnblogs.com/strengthen/p/18498287
[kuikly]: https://github.com/Tencent-TDS/KuiklyUI
[libpag]: https://github.com/Tencent/libpag
[mapbox-declarative]: https://docs.mapbox.com/ios/maps/guides/styles/declarative-map-styling/
[mapbox-swiftui]: https://docs.mapbox.com/ios/maps/guides/swift-ui/
[native-4315]: https://github.com/maplibre/maplibre-native/pull/4315
[oh-addmonitor]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-addMonitor-clearMonitor.md
[oh-attributemodifier-faq]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-attribute-modifier-faq.md
[oh-attributemodifier-guide]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-user-defined-extension-attributeModifier.md
[oh-attributemodifier-ref]: https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-attribute-modifier.md
[oh-arkts-perf]: https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/arkts-high-performance-programming.md
[oh-arkts-style]: https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/arkts-coding-style-guide.md
[oh-builder]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-builder.md
[oh-builderparam]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-builderparam.md
[oh-buildernode]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-user-defined-arktsNode-builderNode.md
[oh-buildernode-api]: https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/js-apis-arkui-builderNode.md
[oh-component-lifecycle]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-page-custom-components-lifecycle.md
[oh-componentv2]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-componentV2.md
[oh-computed]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-computed.md
[oh-contentslot-guide]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/rendering-control/arkts-rendering-control-contentslot.md
[oh-contentslot-ref]: https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-components-contentSlot.md
[oh-dark-light]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/ui-dark-light-color-adaptation.md
[oh-event]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-event.md
[oh-foreach]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/rendering-control/arkts-rendering-control-foreach.md
[oh-forum-publish]: https://forums.openharmony.cn/forum.php?mod=viewthread&tid=397
[oh-framenode]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-user-defined-arktsNode-frameNode.md
[oh-gesture-binding]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-gesture-events-binding.md
[oh-gesture-combined]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-gesture-events-combined-gestures.md
[oh-gesture-judge]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-gesture-events-gesture-judge.md
[oh-gesture-multi-level]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/arkts-gesture-events-multi-level-gesture.md
[oh-graphics3d]: https://github.com/openharmony/docs/blob/master/en/application-dev/graphics3d/arkgraphics3D-overview.md
[oh-graphics3d-scene]: https://github.com/openharmony/docs/blob/master/en/application-dev/graphics3d/arkgraphics3D-scene.md
[oh-har]: https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/har-package.md
[oh-har-to-hsp]: https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/har-to-hsp.md
[oh-location-guidelines]: https://github.com/openharmony/docs/blob/master/en/application-dev/device/location/location-guidelines.md
[oh-location-intro]: https://github.com/openharmony/docs/blob/master/en/application-dev/device/location/location-kit-intro.md
[oh-monitor]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-monitor.md
[oh-mvvm-v2]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-mvvm-V2.md
[oh-napi-guidelines]: https://github.com/openharmony/docs/blob/master/en/application-dev/napi/napi-guidelines.md
[oh-napi-thread-safety]: https://github.com/openharmony/docs/blob/master/en/application-dev/napi/use-napi-thread-safety.md
[oh-ndk-custom]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/ndk-build-custom-components.md
[oh-observedv2]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-observedV2-and-trace.md
[oh-ohpm-guide]: https://github.com/openharmony/docs/blob/master/en/third-party-components/ohpm-third-party-guide.md
[oh-pan]: https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-gestures-pangesture.md
[oh-param]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-param.md
[oh-pinch]: https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-gestures-pinchgesture.md
[oh-provider-consumer]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-new-provider-and-consumer.md
[oh-publish-blog]: https://www.cnblogs.com/openharmony/p/17829637.html
[oh-request-permission]: https://github.com/openharmony/docs/blob/master/en/application-dev/security/AccessToken/request-user-authorization.md
[oh-resources]: https://github.com/openharmony/docs/blob/master/en/application-dev/quick-start/resource-categories-and-access.md
[oh-rotation]: https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-gestures-rotationgesture.md
[oh-scroll]: https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-container-scroll.md
[oh-state-overview]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-state-management-overview.md
[oh-uiability-lifecycle]: https://github.com/openharmony/docs/blob/master/en/application-dev/application-models/uiability-lifecycle.md
[oh-unittest]: https://github.com/openharmony/docs/blob/master/en/application-dev/application-test/unittest-guidelines.md
[oh-v1-v2-migration]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-v1-v2-migration.md
[oh-xcomponent]: https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-xcomponent.md
[oh-xcomponent-guide]: https://github.com/openharmony/docs/blob/master/en/application-dev/ui/napi-xcomponent-guidelines.md
[ohpm]: https://ohpm.openharmony.cn/
[oniro]: https://github.com/eclipse-oniro4openharmony/device_board_oniro
[ovcompose]: https://github.com/Tencent-TDS/ovCompose-sample
[r3f]: https://github.com/pmndrs/react-three-fiber
[react-leaflet]: https://react-leaflet.js.org/docs/core-architecture/
[react-map-gl-layer]: https://github.com/visgl/react-map-gl/blob/master/modules/react-maplibre/src/components/layer.ts
[redplayer]: https://github.com/RTE-Dev/REDPlayer
[rnmapbox]: https://github.com/rnmapbox/maps
[rnoh-arch]: https://blog.csdn.net/qq_44924880/article/details/143364672
[rnoh-capi]: https://zhuanlan.zhihu.com/p/719918885
[sf-component-wrapping]: https://segmentfault.com/a/1190000046559869
[style-spec-expressions]: https://maplibre.org/maplibre-style-spec/expressions/
[svelte-maplibre]: https://github.com/dimfeld/svelte-maplibre
[swiftui-dsl]: https://github.com/maplibre/swiftui-dsl
[tencentmap]: https://ohpm.openharmony.cn/#/cn/detail/@tencentmap%2Fmap
[vue-maplibre-gl]: https://github.com/razorness/vue-maplibre-gl
