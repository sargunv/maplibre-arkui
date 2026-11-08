import { StyleLayer } from './StyleLayer';
import { StyleSource } from './StyleSource';

/**
 * Sources and layers that a map adds to every style it loads. To change them,
 * pass the map a new value; the map changes only what differs. The map also
 * adds the images and resource colors that the layers' expressions use.
 */
export interface MapContent {
  /** Sources to add to the style. */
  sources?: StyleSource[];
  /** Layers to add to the style, from bottom to top. */
  layers?: StyleLayer[];
}
