import { LayerPredicate } from '../content/StyleLayer';

/**
 * How the map draws its `userLocation`. Fields left out keep their defaults.
 *
 * A color that can't be resolved, such as a missing resource, is reported to
 * the map's `onError`, and its default is used instead. Color resources follow
 * dark mode.
 */
export interface UserLocationIndicatorOptions {
  /**
   * Whether the map draws the indicator. True by default. The camera can
   * still follow `userLocation` while it's false.
   */
  visible?: boolean;
  /**
   * The color of the default dot and arrow. `'#1e88e5'` by default.
   */
  color?: ResourceColor;
  /**
   * The fill of the circle that shows the location's `accuracy`. By default,
   * `color` at 15% of its alpha.
   */
  accuracyColor?: ResourceColor;
  /**
   * The border of the circle that shows the location's `accuracy`. By
   * default, `color` at 50% of its alpha.
   */
  accuracyBorderColor?: ResourceColor;
  /**
   * The ID of an image to draw instead of the default dot, from the style or
   * the map's `content.images`. `''` draws none.
   */
  topImage?: string;
  /**
   * The ID of an image to draw instead of the default arrow, under `topImage`.
   * Draw it pointing north; the map turns it with the heading or course.
   * `''` draws none.
   */
  bearingImage?: string;
  /**
   * The ID of an image to draw instead of the default shadow, under the other
   * images. `''` draws none.
   */
  shadowImage?: string;
  /**
   * Draws the indicator under a layer: the base-style or content layer with
   * this ID, or the lowest base-style layer that the predicate picks. By
   * default, or when no layer matches, it draws above every layer.
   */
  below?: string | LayerPredicate;
}
