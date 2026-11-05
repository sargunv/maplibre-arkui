# @maplibre/arkui

ArkUI components for MapLibre Native on HarmonyOS and OpenHarmony: a
`MapLibreMap` component and a `MapController` that reads and moves its camera.
Early, and not on ohpm yet; see the
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

[style expressions]: https://maplibre.org/maplibre-style-spec/expressions/
