import { LayerPredicate } from '../content/StyleLayer';

/**
 * How the map draws `userLocation`: whether it draws it, the colors of its
 * default images and of its accuracy circle, images of the style's own in
 * their place, and the layer it goes under. Fields that it leaves out keep
 * their defaults. For more, such as transitions or sizes, set `visible` to
 * false and draw a `location-indicator` layer in the map's `content`.
 *
 * ```ets
 * MaplibreMap({
 *   controller: this.map,
 *   style: STYLE,
 *   userLocation: this.location,
 *   userLocationIndicator: { color: '#e53935', below: 'road-label' },
 * })
 * ```
 *
 * A color that ArkUI can't resolve, such as a missing resource, goes to the
 * map's `onError` and the log, and its default takes its place. The colors
 * resolve again when the color mode changes, so a color resource can have a
 * dark-mode value.
 *
 * The map compares the options with the last ones by value, and a predicate
 * `below` by the layer that it picks, so options that `build()` writes anew
 * change nothing that stayed the same.
 */
export interface UserLocationIndicatorOptions {
  /**
   * Whether the map draws the indicator. True by default; false draws nothing,
   * while the camera still follows `userLocation`.
   */
  visible?: boolean;
  /**
   * The color of the default dot, which has a white border, and of the
   * default arrow. `'#1e88e5'` by default.
   */
  color?: ResourceColor;
  /**
   * The fill of the circle that shows the location's `accuracy`. By default,
   * `color` at 15% of its own alpha.
   */
  accuracyColor?: ResourceColor;
  /**
   * The border of the circle that shows the location's `accuracy`. By
   * default, `color` at 50% of its own alpha.
   */
  accuracyBorderColor?: ResourceColor;
  /**
   * The name of the image that marks the location, in place of the default
   * dot: one of the style's, or of the map's `content.images`. `''` draws none.
   */
  topImage?: string;
  /**
   * The name of the image under `topImage` that the heading or course turns,
   * pointing north before it turns, in place of the default arrow. It shows
   * only while there is a heading or a course. `''` draws none.
   */
  bearingImage?: string;
  /**
   * The name of the image under the others, in place of the default soft
   * shadow. `''` draws none.
   */
  shadowImage?: string;
  /**
   * Places the indicator under another layer, as `StyleLayer.below` places a
   * layer: the base-style or content layer with this ID, or the lowest
   * base-style layer that the predicate picks. Without it, or when no layer
   * matches as the indicator appears, the indicator goes above every layer.
   * A layer that the app adds through `MapController.withFfiMap()` doesn't
   * count.
   */
  below?: string | LayerPredicate;
}
