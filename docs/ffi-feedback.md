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
  plugin to its own copy. Suggested fix: move it to a repository of its own and
  reference it from `[plugins]`, as its `metadata.lua` already anticipates.
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
  keeping the patch.
- **`pack-hap` needs Python only to edit the profile JSON.** `jq` does it, as in
  this repository's `scripts/pack-hap.sh`. Minor.
- **The emulator can reject the first launch after it boots.** Right after
  `devices-cli get ohos` boots the Oniro emulator, `aa start` failed once with
  error 10106102, "The device screen is locked during the application launch"; a
  second try succeeded. This is in devices-cli rather than FFI, which
  `tools/devices/ohos-key` shares. Suggested fix: have devices-cli wait until
  the lock screen is gone before it reports the device. (`power-shell suspend`
  to reproduce it hangs `hdc shell` until the emulator is released.)

[42012958276]:
  https://github.com/maplibre/maplibre-native-ffi/actions/runs/42012958276
