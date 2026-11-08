import { StyleImage } from './StyleImage';
import { StyleLayer } from './StyleLayer';
import { StyleSource } from './StyleSource';

/**
 * Sources, layers, and images that a map adds to every style it loads. To
 * change them, pass the map a new value; the map changes only what differs.
 */
export interface MapContent {
  /** Sources to add to the style. */
  sources?: StyleSource[];
  /** Layers to add to the style, from bottom to top. */
  layers?: StyleLayer[];
  /** Images that layers can name, such as in `icon-image`. */
  images?: StyleImage[];
}
