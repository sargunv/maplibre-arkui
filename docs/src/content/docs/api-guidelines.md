---
title: API guidelines
description: The conventions that the public API of @maplibre/arkui follows.
---

The conventions that `@maplibre/arkui`'s public API follows. The public API is
what `library/Index.ets` exports. These describe the code as it is; when a rule
doesn't fit a new case, change the rule in the same change rather than make an
exception. The priorities behind them are in
[ROADMAP.md](https://github.com/sargunv/maplibre-arkui/blob/main/ROADMAP.md)'s
guiding ideas: simple code, ArkUI idiom over MapLibre Compose's shape, state
management V2 only, and FFI's API where it already reads as ArkTS.

## Naming

- Components are `@ComponentV2` structs named with nouns that start with `Map`:
  `MapLibreMap`, `MapMarker`, `MapCompass`, `MapScaleBar`, `MapAttribution`,
  `MapZoomButtons`.
- A handle that the app creates and passes to a component is a class named
  `<Thing>Controller`, passed as `controller`, as ArkUI's `Scroller`,
  `TextController`, and `XComponentController` are: `MapController`.
- Settings are interfaces named `<Thing>Options`, after what they configure,
  with optional fields only, and taken as object literals:
  `MapControllerOptions`, `MapGestureOptions`, `FollowUserLocationOptions`,
  `SnapshotOptions`. Data that describes something is a plain noun with the
  fields it needs: `MapContent`, `MapSource`, `MapLayer`, `MapImage`.
- Events are `@Event` params named `on` and what happened: `onStyleLoaded`,
  `onCameraIdle`, `onMapError`, and `onGestureStart` / `onGestureEnd`, as
  ArkUI's `onScrollStart` / `onScrollStop` pair.
- A flag that shows an ornament ends in `Enabled` (`compassEnabled`), and other
  flags are adjectives or the names of what they turn on (`alwaysShown`,
  `cooperative`, `rotate`).
- Functions are verbs or the noun they make: `snapshot()`, `readPixelMap()`,
  `getDefaultRuntime()`, `addRuntimeEventListener()`. Expression functions take
  their operator's name in camelCase (`featureState`), with words for symbols
  (`eq`, `add`) and `cases` for the reserved `case`; operators without arguments
  are functions too (`zoom()`).
- Enum members are lowerCamelCase (`ScaleBarUnits.metric`), as FFI's are
  (`CameraUpdateMode.fly`), so an app sees one style. Internal constants are
  UPPER_SNAKE_CASE (`TAP_SLOP`), as the ArkTS style guide says; there are no
  public constants.
- Acronyms are words in code (`GeoJsonFeature`, `LatLng`), and spelled as usual
  in prose (GeoJSON). Where the style spec has a term, use it: `bearing`,
  `pitch`, `sourceLayer`, `minZoom`.
- Screen distances are vp, the map's logical pixels, unless a name says
  otherwise; durations end in `Ms` (`durationMs`); angles are degrees.
- Re-exported FFI declarations keep FFI's names, except FFI's `Camera`, which is
  `CameraPosition`: ArkUI reserves `Camera` for a built-in component.

## State

- Components use state management V2 only: `@Param` for inputs, with a default
  or `@Require`; `@Once` for the inputs that `MapLibreMap` binds to at creation
  (`controller`, `runtime`), while components that only read a controller take
  it as a `@Require @Param`; `@Event` for callbacks, with a no-op default;
  `@BuilderParam` for trailing-closure content, named for what it holds
  (`MapLibreMap.overlays`, since `content` is what the map draws, and
  `MapMarker.content`); `@Local` for the component's own state. No V1
  decorators, no AppStorage or LocalStorage.
- A component follows a `@Param` change with `@Monitor`, which hands the new
  value to the imperative layer (`MapView`). Every declarative input has an
  imperative operation under it.
- Controllers are `@ObservedV2` classes. `@Trace` goes only on state an app
  shows: `camera` (where the camera rests), `styleLoaded`, `attributions`, and
  `followingUserLocation`. The map sets them; apps read them.
- Values that change every frame live in one private traced field, the frame's
  view, read through `frameCamera` and the projection methods. Components read
  them in `@Computed` getters (`MapMarker.point`, `MapCompass.bearing`), so
  per-frame work stays in the components that ask for it.
- Data passed to a component is a value, not observed inside: `MapContent`,
  `MapGestureOptions`, `userLocation`. A new value is a change; the component
  compares it with the last one (content by ID, then by JSON or reference).

## FFI: wrap or re-export

- Re-export from `Index.ets` every FFI type that the API takes or returns, and
  the FFI API that apps call directly (the style API's types, request handlers,
  offline regions, events, and logs), so an app imports only `@maplibre/arkui`.
- Expose FFI's handles where apps need more than the library wraps:
  `MapController.runtime`, `map`, and `renderSession`, documented with what not
  to do to them (release them, change the style through them).
- Wrap only where ArkUI needs what FFI can't give: a component and its lifecycle
  (`MapLibreMap`), observable state (`MapController`), ArkUI and Kit types
  (`PixelMap` in `readPixelMap()` and `snapshot()`, Location Kit's `Location`),
  ownership that FFI gives one caller (the runtime's event handler, shared
  through `addRuntimeEventListener()`, and each map's event mask, the union of
  the map events that the listeners ask for), declarative data (`MapContent`),
  and types that strict ArkTS needs for literals (GeoJSON, expressions).
- A wrapper names the FFI call it makes and doesn't repeat FFI's docs.

## Errors

- Work that finishes later returns a promise. A camera move resolves with its
  `CameraTransitionOutcome` however it ends (`completed`, `cancelled`,
  `replaced`, `closed`), since being stopped is not an error. It rejects when it
  can't start: no map shows the controller, or the map rejects the change (FFI's
  `MaplibreError`).
- A call that correct code never makes throws an `Error` whose message names the
  rejected value (`readPixelMap()` with an unsupported pixel format).
- A read that can't answer yet returns `undefined` rather than throwing:
  `getCamera()`, `frameCamera`, `pixelForLatLng()`, `map`, `renderSession`.
- Failures while the map runs, which have no caller to reject, go to
  `onMapError` and to the log with a `MapLibre:` prefix: a style that fails to
  load, a frame that fails to render, content the map rejects. Rejected content
  stays out until it changes; the rest applies.
- A runtime event listener that throws is logged, and the other listeners still
  get the event. An `onMapError` handler that throws is logged too, and the map
  goes on.
- A promise that the library starts and nobody awaits ends in a `.catch()` that
  logs.

## Async and lifecycle

- A component owns the FFI objects it creates: `MapLibreMap` creates its map and
  render session as it appears and releases them as it disappears. A controller
  outlives its maps and keeps the camera between them.
- The library creates the default runtime on first use and keeps it for the
  app's life; an app that passes its own runtime owns it.
- FFI's map is usable once its `ready` settles, so the controller exposes it
  only after that.
- FFI commands whose order matters are awaited one at a time
  (`ContentReconciler`), not pipelined. Commands whose result doesn't matter use
  FFI's `discarding` form.
- Callbacks and events run on the ArkTS main thread, where FFI delivers them.

## Strict ArkTS

- Strict ArkTS takes an object literal only for a declared type, so the API
  declares an interface for every literal an app writes (options, `MapContent`,
  GeoJSON). Interfaces for literals have no methods; a callback is a
  function-typed field (`LayerPredicate`).
- Style-spec JSON is `Record<string, Object>` with quoted keys, and each nested
  object goes in a variable of its own type.
- No structural typing: open unions are matched by a `kind` field (FFI's
  results) or `instanceof` (`Expression`). An open style-spec name is a `string`
  (`MapLayer.type`); a closed GeoJSON tag is a string-literal type
  (`type: 'Feature'`).
- No spread or destructuring: copy fields by name
  (`MapController.transition()`).
- Import `@ohos.*` modules, not `@kit.*`.

## Doc comments

- Every export and public member has a `/** */` comment. Its first sentence says
  what the declaration is or does; the rest states defaults, units, when it's
  observable, and what rejects or throws.
- Comments are prose: code in backticks, functions with parentheses
  (`getCamera()`), no JSDoc tags (`@param`, `@returns`, `{@link}`). Add an
  ` ```ets ` example where the usage isn't plain from the signature.
- A public member that only the library should call, because ArkTS has no
  package-private members, starts its comment with "Internal:".
- Internal code uses `//` comments that say why.
- The documentation's examples are regions of the demo's `ets/docs/`, which the
  demo build compiles and the site build cuts out by name. `mise run check`
  matches the READMEs' examples against those files.

## Compared with MapLibre Compose

These carry over from the
[MapLibre Compose API guidelines](https://maplibre.org/maplibre-compose/api-guidelines/):
nouns for types and verbs for functions; acronyms as words; style-spec terms;
operators without arguments as functions; the same names for the same things
across related calls; no answer as `undefined` (Compose's `null`), not an
exception; unsurprising behavior over documented surprises; and docs that state
the contract.

These don't:

- Constants and enum entries: Compose uses PascalCase; this library follows
  FFI's lowerCamelCase enums and the ArkTS style guide's UPPER_SNAKE_CASE for
  internal constants.
- Types that may grow: Compose picks among enums, value classes, and sealed
  types with internal subtypes. ArkTS has no value classes, sealed types, or
  internal constructors, so open names are strings and FFI's results are
  `kind`-tagged unions.
- Options: Compose uses data classes with private constructors and builders, so
  adding an option can't break a constructor. Here options are interfaces of
  optional fields, where a new optional field breaks nothing.
- Compose's composable rules (`Modifier` first, `remember*`, `XState` holders,
  `CompositionLocal`, `@Stable`) map to ArkUI's own idioms above: attributes on
  the component, a controller the app creates, `@Param` / `@Event`, and
  `@ObservedV2`.
- Compose throws feature exceptions (`MapSnapshotException`); this library
  rejects promises with FFI's or plain errors, and reports the rest to
  `onMapError`.
- Platform prefixes, `@IntroducedAt`, and stability annotations have no use here
  yet: there is one platform, and the API is a preview.

## Follow-ups from the audit

The audit for the first preview fixed small gaps (missing docs on content,
marker, and ornament members; `{@link}` tags; `FollowLocationOptions`, now
`FollowUserLocationOptions`). These are larger:

- `MapController` has public methods that only the map calls (`attach()`,
  `detach()`, `showFrame()`, `followCamera()`), marked "Internal:". A
  module-private registry could hide them.
- The ornaments' accessibility labels are English until the HAR has resources.
- Open names that are plain strings (`MapLayer.type`, `GeoJsonGeometry.type`)
  could become string-literal unions once static ArkTS is checked; see
  ROADMAP.md, Next.
- Errors are plain `Error`s with messages; an app can't tell "no map on screen"
  from other rejections except by message. A named error, if apps need it.
