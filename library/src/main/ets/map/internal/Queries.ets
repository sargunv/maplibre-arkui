// Feature queries of the frame that a map drew, and of its sources.

import {
  RenderedFeature as FfiRenderedFeature,
  RenderedQueryGeometry,
  RenderSessionHandle,
  SourceFeature as FfiSourceFeature,
} from '@maplibre/native-ffi';

import { Expression } from '../../expression/Expressions';
import { GeoJsonFeature } from '../../geometry/GeoJson';
import { ScreenPoint } from '../../geometry/Geometry';
import { RenderedFeature, SourceFeature, SourceFeatureQueryOptions } from '../MapController';

// Throws for a hitPadding that isn't finite or is below 0.
export function checkHitPadding(hitPadding: number | undefined): number {
  const padding = hitPadding ?? 0;
  if (!Number.isFinite(padding) || padding < 0) {
    throw new Error(`A query's hitPadding must be finite and at least 0: ${hitPadding}`);
  }
  return padding;
}

// The features that `session` drew within `hitPadding` vp of `point`, in the
// layers that `layers` names, or in all. MapLibre Native lists each layer's
// features front first, but the layers in no set order.
export async function queryRendered(session: RenderSessionHandle, point: ScreenPoint, hitPadding: number,
  layers: string[] | undefined, filter: Expression | undefined): Promise<RenderedFeature[]> {
  const geometry: RenderedQueryGeometry = hitPadding === 0 ?
    { kind: 'point', value: { x: point.x, y: point.y } } :
    {
      kind: 'box',
      value: {
        min: { x: point.x - hitPadding, y: point.y - hitPadding },
        max: { x: point.x + hitPadding, y: point.y + hitPadding },
      },
    };
  const found = await session.queryRenderedFeatures(geometry, { layerIds: layers, filter: filter });
  return found.map(toRenderedFeature);
}

export async function querySource(session: RenderSessionHandle, sourceId: string,
  options: SourceFeatureQueryOptions | undefined): Promise<SourceFeature[]> {
  const found = await session.querySourceFeatures(sourceId,
    { sourceLayerIds: options?.sourceLayers, filter: options?.filter });
  return found.map((feature: FfiSourceFeature): SourceFeature => ({
    feature: feature.feature as GeoJsonFeature,
    sourceLayer: feature.sourceLayerId === '' ? undefined : feature.sourceLayerId,
  }));
}

function toRenderedFeature(feature: FfiRenderedFeature): RenderedFeature {
  return {
    feature: feature.feature as GeoJsonFeature,
    layerId: feature.layerId,
    sourceId: feature.sourceId,
    sourceLayer: feature.sourceLayerId === '' ? undefined : feature.sourceLayerId,
    // FFI gives no state object for a feature without state.
    state: (feature.state as Record<string, Object> | undefined) ?? {},
  };
}
