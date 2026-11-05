# maplibre-arkui

An ArkUI library for MapLibre Native on HarmonyOS and OpenHarmony, built on the
ArkTS bindings of MapLibre Native FFI. `ROADMAP.md` is the plan; its guiding
ideas set the priorities.

## Project map

```
library/                 @maplibre/arkui, a source HAR
  Index.ets              the public API: only what this exports is public
  oh-package.json5       name, version, API floor (20), FFI dependency
  src/main/ets/
    Expressions.ets      style expressions: functions that build style-spec JSON
    MapLibreMap.ets      the map component: params, events, lifecycle
    MapController.ets    the app's handle: observable camera, camera methods,
                         FFI handles
    MapView.ets          the XComponent controller that owns the FFI map and
                         render session (internal)
    runtime.ets          the default runtime, the frame pacer, and per-runtime
                         event dispatch
  src/main/module.json   the HAR's module manifest
  src/ohosTest/          the hypium suite, a test HAP in DevEco's layout
    ets/test/            the cases; List.test.ets registers them
    ets/testability/     the test ability and the page whose map cases drive
demo/entry/src/main/     the demo app's only module (module.json holds the app's
                         fields too, as FFI's ArkUI example does): a map with
                         camera buttons, and a page with two maps
scripts/                 the build, pack, FFI, and device scripts the tasks run
.mise/plugins/ohos-sdk/  mise plugin for the OpenHarmony SDK, identical to FFI's;
                         linked by scripts/link-ohos-sdk-plugin.sh
docs/ffi-feedback.md     FFI gaps and bugs found here, for upstream
build/                   outputs (gitignored): ffi/, har/, demo/, test/
.proof/                  screenshots and logs of runs (gitignored)
```

## Dev tool commands

Run `mise install` once. It installs the OpenHarmony SDK (about 4 GB) and the
Oniro emulator image (1.4 GB), which no other command installs on its own. The
SDK plugin unpacks with the host's `python3`, and the scripts use `perl` and
`unzip`.

- `mise run check` / `mise run fix`: formatters and linters through hk.
- `mise run ffi:download`: fetch the FFI packages that FFI's CI packed at
  `vars.ffi_commit` into `build/ffi`. Needs `gh` signed in.
- `FFI_DIR=<checkout> mise run ffi:pack [preset]`: pack them from an FFI
  checkout instead (default preset `ohos-x64-egl`, for the emulator). Use it to
  try FFI changes; it warns when the checkout isn't at the pin.
- `mise run pack`: pack the library into `build/har/maplibre-arkui.har`.
- `mise run demo:build` / `mise run demo`: build the demo HAP, or build,
  install, and start it on this worktree's emulator (`--device <key>` for
  another device).
- `mise run test:build` / `mise run test`: build the hypium suite, or build and
  run it on the emulator. It fails unless hypium reports every case passed.
- `scripts/ohos-key.sh`: print this worktree's emulator key, booting it if
  needed. `devices-cli release` stops it.
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
demo HAP, and the test HAP. CI hasn't run yet; if `ffi:download` gets a 403
because the job's token can't read another repository's artifacts, give it a
repository secret with a fine-grained token that reads public repositories. It
doesn't boot the emulator yet; FFI's CI does on runners with KVM, which is the
model for adding it.

## Project invariants

- State management V2 only (`@ComponentV2`, `@ObservedV2`/`@Trace`, `@Param`,
  `@Event`, `@Local`, `@Provider`/`@Consumer`, `@Monitor`, `@Computed`); no V1
  decorators. API floor 20, FFI's.
- Strict ArkTS. Import `@ohos.*` modules, not `@kit.*`, which the webpack build
  doesn't rewrite.
- No formatter understands `.ets`, so format it by hand in the style of the
  existing files (2 spaces, single quotes). ets-loader enforces the ArkTS rules
  when it builds.
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
  `NodeContainer` and `ContentSlot`, so `.ets` files can't use them yet.
