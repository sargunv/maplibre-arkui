import image from '@ohos.multimedia.image';

import { GeoJsonObject } from '../geometry/GeoJson';
import { LatLng } from '../geometry/Geometry';

/**
 * A source of the style that `MapStyle` reads.
 *
 * A handle belongs to one style. It expires when that style goes, as
 * `MapStyle` describes, and when its source leaves the style: by `remove()`,
 * or as the content removes or replaces it. Then its writes resolve `false`.
 * Get a new handle for the source of a new style. Its writes throw an `Error`
 * for a source of the content, as `MapStyle` describes.
 *
 * The map creates it; members may be added in later releases.
 */
export interface SourceHandle {
  /** The source's ID. */
  readonly id: string;
  /**
   * The source's type, such as `'geojson'` or `'raster'`, as the style spec
   * names it. Open identity.
   */
  readonly type: string;
  /**
   * The source's attribution, as HTML, when the map made the handle, or `''`
   * for none. A source whose TileJSON loads later can gain one.
   */
  readonly attribution: string;

  /**
   * Removes the source from the style, and resolves `true` once it's gone,
   * when the handle expires. It rejects when the map keeps the source, such as
   * while a layer draws it; then the handle holds.
   */
  remove(): Promise<boolean>;
}

/** A GeoJSON source of the style, as `SourceHandle` describes. */
export interface GeoJsonSourceHandle extends SourceHandle {
  /**
   * Replaces the source's data with a GeoJSON object, or with the GeoJSON at
   * the URL `data`, and keeps the source's options, such as its clustering. It
   * rejects for data that the map can't read.
   */
  setData(data: GeoJsonObject | string): Promise<boolean>;
}

/** An image source of the style, as `SourceHandle` describes. */
export interface ImageSourceHandle extends SourceHandle {
  /**
   * Replaces the source's image with the pixels of `image`, which it reads
   * during the call, so the app can release the pixel map once the call
   * returns. It throws an `Error` for a pixel map that isn't `RGBA_8888` or
   * `BGRA_8888`, or can't be read.
   */
  setImage(image: image.PixelMap): Promise<boolean>;

  /** Makes the source load its image from `url`. */
  setUrl(url: string): Promise<boolean>;

  /**
   * Moves the image to the four corners of `coordinates`, clockwise from the
   * top left. It throws an `Error` unless there are four, each with a finite
   * latitude from -90 to 90 and a finite longitude.
   */
  setCoordinates(coordinates: LatLng[]): Promise<boolean>;
}
