import { Expression } from '../expression/Expressions';
import { GeoJsonFeature } from '../geometry/GeoJson';
import { MapClickEvent } from '../map/MapClickEvent';

/**
 * A layer of the style, by its ID, type, and source. A `LayerPredicate` gets
 * those of the base style: the style that the map loaded, without its content.
 * The map creates it; fields may be added in later releases. It's never one of
 * the layers that the library adds itself, such as the user location
 * indicator's.
 */
export interface LayerSummary {
  /** The layer's ID. */
  id: string;
  /** The layer's style-spec type, such as `'fill'` or `'symbol'`. Open identity. */
  type: string;
  /** The ID of the source that the layer draws, or undefined for a layer without one. */
  source?: string;
  /** The layer of a vector source that the layer draws, or undefined for a source without layers. */
  sourceLayer?: string;
}

/**
 * Picks a layer of the base style to place a layer under, for
 * `StyleLayer.below` and `UserLocationIndicatorOptions.below`.
 *
 * It runs on the UI thread whenever the map places a layer that uses it, once
 * for each base layer from the bottom up until it returns `true`, so it must
 * be fast and pure; the map doesn't observe the state it reads. When it
 * throws, the map reports the exception to `MaplibreMap.onError` and the log,
 * and counts it as no match for that layer or the indicator.
 */
export type LayerPredicate = (layer: LayerSummary) => boolean;

/** A click on a layer's features, which `StyleLayer.onClick` and `onLongClick` get. */
export interface FeatureClickEvent extends MapClickEvent {
  /**
   * The layer's features within its `hitPadding` of the click, front first,
   * as the layer drew them, with the geometry as it drew them. Never empty.
   */
  features: GeoJsonFeature[];
}

/**
 * Handles a click on a layer's features. It returns `true` to consume the
 * click, so the layers under it and `MaplibreMap.onUnhandledClick` don't get
 * it, or `false` to pass it on.
 *
 * It runs on the UI thread. When it throws, the map logs the exception and
 * passes the click on.
 */
export type FeatureClickHandler = (event: FeatureClickEvent) => boolean;

/**
 * A layer, as the style spec writes it, where it goes, and what a click on its
 * features does.
 *
 * ```ets
 * const park: StyleLayer = {
 *   id: 'park', type: 'fill', source: 'places', filter: eq(geometryType(), 'Polygon'),
 *   paint: { 'fill-color': '#66bb6a', 'fill-opacity': 0.6 },
 *   below: (layer: LayerSummary) => layer.type === 'symbol',
 * };
 * ```
 *
 * A change to `paint`, `layout`, `filter`, or the zoom range changes the layer
 * in place, and a change to `type`, `source`, or `sourceLayer` replaces it.
 * The map compares neither the handlers nor `hitPadding`; it uses those of
 * the latest content. An invalid expression goes to `MaplibreMap.onError`.
 */
export interface StyleLayer {
  /** The layer's ID, unique in the content and the base style. */
  id: string;
  /** The style-spec type: `'fill'`, `'line'`, `'circle'`, `'symbol'`, `'raster'`, and so on. Open identity. */
  type: string;
  /** The ID of the source the layer draws, from the content or the base style. */
  source?: string;
  /** The layer of a vector source that the layer draws. */
  sourceLayer?: string;
  /** Which features the layer draws: those for which it's true. */
  filter?: Expression;
  /** The zoom from which the layer shows. */
  minZoom?: number;
  /** The zoom from which the layer hides. */
  maxZoom?: number;
  /** Paint properties by their style-spec names, as expressions or plain values. */
  paint?: Record<string, Object>;
  /** Layout properties by their style-spec names, as expressions or plain values. */
  layout?: Record<string, Object>;
  /**
   * Places the layer under another: the content layer or base-style layer
   * with this ID, or the lowest base-style layer that the predicate picks,
   * such as `(layer: LayerSummary) => layer.type === 'symbol'` to go below
   * the labels, or `() => true` to go below everything. Under a content
   * layer, it goes directly under that layer, wherever that layer goes.
   * Without it, when no layer matches, or when content layers name each
   * other in a cycle, the layer goes on top. Layers placed under the same
   * layer keep their order in `MapContent.layers`.
   *
   * The map compares it by the layer it picks on each pass, so a new
   * predicate that picks the same layer moves nothing.
   */
  below?: string | LayerPredicate;
  /**
   * How far from a click, in vp, the layer's features count as under it: a
   * square of this many vp on each side of the click, so small circles and
   * thin lines are easier to tap. Finite and at least 0; 0 by default. Another
   * value goes to `MaplibreMap.onError` once, when the map applies the
   * content, and counts as 0.
   */
  hitPadding?: number;
  /**
   * Handles a click on the layer's features. After `MaplibreMap.onMapClick`
   * passes a click, the layers with features under it get it from the top
   * layer down, until one consumes it.
   */
  onClick?: FeatureClickHandler;
  /**
   * Handles a long click on the layer's features, a long press or a right
   * click, as `onClick` does a click, after `MaplibreMap.onMapLongClick`.
   */
  onLongClick?: FeatureClickHandler;
}
