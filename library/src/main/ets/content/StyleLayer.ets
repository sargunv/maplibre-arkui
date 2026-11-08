import { Expression } from '../expression/Expressions';
import { GeoJsonFeature } from '../geometry/GeoJson';
import { MapClickEvent } from '../map/MapClickEvent';

/**
 * A layer of the base style: the loaded style without the map's content.
 * Fields may be added in later releases.
 */
export interface LayerSummary {
  /** The layer's ID. */
  readonly id: string;
  /** The layer's style-spec type, such as `'fill'` or `'symbol'`. Open identity. */
  readonly type: string;
  /** The ID of the layer's source, or undefined for a layer without one. */
  readonly source: string | undefined;
  /** The source layer that the layer draws, or undefined for a source without layers. */
  readonly sourceLayer: string | undefined;
}

/**
 * Picks a layer of the base style to place a layer under. The map calls it on
 * the UI thread for each base-style layer, from the bottom up, until it
 * returns `true`. The map doesn't call it again when state that it reads
 * changes. When it throws, the map reports the error to `onError` and places
 * the layer on top.
 */
export type LayerPredicate = (layer: LayerSummary) => boolean;

/** A click on a layer's features. */
export interface FeatureClickEvent extends MapClickEvent {
  /** The layer's features within `hitPadding` of the click, topmost first. Never empty. */
  readonly features: GeoJsonFeature[];
}

/**
 * Handles a click on a layer's features. Return `true` to consume the click,
 * so lower layers and `onUnhandledClick` don't get it. It runs on the UI
 * thread; if it throws, the map logs the error and passes the click on.
 */
export type FeatureClickHandler = (event: FeatureClickEvent) => boolean;

/**
 * A layer of the map's content, with its position and click handlers. A layer
 * that the map rejects, such as for an invalid property, is reported to
 * `onError` as a `ContentError`.
 */
export interface StyleLayer {
  /** The layer's ID, which no other layer in the style may have. */
  id: string;
  /** The style-spec type, such as `'fill'` or `'symbol'`. Open identity. */
  type: string;
  /** The ID of the source to draw, from the content or the base style. */
  source?: string;
  /** The source layer to draw, for a vector source. */
  sourceLayer?: string;
  /** Draws only the features for which this is true. */
  filter?: Expression;
  /** The zoom at which the layer starts to show. */
  minZoom?: number;
  /** The zoom at which the layer stops showing. */
  maxZoom?: number;
  /** Paint properties by their style-spec names, as expressions or plain values. */
  paint?: Record<string, Object>;
  /** Layout properties by their style-spec names, as expressions or plain values. */
  layout?: Record<string, Object>;
  /**
   * The layer to place this layer directly under: the layer with this ID, or
   * the lowest base-style layer that the predicate picks. On top by default,
   * and when nothing matches.
   */
  below?: string | LayerPredicate;
  /**
   * How far from a click, in vp, a feature still counts as clicked. Finite and
   * at least 0; 0 by default. An invalid value is reported to `onError` and
   * counts as 0.
   */
  hitPadding?: number;
  /** Handles a click on the layer's features. Layers get a click from the top down. */
  onClick?: FeatureClickHandler;
  /** Handles a long press or right click on the layer's features. */
  onLongClick?: FeatureClickHandler;
}
