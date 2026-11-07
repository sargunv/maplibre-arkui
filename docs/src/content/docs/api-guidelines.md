---
title: API guidelines
description: Rules for the public API of the published library.
---

Rules for the public API of the published library.

## 1. About this guide

This guide covers every declaration that `library/Index.ets` exports, and how
the library's sources are organized. It doesn't cover the design of internal
code, the demo app, or the tests.

The API is designed for apps written in strict ArkTS with ArkUI's state
management V2. It should read like ArkUI's own components and options, so that
an ArkUI developer can guess it.

Each section lists rules, then examples. A rule taken from another guide ends
with a bracketed number, such as [1], that links to the relevant section; the
guides are also listed under Sources at the end. If a rule doesn't fit a case,
change the rule in the same PR instead of making an exception in code.

Rules enforced deterministically, such as by the ArkTS linter, should be removed
from this guide.

## 2. Naming

- Name classes, interfaces, and components with nouns, and functions with verbs.
  Avoid filler words such as `Manager` and `Wrapper`.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#2-naming)
- Don't repeat the library's name or the word `Map` in a name, because the
  import already says where it comes from. Add `Map` only when the name would
  otherwise be a generic word.
- Don't take a name that ArkUI declares globally, such as a component or a type
  in scope in every file.
- Use UpperCamelCase for classes, interfaces, enums, and components, and
  lowerCamelCase for functions, members, and parameters.
  [[2]](https://gitee.com/openharmony/docs/blob/master/en/contribute/OpenHarmony-ArkTS-coding-style-guide.md)
- Use UPPER_SNAKE_CASE for enum members.
  [[2]](https://gitee.com/openharmony/docs/blob/master/en/contribute/OpenHarmony-ArkTS-coding-style-guide.md)
- Treat acronyms, initialisms, and MapLibre as words in code: `GeoJson`,
  `Maplibre`. In prose, use the usual spelling: GeoJSON, MapLibre.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#2-naming)
- When the MapLibre style spec has a term for something, use it, in camel case.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#2-naming)
- Name a class that the app creates and passes to a component to read and
  control it `<Thing>Controller`, as ArkUI's `TextController` is.
- Name settings `<Thing>Options`, after what they configure.
- Name events `on` and what happened. When ArkUI's universal events take one
  name of a family, add the component's noun to the whole family: `onMapClick`
  and `onMapLongClick`, because of the universal `onClick`.
- Name an event's type after its handler, without `on`, and add `Event`:
  `onCameraIdle` takes a `CameraIdleEvent`. Handlers whose payloads are the same
  may share one type, as `onMapClick` and `onMapLongClick` share
  `MapClickEvent`.
- Don't give booleans an `is` prefix or a negative name.
  [[2]](https://gitee.com/openharmony/docs/blob/master/en/contribute/OpenHarmony-ArkTS-coding-style-guide.md)
- In the expression DSL, write operators that take no arguments as functions,
  not constants: `zoom()`, not `ZOOM`.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#2-naming)
- Start resource names with `maplibre_`, because the library's resources merge
  into the app's.

```ets
// Do
CompassButton()

interface GeoJsonSourceOptions {}

class MapController {}

enum ScaleBarUnits {
  METRIC,
  FEET_AND_MILES,
}

enabled?: boolean;

@Event onMapClick: (event: MapClickEvent) => boolean;

// Don't
MapCompassButton()

interface GeoJSONSourceOptions {}

class Controller {}

enum ScaleBarUnits {
  Metric,
  FeetAndMiles,
}

isDisabled?: boolean;

@Event onClick: (event: MapClickEvent) => boolean; // a universal event
```

## 3. General API design

- Build on a small set of core operations, and add conveniences that combine
  them. Give every declarative feature imperative operations that apps can also
  call.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#3-general-api-design)
- Keep a type's members to its core concept.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#3-general-api-design)
- Prefer small pieces that callers combine over more parameters.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#3-general-api-design)
- Use the same parameter names, types, and order across related functions, from
  general to specific.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#3-general-api-design)
- Avoid `boolean` arguments whose meaning isn't clear at the call site.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#3-general-api-design)
- Choose the failure by whether correct code could have avoided it:
  - A programming error is a call that correct code never makes, such as an
    invalid argument. Throw an `Error` whose message describes the problem and
    includes the rejected value.
  - Work that finishes later returns a promise, which rejects when the work
    fails. Being stopped or replaced is an outcome that the promise resolves
    with, not a failure.
  - A failure with no caller to reject, such as a style that fails to load, goes
    to the component's error event and to the log.
    [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#3-general-api-design)
  - An invalid value in a component parameter is a failure with no caller: the
    component reports it to its error event, or to the log when it has none, and
    uses the default or the last valid value in its place.
- Return `undefined` when data can't be found or computed. Don't use exceptions
  for control flow.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#3-general-api-design)
- Make behavior unsurprising instead of documenting a surprise. When behavior is
  wrong, fix it instead of documenting it.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#3-general-api-design)
- Don't keep state in global variables or stateful top-level functions. Let
  callers pass the object in.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#3-general-api-design)
- Make settings that MapLibre Native keeps once per process static members of
  `MapRuntime`, as ArkUI's `PersistenceV2` and `AppStorageV2` are: the default
  runtime and its configuration, the connectivity mode, and the log handler.

```ets
// Do
controller.updateCamera({ zoom: 12 }, { mode: CameraTransitionMode.EASE });

throw new Error(`Unsupported pixel format: ${format}`);

// Don't
controller.updateCamera({ zoom: 12 }, true);

throw new Error('Unsupported pixel format');
```

## 4. Types that may grow

Every enum, union, and set of named values is one of four kinds. Choose the kind
by what any later release might add, because changing the shape later is a
breaking change.
[[1]](https://maplibre.org/maplibre-compose/api-guidelines/#4-types-that-may-grow)

| Kind           | Use when                                                                           | Declare as                                    | Example        |
| -------------- | ---------------------------------------------------------------------------------- | --------------------------------------------- | -------------- |
| Closed         | The values can never change, because they describe math or a fixed protocol        | A string-literal type                         | GeoJSON's tags |
| Open input     | Callers only pass values in                                                        | `enum`                                        | `WheelAction`  |
| Open identity  | A raw name from the style spec or the engine, possibly one with no named value yet | `string`                                      | A layer's type |
| Open structure | The library returns it                                                             | A union of classes, matched with `instanceof` | `MapEvent`     |

- State the kind in the doc comment: "Closed." or "Values may be added in later
  releases; give a `switch` over it a `default` branch."
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#4-types-that-may-grow)
- An input enum that a getter only echoes back, such as `FollowBearing` from
  `followedBearing`, stays open input.
- An enum that callers pass in and the library also reports, such as
  `MapResourceErrorReason`, or that callers compare against named values, such
  as `MapLogLevel`, stays an enum, as ArkUI's `TouchType` does. Its doc asks for
  a `default` branch.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#4-types-that-may-grow)
- When a value means "no answer", use `undefined` instead of a named catch-all
  such as `UNKNOWN`.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#4-types-that-may-grow)

```ets
// Open identity: holds a type that a later style spec adds
type: string;

// Don't: an enum can't hold a value this version doesn't name
type: LayerType;
```

## 5. Options and configuration

- Declare settings as interfaces that callers write as object literals, as
  ArkUI's own options are.
- Make a field optional when it has a default, and required when it doesn't.
  State the default in the field's doc comment.
- Don't give interfaces that callers write methods. Make a callback a
  function-typed field.
- Nest the settings of one part of a feature as their own options.
- When several functions share settings, have one options interface extend
  another, so the shared fields keep one name and one doc comment.
- Take style-spec JSON as `Record<string, Object>` with the spec's keys.
- Don't start rejecting a value that an earlier release accepted.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#5-options-and-configuration)

```ets
export interface CameraTransitionOptions {
  /** Whether the camera jumps, eases, or flies. Jumps by default. */
  mode?: CameraTransitionMode;
  /** How long the camera takes. */
  durationMs?: number;
}

export interface FitCameraOptions extends CameraTransitionOptions {
  /** Space around what the camera fits. None by default. */
  fitPadding?: Padding | LocalizedPadding;
}

controller.fitCameraToBounds(bounds, {
  mode: CameraTransitionMode.EASE,
  fitPadding: { top: 24, bottom: 24 },
});
```

## 6. Components

### Parameters

- Use state management V2 only. Don't use V1 decorators, AppStorage, or
  LocalStorage.
  [[3]](https://gitee.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-state-management-overview.md)
- Order parameters: required, then optional, then events, then the builder
  parameter.
- Give each `@Param` a default in its initializer or mark it `@Require`, and
  give each `@Event` a no-op default.
- Make a parameter `| undefined` only when absence means something, never to
  mean "use the default".
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#6-composables)
- Use `@Once` only for what a component binds to as it's created.
- Name a `@BuilderParam` for what it holds.
- Don't add a parameter for something an attribute can do, unless it's core to
  the component.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#6-composables)
- Take values for data, not observed objects. Compare a new value with the last
  one, so that a literal that `build()` writes anew changes nothing that stayed
  the same.
- A component meant for the map's overlay finds its map itself, and takes no
  controller.

### State

- Hoist caller-controlled state into an `@ObservedV2` controller that the caller
  creates and passes as `controller`. Default the parameter to a new controller.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#6-composables)
- Put `@Trace` only on state that callers show. Expose state that only the
  library changes through a getter, so callers can't assign it.
- Keep members that only the library calls off public classes.
- Expose values that change every frame as one traced value, so per-frame work
  stays in the components that read it.

```ets
@ComponentV2
export struct Marker {
  /** Where the content goes. */
  @Require @Param coordinate: LatLng;
  /** The point of the content that sits on the coordinate. The center by default. */
  @Param alignment: Alignment = Alignment.Center;
  /** The content. */
  @BuilderParam content: () => void = noContent;
}

@ObservedV2
export class MapController {
  @Trace private loaded: boolean = false;

  /** Whether the map's style has loaded. */
  get styleLoaded(): boolean {
    return this.loaded;
  }
}
```

## 7. Callbacks

- When a callback receives information from the library, such as an event, pass
  it as one parameter of a library type, so that the type can gain fields.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#7-callbacks)
- Name callback types by role: a `<Thing>Handler` handles one event, and a
  `<Thing>Listener` is added and removed.
- Return `true` from a handler to consume the event, so the handlers after it
  don't get it, as ArkUI's `onKeyEvent` does.
- Make a callback that may wait on I/O return a promise.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#7-callbacks)
- Document which thread each callback runs on and what happens if it throws.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#7-callbacks)
- Log an exception from a listener or handler, and keep calling the others.

```ets
// Do
export type FeatureClickHandler = (event: FeatureClickEvent) => boolean;

// Don't
export type FeatureClickHandler = (features: GeoJsonFeature[], x: number, y: number) => boolean;
```

## 8. Types the library creates

Events, query results, and frame state are created by the library and only read
by callers.

- Declare them as interfaces. Errors are classes that extend `Error`. Add fields
  in any release.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#8-types-the-library-creates)
- When state can change outside the caller's control, and the caller can't check
  it first without a race, return `undefined` from reads instead of throwing.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#3-general-api-design)

```ets
export interface MapClickEvent {
  /** The coordinate under the click. */
  coordinate: LatLng;
  /** The click's position on the map. */
  point: ScreenPoint;
}
```

## 9. MapLibre Native FFI

FFI is an implementation detail.

- Declare the library's own types for what the API takes and returns, even where
  FFI has a type for the same thing. Don't re-export or alias FFI's
  declarations.
- Don't expose FFI's objects as properties, parameters, or return values. For
  what the library doesn't cover yet, lend FFI's map only for the length of a
  callback, and document that FFI's types may change in any release.
- When callers commonly need the escape hatch for something, add it to the
  library's API.

```ets
// Do
export interface LatLng {
  latitude: number;
  longitude: number;
}

withFfiMap<T>(block: (map: MapHandle, session: RenderSessionHandle | undefined) => T): T | undefined;

// Don't
export type { LatLng } from '@maplibre/native-ffi';

get map(): MapHandle | undefined;
```

## 10. Units and value types

- Use a typed value when one exists for the quantity (see the table).
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#10-units-and-value-types)
- When a plain number's unit isn't the one in the table, end its name with the
  unit.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#10-units-and-value-types)
- Don't use number types for identifiers.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#10-units-and-value-types)

| Quantity                       | Type                                       |
| ------------------------------ | ------------------------------------------ |
| Geographic position and bounds | The library's `LatLng` and `LatLngBounds`  |
| Geometry                       | The library's GeoJSON types                |
| Screen position                | The library's `ScreenPoint`, in vp         |
| Screen distance                | `number`, in vp                            |
| Duration                       | `number`, named `…Ms`, in milliseconds     |
| Point in time                  | `Date`                                     |
| Size in bytes                  | `number`, named `…Bytes`                   |
| Angle and bearing              | `number`, in degrees, clockwise from north |
| Insets                         | ArkUI `Padding` or `LocalizedPadding`      |
| Color                          | ArkUI `ResourceColor`                      |
| Image                          | `image.PixelMap`                           |
| Location from Location Kit     | `geoLocationManager.Location`              |

```ets
durationMs: number; // Do
duration: number; // Don't: the unit isn't in the name
color: ResourceColor; // Do
color: string; // Don't
```

## 11. Documentation

- Write a `/** */` comment for every public declaration.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#11-documentation)
- Write it as the contract: behavior, parameters, return values, lifecycle,
  threading, and what rejects or throws. Don't describe how it's implemented.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#11-documentation)
- Start with one sentence that says what the declaration does, without restating
  the signature.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#11-documentation)
- State valid input ranges, what happens with invalid input, and every error.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#11-documentation)
- Add an example only when usage isn't clear from the signature and the comment.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#11-documentation)
- Write simple English, without idioms, Latin abbreviations, or jargon.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#11-documentation)
- Keep contracts out of the docs site. Site pages introduce concepts and common
  tasks, and link to the API reference for details.
  [[1]](https://maplibre.org/maplibre-compose/api-guidelines/#11-documentation)

```ets
/**
 * Shows a button that turns the map back to north.
 *
 * Tapping it animates the camera's bearing to 0.
 */
```

## 12. Organization

- Put each feature's sources in one lowercase, singular directory under
  `library/src/main/ets`, such as `camera/`, and library-only code in its
  `internal/` directory. Any feature may import another feature's `internal/`.
  Don't add catch-all directories, such as `util/` or `common/`.
- Name each file in UpperCamelCase, after its main declaration or its topic.
- Group `library/Index.ets` by feature, in the order of the guides.
- Support imports from the package root only. Apps that import a path under
  `src/` may break in any release.

`scripts/check-api-layout.sh` and `docs/scripts/emit-declarations.mjs` check the
rest: every export of a file outside `internal/` is in `Index.ets`, which lists
each name and exports nothing of FFI's, and each feature directory has a
category in the API reference.

```text
camera/
  CameraPosition.ets
  internal/
    Insets.ets
```

## 13. Stability and compatibility

Until 1.0, any release may break the API. The PR that breaks it says how to
migrate.

## Sources

1. [MapLibre Compose API guidelines](https://maplibre.org/maplibre-compose/api-guidelines/):
   the sibling library's rules for its public API.
2. [ArkTS coding style guide](https://gitee.com/openharmony/docs/blob/master/en/contribute/OpenHarmony-ArkTS-coding-style-guide.md):
   naming.
3. [State management overview](https://gitee.com/openharmony/docs/blob/master/en/application-dev/ui/state-management/arkts-state-management-overview.md):
   state management V1 and V2.

Each rule taken from one of these guides ends with its number, linked to the
relevant section. Rules without a citation are this project's own.
