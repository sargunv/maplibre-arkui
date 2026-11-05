# MapLibre Native FFI feedback

Gaps, bugs, and rough edges in MapLibre Native FFI that this library hits, with
evidence and a suggested fix, so they can be fixed upstream before FFI's next
release. Each entry names the FFI commit it was seen at.

## Stage 1: project setup (FFI `5c4c9084`, `11ffaaf6`)

- **The ArkUI example's build can't compile V2 components across files or source
  HARs.** `examples/arkui/scripts/build-hap.sh` runs ets-loader's webpack build,
  and the example uses V1 state management in a single page, so it doesn't hit
  these. In SDK 6.1, that build (a) reads only `@Component` structs from
  imported files, so building an imported `@ComponentV2` struct fails with "does
  not meet UI component syntax"; (b) names the record of an import after the
  _last_ `src/main/ets` in its path but the record itself after the first, so a
  source HAR's `./src/main/ets/...` imports point at records that don't exist;
  and (c) compiles anything in `oh_modules` as CommonJS, which breaks ArkTS.
  This repository's `scripts/ets-loader-patches.cjs` fixes (a) and (b) with two
  string replacements while Node loads ets-loader, and `scripts/build-hap.sh`
  avoids (c) by copying a source HAR into the module's `ets/`. Suggested fix:
  move the example to state management V2 and adopt the same patches, or note
  the limits in the example's README.
- **A main commit's OHPM packages can be missing from CI.** The `package / ohpm`
  job needs every `target` job, so an unrelated failure skips it: run
  [42012958276] for `11ffaaf6` failed only `target / linux-gnu-loongarch64-egl`
  and uploaded no `ohpm-packages-*` artifact. Artifacts also expire after 30
  days. Downstream CI pins a commit and downloads that artifact, so the pin had
  to fall back to `5c4c9084`. Suggested fix: make the job need only the
  OpenHarmony targets, and publish the HARs with the nightly snapshots (as the
  `unstable-native-snapshot` release does for the native archives) so a pin
  doesn't expire.
- **The OpenHarmony SDK mise plugin can't be shared.** Other repositories have
  to copy `.mise/plugins/ohos-sdk`, as this one does, and
  `mise plugins link --force` is global, so each repository's hook relinks the
  plugin to its own copy. In stage 2, a link to a worktree that had been removed
  broke every SDK task here until it was relinked. Suggested fix: move it to a
  repository of its own and reference it from `[plugins]`, as its `metadata.lua`
  already anticipates.
- **The SDK plugin puts a broken `diff` on PATH.** `env_keys.lua` adds the SDK's
  `toolchains/` to PATH for `hdc`, and that directory also ships `diff`,
  `restool`, `idl`, and others. Its `diff` rejects `-r` and still exits 0, so
  `diff -r a b && echo same` prints `same` in an FFI `ohos` shell. Suggested
  fix, as this repository's copy does: link `hdc` into a `bin/` directory in
  `post_install.lua` and put only that on PATH.
- **Packed HAR names differ between CI and local packs.** CI names them
  `native-ffi-0.202601.0-dev.0.har` and `pack-ohpm` names them
  `native-ffi-0.0.0.har`, so consumers glob or rename them (`ffi-download.sh`,
  `ffi-pack.sh`). Minor; suggested fix: name the artifact's files without the
  version, or document the pattern in the TypeScript install guide.
- **hypium may not need the startup patch in a windowed test ability.** FFI
  patches hypium's startup timer with its test addon because the idle loop can
  lose the wakeup. This repository's suite runs hypium from a `TestAbility` that
  loads a page, as DevEco's ohosTest template does, with unpatched hypium
  1.0.29, and has passed every run so far. Worth trying in FFI's suite before
  keeping the patch. (Stage 2 found the lost wakeup in the cases themselves; see
  below.)
- **`pack-hap` needs Python only to edit the profile JSON.** `jq` does it, as in
  this repository's `scripts/pack-hap.sh`. Minor.
- **The emulator can reject the first launch after it boots.** Right after
  `devices-cli get ohos` boots the Oniro emulator, `aa start` failed once with
  error 10106102, "The device screen is locked during the application launch"; a
  second try succeeded. This is in devices-cli rather than FFI, which
  `tools/devices/ohos-key` shares. Suggested fix: have devices-cli wait until
  the lock screen is gone before it reports the device. (`power-shell suspend`
  to reproduce it hangs `hdc shell` until the emulator is released.)

