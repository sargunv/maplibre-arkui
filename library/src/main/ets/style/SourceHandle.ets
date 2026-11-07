import image from '@ohos.multimedia.image';

import { readPixelMap } from '../content/internal/PixelMaps';
import { GeoJsonObject } from '../geometry/GeoJson';
import { LatLng } from '../geometry/Geometry';
import { checkLatLng } from '../geometry/internal/FfiGeometry';
import { registerSourceKey, SourceKey, sourceKeyOf } from './internal/HandleKeys';
import { replaced } from './internal/StyleCommands';

/**
 * A source of the style that `MapStyle` reads.
 *
 * A handle belongs to one style. It expires when that style goes, as
 * `MapStyle` describes, and when its source leaves the style: by `remove()`,
 * or as the content removes or replaces it. Then its writes resolve `false`.
 * Get a new handle for the source of a new style. Its writes throw an `Error`
 * for a source of the content, as `MapStyle` describes.
 *
 * A GeoJSON source's handle is a `GeoJsonSourceHandle`, and an image source's
 * an `ImageSourceHandle`; match them with `instanceof`. Subclasses for other
 * types and members may be added in later releases. The map creates handles;
 * apps can't.
 */
export class SourceHandle {
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
   * Whether the source is one of the map's content, when the map made the
   * handle. The handle's writes throw for a source of the content.
   */
  readonly fromContent: boolean;

  /** @internal The map creates handles. */
  constructor(key: SourceKey) {
    this.id = key.id;
    this.type = key.type;
    this.attribution = key.attribution;
    this.fromContent = key.fromContent;
    registerSourceKey(this, key);
  }

  /**
   * Removes the source from the style, and resolves `true` once it's gone,
   * when the handle expires. It rejects when the map keeps the source, such as
   * while a layer draws it; then the handle holds.
   */
  remove(): Promise<boolean> {
    const key = sourceKeyOf(this);
    return key.send(`removing source ${this.id}`, (map) => map.removeStyleSource(this.id))
      .then((removed: boolean): boolean => {
        if (removed && key.holds()) {
          key.style.reconciler.sourceRemoved(this.id);
        }
        return removed;
      });
  }
}

/** A GeoJSON source of the style, as `SourceHandle` describes. */
export class GeoJsonSourceHandle extends SourceHandle {
  /**
   * Replaces the source's data with a GeoJSON object, or with the GeoJSON at
   * the URL `data`, and keeps the source's options, such as its clustering. It
   * resolves `false` when newer data replaces it before the source has it, and
   * rejects for data that the map can't read.
   */
  setData(data: GeoJsonObject | string): Promise<boolean> {
    return sourceKeyOf(this).send(`setting the data of source ${this.id}`, (map) => typeof data === 'string' ?
      map.setGeoJsonSourceUrl(this.id, data) : map.setGeoJsonSourceData(this.id, data), replaced);
  }
}

/** An image source of the style, as `SourceHandle` describes. */
export class ImageSourceHandle extends SourceHandle {
  /**
   * Replaces the source's image with the pixels of `pixelMap`, which it reads
   * during the call, so the app can release the pixel map once the call
   * returns. It throws an `Error` for a pixel map that isn't `RGBA_8888` or
   * `BGRA_8888`, or can't be read.
   */
  setImage(pixelMap: image.PixelMap): Promise<boolean> {
    const pixels = readPixelMap(pixelMap);
    return sourceKeyOf(this).send(`setting the image of source ${this.id}`,
      (map) => map.setImageSourceImage(this.id, pixels));
  }

  /** Makes the source load its image from `url`. */
  setUrl(url: string): Promise<boolean> {
    return sourceKeyOf(this).send(`setting the URL of source ${this.id}`,
      (map) => map.setImageSourceUrl(this.id, url));
  }

  /**
   * Moves the image to the four corners of `coordinates`, clockwise from the
   * top left. It throws an `Error` unless there are four, each with a finite
   * latitude from -90 to 90 and a finite longitude.
   */
  setCoordinates(coordinates: LatLng[]): Promise<boolean> {
    if (coordinates.length !== 4) {
      throw new Error(`An image source needs its four corners, not ${coordinates.length}`);
    }
    coordinates.forEach((coordinate: LatLng) => checkLatLng(coordinate, 'Each corner of an image source'));
    return sourceKeyOf(this).send(`setting the coordinates of source ${this.id}`,
      (map) => map.setImageSourceCoordinates(this.id, coordinates));
  }
}
