# maplibre-arkui

An ArkUI library for [MapLibre Native] on HarmonyOS and OpenHarmony, built on
the ArkTS bindings of [MapLibre Native FFI]. It is a cousin of [MapLibre
Compose]. The package, `@maplibre/arkui`, has a `MapLibreMap` component that
moves with touch, mouse, touchpad, and keyboard gestures, a `MapController` that
reads and moves its camera, ornaments, markers made of ArkUI content, the user's
location, map content that the app declares from its state, style expressions,
and snapshots. It passes on FFI's style API, request handlers, offline regions,
and logs as they are.

It's a preview, and it isn't on [ohpm] yet: it waits for FFI to publish its
packages there, and for a license. See [the changelog](library/CHANGELOG.md) and
[ROADMAP.md](ROADMAP.md).

- [Install](#install) and [quick start](#quick-start)
- [The map](#the-map) and [the camera](#the-camera)
- [Gestures](#gestures)
- [Ornaments and markers](#ornaments-and-markers)
- [Map content](#map-content) and [expressions](#expressions)
- [The style API](#the-style-api)
- [The user's location](#the-users-location)
- [Snapshots](#snapshots)
- [Requests, offline regions, and logs](#requests-offline-regions-and-logs)
- [Errors](#errors)
- [Developing](#developing)

## Install

The library is a source HAR for API 20 and later. It depends on FFI's facade,
`@maplibre/native-ffi`, and the app installs one backend package next to it,
since ohpm has no peer dependencies. Once they are on ohpm:

```sh
ohpm install @maplibre/arkui @maplibre/native-ffi-opengl@<FFI version>
```

The backend's version must be the facade's, which `@maplibre/arkui`'s
`oh-package.json5` names; `ohpm list` shows it. OpenGL is the backend that FFI
tests; `@maplibre/native-ffi-vulkan` is the other. Until then, build the library
and the demo from this repository (see [Developing](#developing)).

An app that loads styles or tiles from the network requests the internet
permission in its `module.json5`:

```json5
"requestPermissions": [{ "name": "ohos.permission.INTERNET" }]
```

## Quick start

```ets
import { CameraUpdateMode, MapController, MapLibreMap } from '@maplibre/arkui';

@Entry
@ComponentV2
struct MapPage {
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
  });

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MapLibreMap({
        controller: this.controller,
        style: 'https://tiles.openfreemap.org/styles/liberty',
        onMapError: (error: Error) => console.error(error.message),
      })
      Button('Fly to New York')
        .margin(64)
        .onClick(() => {
          this.controller.updateCamera({
            mode: CameraUpdateMode.fly,
            camera: { center: { latitude: 40.7128, longitude: -74.006 }, zoom: 12 },
            animation: { durationMs: 3000 },
          }).catch((error: Error) => console.error(error.message));
        })
    }
    .width('100%')
    .height('100%')
  }
}
```

The library uses state management V2 only: put it in `@ComponentV2` structs.

## The map

`MapLibreMap` fills the size its parent gives it. Its `style` is a URL or a
style document as JSON, and a new value loads the new style. The map creates its
FFI map when it appears and releases it when it disappears. Pages in the
background need no code, since the map draws only while its window shows.

Its events tell the app when the style has loaded (`onStyleLoaded`), the camera
has come to rest (`onCameraIdle`), the user starts and stops moving the map
(`onGestureStart`, `onGestureEnd`), and something failed (`onMapError`; see
[Errors](#errors)). `cameraBounds` limits where the camera goes, and `runtime`
takes an FFI runtime of the app's own, for another cache.

## The camera

`MapController` reads and moves the camera from anywhere, as a `Scroller` does
for a list. Create one, pass it to one map, and keep it; when the map leaves the
screen and comes back, the new map starts where the old one left the camera.
`camera`, `styleLoaded`, `attributions`, and `followingUserLocation` are
observable, so a component that reads them updates when they change:

```ets
Text(this.moving ? 'Moving' : `Zoom ${this.controller.camera?.zoom.toFixed(1) ?? '…'}`)
```

`camera` changes when the camera comes to rest; `getCamera()` reads where it is
now. `updateCamera()` jumps, eases, or flies, `fitCameraToLatLngBounds()` fits
an area, and both resolve with how the move ended:

```ets
this.controller.fitCameraToLatLngBounds(SWITZERLAND, {
  mode: CameraUpdateMode.ease,
  fit: { padding: { top: 24, left: 24, bottom: 24, right: 24 } },
  animation: { durationMs: 1000 },
}).then((outcome: CameraTransitionOutcome) => {
  // A gesture or a later move can stop it first.
  this.message = outcome === CameraTransitionOutcome.completed ? 'Fitted' : 'Stopped';
}).catch((error: Error) => {
  // No map is on screen, or the map rejected the move.
  this.message = error.message;
});
```

`frameCamera`, `pixelForLatLng()`, `latLngForPixel()`, and
`metersPerPixelAtLatitude()` follow the frame on screen, and are observable too,
so content placed with them moves with the map. They change every frame, so read
them in `@Computed` getters of the components that need them. The controller
also exposes the FFI `runtime`, `map`, and `renderSession`, for what this
library doesn't wrap.

## Gestures

Drag, pinch, twist, and drag two fingers up or down to pan, zoom, rotate, and
pitch; double tap to zoom in, double tap and drag to zoom, and tap with two
fingers to zoom out. The mouse wheel, a touchpad pinch, and the arrow, plus, and
minus keys work too. A drag that starts on the map moves the map, even in a
`Scroll`. `gestures` turns some off, and `cooperative` leaves one-finger drags
and the plain wheel to a scrolling parent:

```ets
MapLibreMap({
  controller: this.controller,
  style: STYLE,
  gestures: { rotate: false },
  onGestureStart: () => {
    this.moving = true;
  },
  onGestureEnd: () => {
    this.moving = false;
  },
})
```

Content over the map that handles its own gestures, such as a button, keeps
them.

## Ornaments and markers

The map shows a compass while it's rotated or tilted, and the style's
attribution. `scaleBarEnabled` and `zoomButtonsEnabled` add a scale bar and zoom
buttons, and `ornamentPadding` keeps them all clear of app UI over the map. The
ornaments follow dark mode.

Content in the map's trailing closure lies over it, and `MapMarker` pins content
to a coordinate:

```ets
MapLibreMap({ controller: this.controller, style: STYLE, scaleBarEnabled: true }) {
  MapMarker({ controller: this.controller, coordinate: { latitude: 48.8566, longitude: 2.3522 } }) {
    Text('Paris')
      .padding(6)
      .backgroundColor(Color.White)
  }
}
```

Each ornament is also a component, `MapCompass`, `MapScaleBar`,
`MapAttribution`, and `MapZoomButtons`, to place yourself:

```ets
Stack({ alignContent: Alignment.TopStart }) {
  MapLibreMap({ controller: this.controller, style: STYLE, compassEnabled: false })
  MapCompass({ controller: this.controller, alwaysShown: true })
    .margin(16)
}
```

The sources' terms usually require their attribution, so show it, with
`MapAttribution` or the controller's `attributions`, when you turn
`attributionEnabled` off.

## Map content

An app declares what it draws over the style as data: sources, layers, and
images, in a `MapContent` that it passes to `MapLibreMap`. A `@Computed` getter
that reads the app's state makes a new value when the state changes, and the map
compares it with what it applied, by ID, and changes only what differs: a
property in place, a GeoJSON source's data, a layer's position. Each style the
map loads gets the content again, so it lasts across style changes.

```ets
@Computed
get content(): MapContent {
  return {
    sources: [{ id: 'places', json: { 'type': 'geojson', 'data': this.places } }],
    layers: [
      {
        id: 'places', type: 'circle', source: 'places',
        paint: { 'circle-radius': 8, 'circle-color': match(get('kind'), [['museum', '#fb8c00']], this.color) },
        // Under the base style's labels.
        below: (layer: StyleLayerInfo) => layer.type === 'symbol',
      },
      {
        id: 'monuments', type: 'symbol', source: 'places', filter: eq(get('kind'), 'monument'),
        layout: { 'icon-image': 'pin', 'icon-anchor': 'bottom', 'icon-allow-overlap': true },
      },
    ],
    images: [{ id: 'pin', image: this.pin, options: { pixelRatio: 3 } }],
  };
}
```

The map takes it as `content`, as in [the style API](#the-style-api)'s example.

To change it, give the state a new value; the map doesn't see changes made
inside a value it has. It compares properties and GeoJSON data by their JSON,
and images by reference, so read an image once:

```ets
// Read once: the map compares images by reference.
private pin: PremultipliedRgba8Image = readImage(this.getUIContext(), 'pin.png');
```

```ets
this.places = { type: 'FeatureCollection', features: this.places.features.concat([LOUVRE]) };
```

Strict ArkTS takes an object literal only for a declared type, so the library
declares GeoJSON's types (`GeoJsonFeatureCollection`, `GeoJsonFeature`,
`GeoJsonGeometry`), and style JSON is a `Record<string, Object>` with quoted
keys:

```ets
const LOUVRE: GeoJsonFeature = {
  type: 'Feature', id: 3, geometry: { type: 'Point', coordinates: [2.3376, 48.8606] },
  properties: { 'name': 'Louvre', 'kind': 'museum' },
};
```

Layers go on top, or under the base-style layer that `below` names or picks, in
their order in `layers`. A source or layer that the map rejects goes to
`onMapError` and stays out until it changes. `readPixelMap()` turns a decoded
`PixelMap` into a style image; the demo's
[`readImage()`](demo/entry/src/main/ets/docs/Examples.ets) reads one from
`resources/rawfile`.

## Expressions

Build [style expressions] with functions named after their operators, such as
`get`, `match`, `interpolate`, and `featureState` for `feature-state`. Symbols
get words (`eq` for `==`, `add` for `+`), and `case` is `cases`. Use them in
`MapContent`, or pass them to FFI's style functions as they are:

```ets
async function styleWithExpressions(map: MapHandle): Promise<void> {
  const radius = interpolate(linear(), zoom(), [[0, 2], [12, get('size')]]);
  const color = match(get('kind'), [['park', '#8c8'], [['lake', 'river'], '#88c']], '#ccc');
  await map.setStyleLayerProperty('places', 'circle-radius', radius);
  await map.setStyleLayerProperty('places', 'circle-color', color);
}
```

`call(operator, ...args)` and `new Expression(json)` cover the operators that
have no function. Expressions are untyped: MapLibre checks their types as it
parses them.

## The style API

For everything else, the style API is MapLibre Native FFI's: `controller.map`
adds and changes sources, layers, images, and feature state, and
`controller.renderSession` queries features. A click's point is in vp from the
map's corner, as queries take it:

```ets
MapLibreMap({ controller: this.controller, style: STYLE, content: this.content })
  .onClick((event: ClickEvent) => this.select(event.x, event.y))
```

```ets
private async select(x: number, y: number): Promise<void> {
  const session = this.controller.renderSession;
  if (session === undefined) {
    return;
  }
  const hits = await session.queryRenderedFeatures({ kind: 'point', value: { x: x, y: y } },
    { layerIds: ['places', 'monuments'] });
  const feature = hits.length > 0 ? hits[0].feature as GeoJsonFeature : undefined;
  this.selected = feature === undefined ? 'Nothing here' : `${feature.properties?.['name']}`;
}
```

What an app adds through `controller.map` is gone in the next style, so add it
in `onStyleLoaded`, or declare it as content. Change the style through the map's
`style`, not the FFI map's style setters, so the map adds its content again. On
an idle map, a feature state change draws only from the frame after the one that
applies it; until FFI fixes that, request one, as the demo's style page does
with `map.discarding.requestRepaint()` from a delayed frame callback (see
[docs/ffi-feedback.md](docs/ffi-feedback.md)).

## The user's location

The map shows the location that the app passes as `userLocation`, a Location Kit
`geoLocationManager.Location`, as a dot in a circle of its accuracy, with an
arrow for its course while it moves. `followUserLocation()` moves the camera
with each new location until the user starts a gesture, which sets the
controller's observable `followingUserLocation` to false:

```ets
@Local location: geoLocationManager.Location | undefined = undefined;
private controller: MapController = new MapController();
private listening: boolean = false;
private onLocation = (location: geoLocationManager.Location): void => {
  this.location = location;
};

build() {
  Stack({ alignContent: Alignment.Bottom }) {
    MapLibreMap({ controller: this.controller, style: STYLE, userLocation: this.location })
    Button(this.controller.followingUserLocation ? 'Following' : 'Locate me')
      .margin(64)
      .onClick(() => {
        this.controller.followUserLocation({ zoom: 16, course: true });
        this.startUpdates().catch((error: Error) => console.error(error.message));
      })
  }
}
```

The library declares no permission and starts no location request, so apps that
don't show a location don't ask for one. An app that does declares
`ohos.permission.APPROXIMATELY_LOCATION` and `ohos.permission.LOCATION` in its
`module.json5`, with a `reason`, asks for them when the user wants to see their
location, and listens until the page goes away:

```ets
aboutToDisappear(): void {
  if (!this.listening) {
    return;
  }
  try {
    geoLocationManager.off('locationChange', this.onLocation);
  } catch (error) {
    // Location Kit throws once the user takes the permission back.
  }
}

private async startUpdates(): Promise<void> {
  if (this.listening) {
    return;
  }
  this.listening = true;
  const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, PERMISSIONS);
  if (!result.authResults.some((status: number) => status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)) {
    this.listening = false;
    this.controller.stopFollowingUserLocation();
    return;
  }
  const request: geoLocationManager.ContinuousLocationRequest = {
    interval: 1,
    locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION,
  };
  geoLocationManager.on('locationChange', request, this.onLocation);
}
```

## Snapshots

`snapshot()` renders a still image of a map that isn't on screen, as a
`PixelMap` for an `Image`:

```ets
@Local preview: image.PixelMap | undefined = undefined;
private disappeared: boolean = false;

aboutToAppear(): void {
  snapshot({
    style: STYLE,
    width: 320,
    height: 200,
    camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
  }).then((preview: image.PixelMap) => {
    if (this.disappeared) {
      preview.release();
    } else {
      this.preview = preview;
    }
  }).catch((error: Error) => console.error(error.message));
}

aboutToDisappear(): void {
  this.disappeared = true;
  this.preview?.release();
}
```

For an image of a `MapLibreMap`, pass its style, its content, and its
controller's camera:

```ets
function snapshotOf(controller: MapController, content: MapContent): Promise<image.PixelMap> {
  const camera = controller.getCamera();
  return snapshot({
    style: STYLE,
    content: content,
    width: 320,
    height: 200,
    camera: camera === undefined ? undefined : cameraToOptions(camera),
  });
}
```

Without `camera`, the image uses the style's default camera; with it, the fields
it leaves out take MapLibre's defaults, not the style's. The image holds only
the map, so show the style's attribution with it.

## Requests, offline regions, and logs

These are [MapLibre Native FFI]'s API, which the package re-exports. Maps and
snapshots share a default runtime unless the app passes its own. Set request
handlers on it, before or after maps appear:

```ets
async function useApiKey(): Promise<void> {
  const runtime = await getDefaultRuntime();
  await runtime.setResourceTransform({
    rules: [{
      flags: UrlMatchFlag.glob,
      url: 'https://tiles.example.com/**',
      parameters: [{ name: 'key', value: API_KEY }],
    }],
  });
}
```

For other rewrites, pass a `callback` instead of `rules`; it must answer every
request. On OpenHarmony, FFI has no header transform: serve the requests that
need headers with `runtime.setResourceProvider()` instead. See FFI's [network
guide].

The default runtime keeps its cache database, `maplibre-cache.db`, in the app's
files directory, so [offline regions] last between launches. The library owns
the runtime's one event handler, so watch a download with
`addRuntimeEventListener()`:

```ets
const region = await runtime.createOfflineRegion(PARIS_REGION, new util.TextEncoder().encodeInto('Paris'));
addRuntimeEventListener(runtime, (event: RuntimeEvent) => {
  const payload = event.payload;
  if (payload.kind === 'offlineRegionStatus' && payload.value.regionId === region.id) {
    const status = payload.value.status;
    console.info(`Paris: ${status.completedResourceCount} of ${status.requiredResourceCount} resources`);
  }
});
await runtime.setOfflineRegionObserved(region.id, RuntimeEventFlag.offlineRegionStatusChanged);
await runtime.setOfflineRegionDownloadState(region.id, OfflineRegionDownloadState.active);
```

MapLibre logs to hilog with the tag `MapLibreNative`. To take the logs, set a
callback:

```ets
setLogCallback({
  callback: (severity: LogSeverity, event: LogEvent, code: bigint, message: string) => {
    console.info(`MapLibre (${event}): ${message}`);
  },
  // Errors still go to hilog too.
  platformSeverities: LogSeverityFlag.error,
});
```

## Errors

- Camera methods return promises that resolve with how the move ended
  (`CameraTransitionOutcome`), and reject when no map is on screen or the map
  rejects the change. FFI's style and query methods reject with a
  `MaplibreError`.
- What goes wrong while the map runs, such as a style that fails to load or
  content the map rejects, goes to `onMapError`.
- `snapshot()` rejects when the style or a resource it needs fails to load.

## Developing

[mise] installs everything, including the OpenHarmony SDK and an Oniro emulator
image:

```sh
mise install
mise run ffi:download   # FFI's packages at the pinned commit
mise run demo           # build the demo and start it on an emulator
mise run test           # run the hypium suite on the emulator
mise run check
```

[AGENTS.md](AGENTS.md) describes the layout, the tasks, how the build works
without hvigor, and how to release.
[docs/api-guidelines.md](docs/api-guidelines.md) has the API's conventions. The
demo's [`docs/`](demo/entry/src/main/ets/docs) pages hold this README's
examples, which `mise run check` matches against it and the demo build compiles.

[MapLibre Compose]: https://maplibre.org/maplibre-compose/
[MapLibre Native]: https://github.com/maplibre/maplibre-native
[MapLibre Native FFI]: https://maplibre.org/maplibre-native-ffi/
[mise]: https://mise.jdx.dev
[network guide]: https://maplibre.org/maplibre-native-ffi/guides/network/
[offline regions]: https://maplibre.org/maplibre-native-ffi/guides/offline/
[ohpm]: https://ohpm.openharmony.cn/
[style expressions]: https://maplibre.org/maplibre-style-spec/expressions/
