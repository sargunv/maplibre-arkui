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

The project is prerelease. Make breaking changes instead of adding compatibility
shims.

Simple, clear code comes first: a map that behaves well with simple code beats
one that matches Compose or any other reference exactly. Follow ArkUI's idioms
where Compose's shape would surprise an ArkUI developer, and use only state
management V2 and current APIs. Wrap FFI only where ArkUI apps need more than
FFI's types; otherwise re-export them and expose FFI's handles. Every
declarative feature sits on imperative operations that apps can also call. Avoid
native code.

FFI's behavior is whatever FFI does at the commit `vars.ffi_commit` in
`mise.toml` pins. Report FFI gaps and bugs upstream instead of working around
them with complex code.

## Pitfalls

- FFI's CI keeps the packages `mise run ffi:download` fetches for 30 days. Move
  the pin to a newer FFI main commit whose CI run has them before then, or CI
  breaks.
- On the Oniro emulator, Mesa's llvmpipe crashes the app during most full test
  runs (maplibre-native-ffi#1692). A run that ends without hypium's tally
  crashed; don't retry it. DevEco Studio's emulator has a GPU and finishes the
  suite.
- Don't run `power-shell suspend` on the emulator: `hdc shell` hangs until it's
  released.
- The webpack build that compiles ArkTS doesn't rewrite `@kit.*` imports, so
  import `@ohos.*` modules. It omits some built-in components, such as
  `NodeContainer` and `ContentSlot`. In a `ForEach` item, a custom component's
  trailing closure is silently dropped; have the item call a `@Builder`.
- ArkUI reserves the name `Camera`, so import FFI's as `CameraPosition`.
- OpenHarmony's main thread can lose a timer's wakeup and hang a `setTimeout`
  poll. Wait for frame callbacks or events instead.
- hypium's `assertClose` compares the difference relative to the actual value,
  not as an absolute tolerance.
- A HAR's `requestPermissions` merge into every app that uses it, so the library
  declares none; apps pass in what needs a permission.

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
- List checks that CI can't run, such as the hypium suite on a device. Leave out
  the builds and checks that CI runs.
- Rewrite both when review changes the scope.

Append this disclosure to any AI-assisted content you post on GitHub, such as an
issue, a reply, or a PR description or comment:
`*AI-assisted — Tool: <tool>; model: <provider>/<model>*`
