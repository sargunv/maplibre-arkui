# Repository guidance

maplibre-arkui is an ArkUI library for MapLibre Native on HarmonyOS and
OpenHarmony, built on the ArkTS bindings of
[MapLibre Native FFI](https://github.com/maplibre/maplibre-native-ffi). Its
sibling, [MapLibre Compose](https://github.com/maplibre/maplibre-compose), also
runs on FFI. Mise provides every tool and task; `mise tasks` lists the tasks.

Read these when the task needs them:

- [Guides](docs/src/content/docs/): how to use the library.
- [Build from source](docs/src/content/docs/development.mdx): setup and everyday
  commands.
- [API guidelines](docs/src/content/docs/api-guidelines.md): read before you
  change the public API.

## Priorities

The published library is the product. What matters most there is correct
behavior and a clear API. Until 1.0, a release may break the API to reach a
better one; users upgrade by following the migration notes in PR descriptions.

Simple, clear code comes first: a map that behaves well with simple code beats
one that matches Compose or any other reference exactly. Avoid native code.

Everything else serves maintainers: the demo app, tests, docs-site tooling, and
CI scripts. The demo also shows users how to call the library, so its library
usage should be idiomatic.

FFI's behavior is whatever FFI does at the commit `vars.ffi_commit` in
`mise.toml` pins. Answer questions about engine behavior from that source, and
report FFI gaps and bugs upstream instead of working around them with complex
code.

## Pitfalls

- FFI's CI keeps the packages `mise run ffi:download` fetches for 30 days. Move
  the pin to a newer FFI main commit whose CI run has them before then, or CI
  breaks.
- A test run that ends without hypium's tally didn't finish. Don't retry it:
  inspect the device's freeze reports (`/data/log/eventlog/`) and crash logs
  (`/data/log/faultlog/faultlogger/`).
- On DevEco Studio's emulator, the OpenGL driver crashes the app during some
  full test runs (maplibre-native-ffi#1728). It corrupts memory when a map's
  surface goes away while the emulator still shows it, so the app dies later,
  often in `Style::Impl::loadJSON` on FFI's runtime thread. The app's hilog then
  has DGLES's `null gpu context` and `program_data_len is 0`. Such a crash isn't
  a bug in the change under test.
- Don't run `power-shell suspend` on the emulator: `hdc shell` hangs until it's
  released.
- The webpack build that compiles ArkTS doesn't rewrite `@kit.*` imports, so
  import `@ohos.*` modules, and it emits invalid code for a renamed import
  (`import { A as B }`) from one. It omits some built-in components, such as
  `NodeContainer` and `ContentSlot`. In a `ForEach` item, a custom component's
  trailing closure is silently dropped; have the item call a `@Builder`.
- ArkUI reserves its components' names, such as `Camera`, so import an FFI
  declaration that takes one under another name.
- OpenHarmony's main thread can lose a timer's wakeup and hang a `setTimeout`
  poll. Wait for frame callbacks or events instead.
- hypium's `assertClose` compares the difference relative to the actual value,
  not as an absolute tolerance.
- A HAR's `requestPermissions` merge into every app that uses it, so the library
  declares none; apps pass in what needs a permission.
- The library's resources merge into every app's, as its permissions would, so
  name each `maplibre_…`. `scripts/build-hap.sh` compiles the merged table with
  restool before ets-loader runs, since ets-loader resolves `$r('app.…')` from
  it; a name missing from it fails the build as an unknown resource.
- ArkUI's `@Consumer` doesn't reach content in another component's trailing
  closure, which the closure's author owns. The overlay's controls find their
  map by walking up the frame nodes (`scope.ets`).
- A custom component can't declare a member that ArkUI's universal attributes
  name, such as `size`, `key`, `overlay`, or `onClick`.

## Tests

Test what this library adds, not FFI's behavior. Test behavior that apps can
observe, and add a test only when it would catch a regression in that behavior.
Keep cases independent of each other and of screen density. Scratch checks you
ran while working don't need to be committed.

## Documentation

Documentation describes the library as it is, for a reader who doesn't know its
history. Notes about what changed belong in the PR description. Site pages help
a user complete a task; exact contracts belong in doc comments, which become the
API reference. Each ArkTS example on the site is a region of the demo's
`ets/docs/` files, so it compiles with the demo.

## Issues and pull requests

PR titles follow Conventional Commits, because the title becomes the
squash-merge commit message. Mark a title as breaking only when the change
breaks a user-facing contract. Changes to tooling, tests, or CI are never
breaking.

Write a short title and description for a reviewer who will read the diff. Say
what the diff, its doc comments, and CI can't:

- Open with the problem and what users can now do, or what maintainers gain.
- Show one small example of new API, or a bug's trigger with before and after.
- List checks that CI can't run, such as a run on a phone or on DevEco Studio's
  emulator. Leave out the builds, checks, and hypium suite that CI runs.
- Rewrite both when review changes the scope.

Append this disclosure to any AI-assisted content you post on GitHub, such as an
issue, a reply, or a PR description or comment:
`*AI-assisted — Tool: <tool>; model: <provider>/<model>*`
