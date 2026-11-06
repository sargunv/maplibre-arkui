# maplibre-arkui

An ArkUI library for MapLibre Native on HarmonyOS and OpenHarmony, built on the
ArkTS bindings of MapLibre Native FFI. `ROADMAP.md` is the plan; its guiding
ideas set the priorities.

## Project map

```
library/                 @maplibre/arkui, a source HAR
  Index.ets              the public API: only what this exports is public
  oh-package.json5       name, version, API floor (20), FFI dependency, and
                         the metadata ohpm shows
  README.md              the ohpm page: install, quick start, and links to the
                         site
  CHANGELOG.md           a section per version, which pack-har.sh requires
  src/main/ets/
    Expressions.ets      style expressions: functions that build style-spec JSON
    GeoJson.ets          GeoJSON types, so ArkTS can write GeoJSON literals
    StyleImage.ets       readPixelMap(): a PixelMap as FFI's style image
    Content.ets          MapContent (sources, layers, images as data), the
                         reconciler that applies it to each style a map loads,
                         and loadStyle()
    MapLibreMap.ets      the map component: params, events, lifecycle
    MapController.ets    the app's handle: observable camera, camera methods,
                         FFI handles
    MapView.ets          the XComponent controller that owns the FFI map and
                         render session (internal)
    gestures.ets         gesture options, and the recognizer that turns touch,
                         wheel, and keys into camera deltas and momentum
    MapMarker.ets        ArkUI content pinned to a coordinate
    Ornaments.ets        the compass, scale bar, attribution, and zoom buttons
    location.ets         the user location's indicator layer and its images,
                         and where a following camera moves
    runtime.ets          the default runtime and its cache file, the frame
                         pacer, and per-runtime event dispatch to maps and app
                         listeners
    Snapshot.ets         snapshot(): a still image of a map, as a PixelMap
    log.ets              logError(), which every library log message goes
                         through, after a `MapLibre:` prefix
  src/main/module.json   the HAR's module manifest
  src/ohosTest/          the hypium suite, a test HAP in DevEco's layout
    ets/test/            the cases; List.test.ets registers them, helpers.ets
                         holds what they share
    ets/testability/     the test ability, the page, and TestMaps.ets: the
                         page's map, its reset(), and the frame waits
demo/entry/src/main/     the demo app's only module (module.json holds the app's
                         fields too, as FFI's ArkUI example does): a map with
                         camera buttons, a page with two maps, a map in a
                         Scroll, a runtime page (RuntimeDemo.ets) with a
                         snapshot, a resource transform, and an offline region,
                         a style page (StyleDemo.ets)
                         whose content comes from its state, with a snapshot
                         of it and queries on tap, and a location page
                         (LocationDemo.ets) with Location Kit and a simulated
                         walk
  ets/pages/common.ets   the style URLs and the panel look the pages share
  ets/docs/              the documentation's examples, as `// #region`s:
                         QuickStart.ets (a page of its own) and Examples.ets
                         (a page of tabs)
scripts/                 the build, pack, FFI, and device scripts the tasks run
docs/                    the documentation site: Astro with Starlight, a pnpm
                         package of its own, for GitHub Pages
  astro.config.mts       the site's base path and sidebar
  src/content/docs/      the pages; api-guidelines.md holds the public API's
                         conventions
  src/snippets.ts        region(): cuts a page's example out of ets/docs/
  src/components/Api.astro  <Api of="Name" />: a link into the API reference
  scripts/               the API reference's pipeline (see docs:api)
  typedoc.config.mjs     TypeDoc's options for the reference
docs/ffi-feedback.md     FFI gaps and bugs found here, for upstream
README.md                a stub: what the library is, install, quick start, and
                         a link to the site
