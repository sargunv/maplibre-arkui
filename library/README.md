# @maplibre/arkui

ArkUI components for MapLibre Native on HarmonyOS and OpenHarmony: a
`MapLibreMap` component, a `MapController` that reads and moves its camera, and
`snapshot()` for still images. Early, and not on ohpm yet; see the
[repository](https://github.com/sargunv/maplibre-arkui).

## Style expressions

Build [style expressions] with functions named after their operators, and pass
them to FFI's style functions:

```ets
import { get, interpolate, linear, match, zoom } from '@maplibre/arkui';

const radius = interpolate(linear(), zoom(), [[0, 2], [12, get('size')]]);
const color = match(get('kind'), [['park', '#8c8'], [['lake', 'river'], '#88c']], '#ccc');
map.setStyleLayerProperty('places', 'circle-radius', radius);
map.setStyleLayerProperty('places', 'circle-color', color);
```

`new Expression(json)` and `call(operator, ...args)` cover the operators that
have no function.

## Snapshots

`snapshot()` renders a still image of a map that isn't on screen, as a
`PixelMap` for an `Image`:

```ets
@Local preview: image.PixelMap | undefined = undefined;

async aboutToAppear(): Promise<void> {
  this.preview = await snapshot({
    style: 'https://tiles.openfreemap.org/styles/liberty',
    width: 320,
    height: 200,
    camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
  });
}
```

For an image of a `MapLibreMap`, pass its style and its controller's camera,
through `cameraToOptions()`, when `getCamera()` returns one. Without `camera`,
the image uses the style's default camera; with it, the fields it leaves out
take MapLibre's defaults, not the style's.

## Requests, offline regions, and logs

These are [MapLibre Native FFI]'s API, which this package re-exports. Maps and
snapshots share a default runtime unless the app passes its own; set request
handlers on it, before or after maps appear:

```ets
const runtime = await getDefaultRuntime();
runtime.discarding.setResourceTransform({
  rules: [{
    flags: UrlMatchFlag.glob,
    url: 'https://tiles.example.com/**',
    parameters: [{ name: 'key', value: API_KEY }],
  }],
});
```

For other rewrites, pass a `callback` instead of `rules`; it must answer every
request. On OpenHarmony, FFI has no header transform: serve the requests that
need headers with `runtime.setResourceProvider()` instead. See FFI's [network
guide].

The default runtime's cache database is `maplibre-cache.db` in the app's files
directory, so [offline regions] last between launches. The library owns the
runtime's event handler, so watch a download's progress with
`addRuntimeEventListener()`:

```ets
const region = await runtime.createOfflineRegion(definition, new util.TextEncoder().encodeInto('Paris'));
addRuntimeEventListener(runtime, (event: RuntimeEvent) => {
  const payload = event.payload;
  if (payload.kind === 'offlineRegionStatus' && payload.value.regionId === region.id) {
    this.status = payload.value.status;
  }
});
await runtime.setOfflineRegionObserved(region.id, RuntimeEventFlag.offlineRegionStatusChanged);
await runtime.setOfflineRegionDownloadState(region.id, OfflineRegionDownloadState.active);
```

MapLibre logs to hilog with the tag `MapLibreNative`. To take the logs, call
`setLogCallback()`; its `platformSeverities` keeps some in hilog too.

[MapLibre Native FFI]: https://maplibre.org/maplibre-native-ffi/
[network guide]: https://maplibre.org/maplibre-native-ffi/guides/network/
[offline regions]: https://maplibre.org/maplibre-native-ffi/guides/offline/
[style expressions]: https://maplibre.org/maplibre-style-spec/expressions/
