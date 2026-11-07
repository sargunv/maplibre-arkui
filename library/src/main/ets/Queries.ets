// Feature queries of the frame that a map drew, and of its sources.

import {
  RenderedFeature as FfiRenderedFeature,
  RenderedQueryGeometry,
  RenderSessionHandle,
  SourceFeature as FfiSourceFeature,
} from '@maplibre/native-ffi';

import { Expression } from './Expressions';
import { GeoJsonFeature } from './GeoJson';
import { ScreenPoint } from './Geometry';

/** Which features `MapController.queryRenderedFeatures()` finds. */
export interface RenderedFeatureQueryOptions {
  /**
   * How far from the point, in vp, features count as under it: the query
   * covers a square of this many vp on each side of the point. Finite and at
   * least 0; 0 by default, which covers the point alone.
   */
  hitPadding?: number;
  /** The IDs of the layers to query. Every layer by default. */
  layers?: string[];
  /** Which features count: those for which it's true. Every feature by default. */
  filter?: Expression;
}

/**
 * A feature that a layer drew, as `MapController.queryRenderedFeatures()`
 * finds it. The map creates it; fields may be added in later releases.
 */
export interface RenderedFeature {
  /** The feature, with the geometry as the layer drew it. */
  feature: GeoJsonFeature;
  /** The ID of the layer that drew the feature. */
  layerId: string;
  /** The ID of the feature's source. */
  sourceId: string;
  /** The layer of a vector source that the feature is in, or undefined for a source without layers. */
  sourceLayer?: string;
  /** The feature's state, by name. Empty for a feature without state. */
  state: Record<string, Object>;
}

/** Which features `MapController.querySourceFeatures()` finds. */
export interface SourceFeatureQueryOptions {
  /** The layers of a vector source to query. A vector source finds features only in those named here. */
  sourceLayers?: string[];
  /** Which features count: those for which it's true. Every feature by default. */
  filter?: Expression;
}

/**
 * A feature of a source, as `MapController.querySourceFeatures()` finds it.
 * The map creates it; fields may be added in later releases.
 */
export interface SourceFeature {
  /** The feature, with the geometry as its tiles hold it. */
  feature: GeoJsonFeature;
  /** The layer of a vector source that the feature is in, or undefined for a source without layers. */
  sourceLayer?: string;
}

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