build/                   outputs (gitignored): ffi/, har/, demo/<abi>/,
                         test/<abi>/, and docs/ (the reference's declarations)
.proof/                  screenshots and logs of runs (gitignored)
```

## Dev tool commands

Run `mise install` once. It installs the OpenHarmony SDK (about 4 GB) and the
Oniro emulator image (1.4 GB), which no other command installs on its own. The
SDK comes through the [mise-ohos-sdk](https://github.com/sargunv/mise-ohos-sdk)
plugin that `[plugins]` in `mise.toml` pins, which unpacks it with the host's
`python3` and puts only `hdc` on PATH. The scripts use `perl` and `unzip`.

- `mise run check` / `mise run fix`: formatters and linters through hk, and
  `scripts/check-doc-examples.sh`, which checks that each `ets` block of the
  READMEs is in the demo's `ets/docs/`. They install the site's packages first,
  since dprint formats its `.mdx` pages with the site's mdxlint.
- `mise run docs:build` / `mise run docs:dev`: build the documentation site into
  `docs/dist`, or serve it with live reload. `mise run docs:preview` serves the
  build. Each runs `docs:api` first, which needs the SDK and `build/ffi`: the
  SDK's TypeScript fork emits the library's declarations
  (`docs/scripts/emit-declarations.mjs`), a rewrite turns structs into classes
  and decorators into TypeDoc badges, `docs/scripts/ffi-reference.mjs` links
  FFI's re-exports to FFI's TypeDoc, and TypeDoc writes `docs/public/api`.
- `mise run ffi:download`: fetch the FFI packages that FFI's CI packed at
  `vars.ffi_commit` into `build/ffi`. Needs `gh` signed in.
- `FFI_DIR=<checkout> mise run ffi:pack [preset]`: pack them from an FFI
  checkout instead (default preset `ohos-x64-egl`, for the Oniro emulator;
  `ohos-arm64-egl` for arm64 devices). Use it to try FFI changes; it warns when
  the checkout isn't at the pin.
- `mise run pack`: pack the library into `build/har/maplibre-arkui.har`.
- `mise run demo:build` / `mise run demo`: build the demo HAP into
  `build/demo/<abi>`, or build, install, and start it on this worktree's
  emulator (`--device <key>` for another device). The build takes `--abi x86_64`
  (the default, for the Oniro emulator and CI) or `--abi arm64-v8a`; `demo`
  reads the device's ABI with `scripts/device-abi.sh` and builds for it, so it
  runs on arm64 devices and DevEco Studio's emulator too.
- `mise run test:build` / `mise run test`: build the hypium suite into
  `build/test/<abi>`, with the same `--abi`, or build it for the device's ABI
  and run it on the emulator or `--device <key>`. It fails unless hypium reports
  every case passed. A run that ends without hypium's tally crashed, most likely
  in the Oniro emulator's llvmpipe (see `docs/ffi-feedback.md`), which isn't a
  reason to retry. The suite finishes on DevEco Studio's emulator, which has a
  GPU.
- `scripts/ohos-key.sh`: print this worktree's emulator key, booting it if
  needed. `devices-cli release` stops it. It runs `scripts/wake-device.sh`,
  which turns the screen on, keeps it on for a day, and swipes the lock screen
  away, since the emulator locks after it sleeps and `aa start` and the UI cases
  fail behind the lock screen. A device named with `--device` is left as it is.
  Don't run `power-shell suspend`: `hdc shell` hangs until the emulator is
  released.
- Screenshot:
  `hdc -t "$(scripts/ohos-key.sh)" shell snapshot_display -f /data/local/tmp/x.jpeg`,
  then `hdc -t ... file recv /data/local/tmp/x.jpeg .proof/x.jpeg`.

The build and device tasks need `build/ffi` from `ffi:download` or `ffi:pack`.

## How the build works

HAPs build without hvigor, whose packages have no clear license.
`scripts/build-hap.sh` adapts FFI's `examples/arkui/scripts/build-hap.sh` and
`tools/ohos/pack-hap`: ets-loader's webpack build compiles ArkTS, es2abc merges
the records, and `scripts/pack-hap.sh` packs and signs with the SDK's debug
keys. It takes the packages as ohpm would install them:

- The library HAR's sources join the module's `ets/`, and the module's imports
  of `@maplibre/arkui` become relative imports of them. The tests and the demo
  build against the packed HAR. The script ignores package dependencies, and the
  packed HAR still names FFI by its `file:` path in this repository, so ohpm
  can't install it into an app until FFI is on OHPM.
- JavaScript packages (FFI's facade, hypium) stay external and become records of
  their own. The backend supplies the native libraries.
- `scripts/ets-loader-patches.cjs` fixes two bugs in the webpack build for
  imported `@ComponentV2` structs and for source HAR records. A SDK update that
  changes the patched text stops the build with an error.

## FFI pin and CI

FFI isn't on OHPM in the form this library needs. `vars.ffi_commit` in
`mise.toml` names the FFI main commit to build against, and
`library/oh-package.json5` points at `build/ffi/native-ffi.har`. CI runs
`ffi:download`, which uses the `ohpm-packages-*` artifact of FFI's CI run for
that commit. FFI keeps those artifacts for 30 days and packs them only when
every target passes, so pick the newest main commit whose CI has the artifact,
and bump the pin within 30 days or CI breaks. Building FFI in CI instead would
mean building MapLibre Native, which is far slower.

CI (`.github/workflows/ci.yml`) runs `mise run check` and builds the HAR, the
demo HAP, the test HAP, and the documentation site. On pushes to `main`, its
`deploy-pages` job publishes the site to GitHub Pages, at
`https://sargunv.github.io/maplibre-arkui/`. It doesn't run the hypium suite,
which llvmpipe's crash makes fail most runs (ROADMAP.md, Next). CI hasn't run on
GitHub yet; if `ffi:download` gets a 403 because the job's token can't read
another repository's artifacts, give it a repository secret with a fine-grained
token that reads public repositories.

## Releasing

Nothing is published yet. `mise run pack` warns about what keeps the HAR off
ohpm. To publish:

1. Once FFI publishes `@maplibre/native-ffi` and its backends on OHPM, set the
   dependency in `library/oh-package.json5` to that exact version, such as
   `"@maplibre/native-ffi": "0.202612.0"`. FFI breaks its API in most releases,
   and the backend the app installs must match the facade, so pin it exactly,
   and tell apps that version in the READMEs' install line
   (`ohpm install @maplibre/arkui @maplibre/native-ffi-opengl@<version>`). Then
   `vars.ffi_commit` and `ffi:download` can give way to the published packages.
2. Set `version` and add its section to `library/CHANGELOG.md`.
3. `mise run pack`, then `ohpm prepublish build/har/maplibre-arkui.har` with
   DevEco's or the command-line tools' ohpm, which isn't part of this
   repository's toolchain. It warns that the HAR has source code, which a source
   HAR does. Then `ohpm publish build/har/maplibre-arkui.har`. OHPM lists the
   version after a review, which checks the README's install line.

## Project invariants

- Nothing is published, so the public API has no users to keep working. When a
  better name or shape appears, change it everywhere: no deprecations, aliases,
  or compatibility shims until the first release.
- State management V2 only (`@ComponentV2`, `@ObservedV2`/`@Trace`, `@Param`,
  `@Event`, `@Local`, `@Provider`/`@Consumer`, `@Monitor`, `@Computed`); no V1
  decorators. API floor 20, FFI's.
- Strict ArkTS. Import `@ohos.*` modules, not `@kit.*`, which the webpack build
  doesn't rewrite.
- No formatter understands `.ets`, so format it by hand in the style of the
  existing files (2 spaces, single quotes). The build enforces the ArkTS rules.
- `oh-package.json5` files stay plain JSON, which the scripts read with jq.
- Record FFI gaps and bugs in `docs/ffi-feedback.md` instead of working around
  them with complex code.
- Expressions are untyped and immutable, and FFI's style functions take an
  `Expression` as is, through its `toJSON()`. A new expression function gets a
  JSON case and a case that FFI's `StyleExpressionHandle` parses and evaluates
  in `Expressions.test.ets`.
- Import FFI's `Camera` type as `CameraPosition`; ArkUI reserves the name for a
  built-in component, and ets-loader rejects the import.
- The FFI map is usable only once `map.ready` settles: its snapshot throws
  before then. `MapView` exposes it to the controller only after that.
- Tests wait with frame callbacks, not timers. OpenHarmony's main thread can
  lose a timer's wakeup while nothing else wakes its event loop, which hangs a
  `setTimeout` poll.
- The webpack build's ESM tsconfig omits some built-in components, such as
  `NodeContainer`, `ContentSlot`, and `SymbolGlyph`, so `.ets` files can't use
  them yet. It also rejects `layoutGravity`. In a `ForEach` item, a built-in
  component fails to build, and a custom component with a trailing closure
  builds but silently loses that content; have the item call a `@Builder`.
- ets-loader only warns when code breaks the ArkTS rules, so `build-hap.sh`
  fails on the errors in its `ArkTSLinter_output.json`.
- The library owns each runtime's one FFI event handler and its maps' event
  masks. Code that needs a runtime's events, such as offline progress, uses
  `addRuntimeEventListener()`, with the map events it needs as flags, never
  `RuntimeHandle.setEventHandler()` or `MapHandle.setEventMask()`. A listener
  gets only the map events it asks for.
- Request handlers, offline regions, and logs are FFI's API, re-exported from
  `Index.ets`; wrap them only where ArkUI needs it.
- Test cases don't need the network, except the resource transform case, which
  rewrites a URL to a real style.
- Each ArkTS example of the documentation site is a `// #region <name>` of
  `demo/entry/src/main/ets/docs/`, which a page shows with
  `<Code code={region(examples, "<name>")} lang="ts" />`; the site build fails
  on a missing region. The READMEs keep only the quick start, in an `ets` block,
  which dprint leaves alone, that is lines of those files: change both together.
- The API reference comes from the doc comments of what `Index.ets` exports. A
  struct's members other than its params, and comments that start with
  "Internal:", stay out of it. FFI's re-exports link to FFI's reference rather
  than being documented here; link names in pages with `<Api of="Name" />`,
  which fails the build on a name the reference doesn't have.
- `docs/src/content/docs/api-guidelines.md` describes the public API as it is; a
  change that departs from it changes it too.
- The build has no resource table, so `.ets` files can't use `$r()`; load files
  from `resources/rawfile` with `getRawFileContentSync()`.
- The style and query API is FFI's, through `MapController.map` and
  `renderSession`; wrap a part of it only where ArkUI apps need more than the
  FFI types, which `Index.ets` re-exports. Style JSON in ArkTS is a
  `Record<string, Object>` literal with quoted keys, each nested object in a
  variable of its own, since ArkTS types an object literal only from a declared
  type.
- Per-frame state lives in one traced field, the controller's frame view, which
  the map sets from the render session's frame results. Read it through
  `frameCamera` and the projection methods, in `@Computed` getters where a
  component derives values from it.
- Ornaments use `sys.color.*` and `sys.media.*` resources so they follow dark
  mode; the HAR has no resources of its own yet.
- On the Oniro emulator, content that moves every frame over a map makes the
  llvmpipe crash likelier, so test cases turn on the scale bar, markers, and
  compass only while they need them, and the suites that need no map run before
  any suite shows it.
- Each suite that uses the test page's map calls `testMap.reset()` in its
  `beforeEach`, which loads the style afresh and turns every flag off, rather
  than undoing its changes in `afterEach` or `finally`. Shared helpers go in
  `test/helpers.ets`.
- The map's ArkUI gestures only claim touches; `MapGestures` moves the camera
  from the raw touches, and only after a claim. Keep camera math out of the
  gesture callbacks, except for input that has no touches (touchpad pinch). Each
  touch event moves one finger, and on HarmonyOS 6 the other fingers in its
  `touches` have wrong coordinates, so the recognizer reads positions from
  `changedTouches` only.
- Tests may import the library's internal files by path, such as
  `@maplibre/arkui/src/main/ets/gestures`; `build-hap.sh` rewrites those
  imports. `Gestures.test.ets` feeds the recognizer made-up touches, and
  `GestureInput.test.ets` injects real input with `@ohos.UiTest`'s `Driver`,
  which takes px: aim and time input in vp and convert, and measure the camera's
  motion in vp with the map's projection, so the cases hold at any density.
- The library declares no permission; a HAR's `requestPermissions` merge into
  every app that uses it. Location comes from the app as Location Kit's
  `geoLocationManager.Location`. The emulator's Location Kit has no fixes (the
  location switch is off), so tests and the demo make up locations.
- hypium's `assertClose` divides the difference by the actual value; compare
  with a tolerance through `expectNear()` in `test/helpers.ets` instead.
- Map content is data: `MapContent` goes to `MapLibreMap` and `snapshot()` as a
  value, and a new value is a change. `ContentReconciler` (internal) runs one
  pass at a time and awaits each FFI command, so its record of the style stays
  true; keep it that way rather than pipelining commands. It owns only what it
  added, by ID, and starts over on each style load.
- The map reads layer properties back normalized: colors as
  `["rgba", r, g, b, a]`, expressions wrapped in their type's coercion
  (`["to-color", ...]`), and unset properties as `undefined`. Tests compare
  against those forms.