## Stages 2 and 3: map component and camera (FFI `5c4c9084`)

- **ArkTS can't import the `Camera` type by its name.** ArkUI has a built-in
  `Camera` component, and ets-loader rejects
  `import { Camera } from '@maplibre/native-ffi'` in an `.ets` file with "The
  module name 'Camera' can not be the same as the inner component name". This
  library imports and re-exports it as `CameraPosition`. Suggested fix: note the
  alias in the TypeScript install guide's ArkTS section, or rename the type in
  the TypeScript binding (MapLibre Compose and Map Kit call it
  `CameraPosition`).
- **`MapHandle.getSnapshot()` throws before the map is ready, though `ready`'s
  doc says the map takes calls before then.** Reading the snapshot right after
  `RuntimeHandle.createMap()` threw
  `invalidState: map creation has not succeeded`. Commands queue, but the
  synchronous reads don't. Suggested fix: say in `ready`'s doc that
  `getSnapshot()` and other synchronous reads need it to settle first.
- **A runtime has one event handler, so maps that share a runtime need a
  dispatcher, and a library that sets it takes it from the app.**
  `RuntimeHandle.setEventHandler()` replaces the handler for the runtime and all
  its maps. This library shares one runtime between maps, so it sets the handler
  once and routes events by `event.source` (`runtime.ets`, about 20 lines); an
  app that passes its own runtime loses its handler. Suggested fix: a per-map
  event handler (the map already has its own event mask), or several handlers
  per runtime.
- **`MapHandle.setStyleJson()` stringifies its argument.** It takes `unknown`
  and passes it through `JSON.stringify` (`native/runtime.c`), so a style
  document held as text, as ArkUI apps get it from a rawfile or a param, has to
  be parsed first; passing the text would load a JSON string. This library calls
  `JSON.parse` first. Suggested fix: take a string as the document itself, or
  say in the doc that a string is a JSON value, not a document.
- **A style that fails to load reports an empty reason.** Loading
  `file:///nonexistent/style.json` raised `mapLoadingFailed` with the message
  `loading style failed: ` and nothing after the colon. Suggested fix: include
  the URL and the failure (not found, HTTP status) in the message.
- **OpenHarmony's lost timer wakeup also hangs test cases that poll.** A case
  that waited with a `setTimeout` loop hung for the whole 600 s run once the app
  went idle, the bug that FFI's `test/arkts/node/timers.ts` describes. Waiting
  with `UIContext.postFrameCallback()` works in a windowed test ability, with no
  native addon. Suggested fix: mention it in the ArkTS testing notes, since any
  downstream suite that polls hits it.
- **ets-loader's webpack build can't compile `NodeContainer` or `ContentSlot`.**
  In ESM mode it reads `tsconfig.esm.json`, whose list of built-in components
  lacks them and others that `tsconfig.json` has (`FolderStack`,
  `MovingPhotoView`, ...), so a page that uses one fails with "does not meet UI
  component syntax". FFI's example build has the same limit. Suggested fix: note
  it next to the example's other build limits; a build that needs them could
  pass ts-loader a config with the full list.
- **The ArkUI example's surface-replacement path doesn't run on the emulator.**
  On the Oniro emulator a `SURFACE` XComponent kept its surface when the app
  went to the background, behind a `Navigation` push, under `visibility(None)`,
  and when its `ComponentContent` left an overlay; `onSurfaceDestroyed` fired
  only when the component was destroyed. This library keeps the
  `releaseTarget()` and `setOhosSurfaceTarget()` handling, but can't test it
  there. Suggested fix: if FFI knows a trigger (a device that drops surfaces in
  the background, or a fold), name it in the window guide so downstream tests
  can reproduce it.
