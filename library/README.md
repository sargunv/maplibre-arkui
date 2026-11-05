# @maplibre/arkui

ArkUI components for MapLibre Native on HarmonyOS and OpenHarmony. Not usable
yet; see the [repository](https://github.com/sargunv/maplibre-arkui).

## Style expressions

Build [style expressions] with functions named after their operators, and pass
their JSON to FFI's style functions:

```ets
import { get, interpolate, linear, match, zoom } from '@maplibre/arkui';

const radius = interpolate(linear(), zoom(), [[0, 2], [12, get('size')]]);
const color = match(get('kind'), [['park', '#8c8'], [['lake', 'river'], '#88c']], '#ccc');
map.setStyleLayerProperty('places', 'circle-radius', radius.json);
map.setStyleLayerProperty('places', 'circle-color', color.json);
```

`new Expression(json)` and `call(operator, ...args)` cover the operators that
have no function.

[style expressions]: https://maplibre.org/maplibre-style-spec/expressions/
