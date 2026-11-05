# maplibre-arkui

An ArkUI library for [MapLibre Native] on HarmonyOS and OpenHarmony, built on
the ArkTS bindings of [MapLibre Native FFI]. It is a cousin of [MapLibre
Compose]. It's early: the package, `@maplibre/arkui`, shows a map that moves
with touch, mouse, and keyboard gestures, with a compass, scale bar,
attribution, and zoom buttons. It pins ArkUI content to coordinates, moves its
camera from code, builds style expressions, draws content that the app declares
from its state, changes the style, and renders snapshots. It re-exports FFI's
request handlers, offline regions, and logs. See [ROADMAP.md](ROADMAP.md) for
the plan.

## Using it

The library will be published on [ohpm] as a source HAR that requires API 20. It
depends on FFI's backend-free facade, `@maplibre/native-ffi`, and an app
installs one backend next to it, `@maplibre/native-ffi-opengl`, since ohpm has
no peer dependencies. Until FFI publishes those packages, build against FFI main
as below.

```ts
import { CameraUpdateMode, MapController, MapLibreMap } from '@maplibre/arkui';

@Entry
@ComponentV2
struct MapPage {
  private map: MapController = new MapController({
    camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
  });

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MapLibreMap({
        controller: this.map,
        style: 'https://tiles.openfreemap.org/styles/liberty',
        onMapError: (error: Error) => console.error(error.message),
      })
      Button('Fly to New York').onClick(() => {
        this.map.updateCamera({
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

An app that loads styles or tiles from the network requests
`ohos.permission.INTERNET` in its `module.json5`.

The map shows a compass while it's rotated and the style's attribution; its
`scaleBarEnabled` and `zoomButtonsEnabled` flags add the others, and
`ornamentPadding` keeps them clear of app UI. Each is also a component, such as
`MapCompass({ controller })`, to place yourself. Content in the map's trailing
closure lies over it, and `MapMarker` pins content to a coordinate:

```ts
MapLibreMap({ controller: this.map, style: STYLE, scaleBarEnabled: true }) {
  MapMarker({ controller: this.map, coordinate: { latitude: 48.8566, longitude: 2.3522 } }) {
    Text('Paris')
  }
}
```

Drag, pinch, twist, and drag two fingers up or down to pan, zoom, rotate, and
pitch; double tap to zoom in and tap with two fingers to zoom out. The wheel, a
touchpad pinch, and the arrow and plus and minus keys work too. `gestures` turns
some off, and `cooperative` leaves one-finger drags to a scrolling parent:

```ts
MapLibreMap({
  controller: this.map,
  style: "https://tiles.openfreemap.org/styles/liberty",
  gestures: { rotate: false, cooperative: true },
  onGestureStart: () => {
    this.following = false;
  },
});
```

`MapController` reads and moves the camera from anywhere: its `camera` and
`styleLoaded` are observable, `getCamera()` reads the camera right now, and its
camera methods resolve with how the move ended. `frameCamera` and
`pixelForLatLng()` follow the frame on screen, for content that moves with the
map. It also exposes the FFI runtime, map, and render session for what this
library doesn't wrap yet.

### Map content

An app declares what it draws over the style as data: sources, layers, and
images, in a `MapContent` that it passes to `MapLibreMap`. A `@Computed` getter
that reads the app's state makes a new value when that state changes, and the
map compares it with what it applied, by ID, and changes only what differs: a
property in place, a GeoJSON source's data, a layer's position. Each style the
map loads gets the content again, so it lasts across style changes, and
`snapshot()` takes the same content.

```ets
@Local places: GeoJsonFeatureCollection = { type: 'FeatureCollection', features: [] };
@Local color: string = '#1e88e5';
// Read once: the map compares images by reference.
private pin: PremultipliedRgba8Image = readPixelMap(PIN);

@Computed
get content(): MapContent {
  return {
    sources: [{ id: 'places', json: { 'type': 'geojson', 'data': this.places } }],
    layers: [{
      id: 'places', type: 'circle', source: 'places',
      paint: { 'circle-color': match(get('kind'), [['museum', '#fb8c00']], this.color) },
      // Under the base style's labels.
      below: (layer: StyleLayerInfo) => layer.type === 'symbol',
    }],
    images: [{ id: 'pin', image: this.pin }],
  };
}

build() {
  MapLibreMap({
    controller: this.map,
    style: 'https://tiles.openfreemap.org/styles/liberty',
    content: this.content,
  })
}
```

Layers are style-spec JSON with typed `id`, `type`, `source`, `filter`, and zoom
range, and `paint` and `layout` records whose values are plain values or this
library's expressions. Layers go on top, or under the base-style layer that
`below` names or picks, in their order in `layers`. A source or layer that the
map rejects is reported to `onMapError` and left out until it changes.
`readPixelMap()` turns an ArkUI `PixelMap` into a style image.

### The style API

For everything else, the style API is MapLibre Native FFI's: `controller.map`
adds and changes sources, layers, images, and feature state, and
`controller.renderSession` queries features:

```ets
MapLibreMap({ controller: this.map, style: STYLE, content: this.content })
  .onClick((event: ClickEvent) => {
    // The click's point is in vp from the map's corner, as queries take it.
    this.map.renderSession?.queryRenderedFeatures({ kind: 'point', value: { x: event.x, y: event.y } },
      { layerIds: ['places'] });
  })
```

What an app adds through `controller.map` is gone in the next style, so it adds
it again in `onStyleLoaded`. (Feature state of a source re-added under the same
ID can carry over.) The demo's style page shows content driven by state, a
snapshot of it, and feature state on tap. On an idle map, a feature state change
draws only from the frame after the one that applies it, so until FFI fixes
that, request one, as the demo does with `map.discarding.requestRepaint()` from
a delayed frame callback (see [docs/ffi-feedback.md](docs/ffi-feedback.md)).

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

[AGENTS.md](AGENTS.md) describes the layout, the tasks, and how the build works
without hvigor.

[MapLibre Compose]: https://maplibre.org/maplibre-compose/
[MapLibre Native]: https://github.com/maplibre/maplibre-native
[MapLibre Native FFI]: https://maplibre.org/maplibre-native-ffi/
[mise]: https://mise.jdx.dev
[ohpm]: https://ohpm.openharmony.cn/