- **Maps crash the app on the Oniro emulator, more often the more maps run.**
  The process dies with `SIGSEGV(SEGV_MAPERR)` on a MapLibre render thread in
  the emulator's Mesa llvmpipe: `lp_scene_is_resource_referenced` <-
  `lp_setup_is_resource_referenced` <- `llvmpipe_flush_resource`, reached from
  `libmaplibre-native-c.so` through `glDrawElements`, `glTexSubImage2D`,
  `glClear`, or `ohos_create_image_from_native_buffer`. It reproduces with FFI
  alone: a copy of `examples/arkui` whose page shows N of the example's own
  `MapController` maps (each with its own runtime, pacer, and `coreWorker`
  session; FFI `5c4c9084` HARs, OpenHarmony 6.1.0.31 image) crashed within
  seconds in 3 of 3 starts with three maps, within 30 s in 4 of 8 starts with
  two, and in 1 of 5 starts with one. In this library's demo, the same crash
  came within three pushes of the two-map page over the first page's map (three
  sessions) in three runs, not at all in fifteen pushes of another run, and once
  with one map during a fly. The sessions use dedicated, unshared EGL contexts,
  and the process also runs ArkUI's own `RSRenderThread` on llvmpipe, so this
  looks like a llvmpipe race between contexts on different threads rather than a
  misuse in FFI, but it hasn't been checked on a device with a GPU. Suggested
  fix: try two maps on a device; if only the emulator crashes, report it to
  Oniro with these stacks and note in the OpenHarmony guide that the emulator
  can't run several maps (or many frames of one) reliably; if devices crash too,
  look at how the render threads share EGL state. The full fault logs are in the
  stage 2 worktree's gitignored `.proof/` (`ffi-repro-cppcrash-*.log`,
  `review-cppcrash*.log`).

## Stage 6: expressions (FFI `5c4c9084`, `11ffaaf6`)

- **`StyleExpressionHandle.evaluate` doesn't document the JSON of colors,
  formatted text, and images.** On the emulator, a color evaluates to
  `["rgba", r, g, b, a]` with channels from 0 to 255; formatted text to
  `["format", text, {options}, ...]` with its colors in that form; and an image
  to `{"available": true, "name": "park"}`. Colors also come back with float
  noise from MapLibre's premultiplied storage: `'#ff000080'` gives
  `["rgba",254.99998474121094,0,0,0.5]`, and an HCL interpolation from red to
  red gives `["rgba",254.99998474121094,0.00019044788496103138,...]`, so a test
  has to round. Suggested fix: document these shapes in
  `mln_style_expression_evaluate`, and round un-premultiplied channels that are
  within float error of an integer. The header on main (`11ffaaf6`) still says
  only that the result is JSON.
- **The first `hdc install` after a boot can fail.** On the emulator it failed
  with "code:301 error: user not exist", and a retry succeeded. Like the lock
  screen above, this is in devices-cli rather than FFI. Suggested fix: have
  devices-cli wait until the account service reports the user before it reports
  the device.

## Stage 10: requests, offline, snapshots, logs (FFI `5c4c9084`)

- **A relative `cachePath` creates a runtime whose cache can't open.** On the
  emulator, `RuntimeHandle.create({ cachePath: 'probe-cache.db' })` resolved,
  and then `createOfflineRegion()` rejected with
  `nativeError: unable to open database file`: an app's working directory isn't
  writable on OpenHarmony. The offline guide's snippet passes
  `"maplibre-cache.db"`. Suggested fix: use an app data directory in the snippet
  and say in `RuntimeOptions.cachePath` that it should be absolute; ideally,
  have `RuntimeHandle.create()` reject when it can't open the file. This
  library's default runtime uses `<filesDir>/maplibre-cache.db`.
- **Offline download progress needs the runtime's one event handler.** Progress,
  response errors, and the tile limit arrive only as runtime events, so a
  library that sets the handler for its maps (see stages 2 and 3) has to pass
  the runtime's own events on too. This library adds `addRuntimeEventListener()`
  for it (about 20 lines in `runtime.ets`). The same per-map or multi-handler
  fix would cover it; a per-region callback on `setOfflineRegionObserved()`
  would also suit apps.
- **The header transform is unsupported on OpenHarmony, and the network guide
  doesn't say so.** `setHttpHeaderTransform()` documents `Status.unsupported`
  there, but the guide's "Add headers" section reads as if it works everywhere,
  and its TypeScript snippet doesn't mention OpenHarmony. An ArkTS app has to
  serve the requests with a resource provider and `@ohos.net.http` to add a
  header. Suggested fix: say so in the guide, with the provider as the way to
  add headers, or implement the transform on OpenHarmony's HTTP source.
- **Only offscreen sessions read back pixels, so an image of a visible map
  renders it again.** `readTexture()` needs
  `RenderSessionCapabilityFlag.readback`, which only `offscreen_device.cpp`
  sets; an OpenHarmony surface session doesn't. This library's `snapshot()`
  renders the map's style and camera in a static map instead, which loads the
  resources again (from the cache) and can differ from the screen mid-load.
  Suggested fix: readback for window sessions, or a note in the images guide
  that a still image of an on-screen map means a second, static map.

[42012958276]:
  https://github.com/maplibre/maplibre-native-ffi/actions/runs/42012958276
