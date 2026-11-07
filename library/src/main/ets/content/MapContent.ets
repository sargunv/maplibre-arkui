import { StyleImage } from './StyleImage';
import { StyleLayer } from './StyleLayer';
import { StyleSource } from './StyleSource';

/**
 * What a map draws on top of its base style: sources, the layers that draw
 * them, and the images that symbol layers show. Each style the map loads gets
 * all of it, so it lasts across style changes.
 *
 * It's a value. To change what the map draws, give `MaplibreMap` a new one,
 * such as from a `@Computed` getter that reads the app's state. The map
 * compares it with the content it applied, by ID, and changes only what
 * differs.
 */
export interface MapContent {
  /** The sources that the layers draw, besides the base style's. */
  sources?: StyleSource[];
  /** The layers, from bottom to top among those that go under the same layer. */
  layers?: StyleLayer[];
  /** The images that the layers name, such as in `icon-image`. */
  images?: StyleImage[];
}
