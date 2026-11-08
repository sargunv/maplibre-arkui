// Examples for the "Expressions in ArkTS" page and the FFI escape hatch.

import { MapDebugFlag, MapHandle } from '@maplibre/native-ffi';

import {
  color,
  call,
  eq,
  Expression,
  geometryType,
  get,
  interpolate,
  linear,
  literal,
  MapController,
  match,
  StyleLayer,
  zoom,
} from '@maplibre/arkui';

// #region expressions
const PARKS: StyleLayer = {
  id: 'parks', type: 'circle', source: 'places',
  filter: eq(geometryType(), 'Point'),
  paint: {
    'circle-radius': interpolate(linear(), zoom(), [[8, 2], [16, 10]]),
    'circle-color': match(get('kind'), [['park', color('#43a047')], [['lake', 'river'], color('#1e88e5')]], color('#9e9e9e')),
  },
};
// #endregion expressions

// #region raw
const IN_PARKS: Expression = call('in', get('class'), literal(['park', 'garden']));
const NAME: Expression = new Expression(['get', 'name']);
// #endregion raw

// #region ffi-map
async function showTileBorders(controller: MapController): Promise<void> {
  await controller.withFfiMap((map: MapHandle) => map.setDebugFlags(MapDebugFlag.tileBorders));
}
// #endregion ffi-map

export const EXPRESSION_VALUES: Object[] = [PARKS, IN_PARKS, NAME, showTileBorders];
