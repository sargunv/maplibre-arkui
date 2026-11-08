import { CommandCompletion, RenderSessionHandle } from '@maplibre/native-ffi';
import image from '@ohos.multimedia.image';

import { readPixelMap } from '../content/internal/PixelMaps';
import { GeoJsonFeature, GeoJsonFeatureCollection, GeoJsonObject } from '../geometry/GeoJson';
import { LatLng } from '../geometry/Geometry';
import { checkLatLng } from '../geometry/internal/FfiGeometry';
import { registerSourceKey, SourceKey, sourceKeyOf } from './internal/HandleKeys';
import {
  checkCount,
  checkSourceLayer,
  getState,
  queryCluster,
  removeState,
  setState,
} from './internal/SourceFeatures';
import { replaced } from './internal/StyleCommands';

/**
 * A source of the loaded style. Match the subclasses with `instanceof`.
 * Subclasses and members may be added in later releases. Only the library
 * creates handles.
 *
 * A handle expires when its style is replaced or its source leaves the style.
 * After that, reads resolve undefined and writes resolve `false`. Writes throw
 * an `Error` for a source that the content owns, except feature state writes.
 *
 * Feature state is a set of values on one feature, which `featureState()`
 * reads. It works on every source, including the content's. Due to
 * [maplibre-native-ffi#1746](https://github.com/maplibre/maplibre-native-ffi/issues/1746),
 * it can carry over to a later source with the same ID; call
 * `resetFeatureStates()` to clear it.
 */
export class SourceHandle {
  /** The source's ID. */
  readonly id: string;
  /** The source's style-spec type, such as `'geojson'` or `'raster'`. Open identity. */
  readonly type: string;
  /** The source's attribution as HTML, or `''` for none, when the handle was made. */
  readonly attribution: string;
  /** Whether the source belonged to the map's content when the handle was made. */
  readonly fromContent: boolean;

  /** @internal The map creates handles. */
  constructor(key: SourceKey) {
    this.id = key.id;
    this.type = key.type;
    this.attribution = key.attribution;
    this.fromContent = key.fromContent;
    registerSourceKey(this, key);
  }

  /** Removes the source from the style. Rejects while a layer draws it. */
  remove(): Promise<boolean> {
    const key = sourceKeyOf(this);
    // The handle expires as the removal lands, before any later command's
    // answer, so a write sent after it resolves false.
    return key.send(`removing source ${this.id}`, (map) => map.removeStyleSource(this.id)
      .then((completion: CommandCompletion): CommandCompletion => {
        if (key.holds()) {
          key.style.reconciler.sourceRemoved(this.id);
        }
        return completion;
      }));
  }
}

/**
 * A GeoJSON source of the loaded style.
 *
 * The cluster methods take a cluster feature of this source, such as from a
 * click or a query. They resolve undefined for a feature that isn't one of the
 * source's current clusters.
 */
export class GeoJsonSourceHandle extends SourceHandle {
  /**
   * Replaces the source's data with a GeoJSON object or a URL, and keeps its
   * other options. Resolves `false` when newer data replaces it first, and
   * rejects for data that the map can't read.
   */
  setData(data: GeoJsonObject | string): Promise<boolean> {
    return sourceKeyOf(this).send(`setting the data of source ${this.id}`, (map) => typeof data === 'string' ?
      map.setGeoJsonSourceUrl(this.id, data) : map.setGeoJsonSourceData(this.id, data), replaced);
  }

  /** Merges values into a feature's state, replacing values with the same names. */
  setFeatureState(featureId: number | string, state: Record<string, Object>): Promise<boolean> {
    return setState(sourceKeyOf(this), undefined, featureId, state);
  }

  /** A feature's state, which is empty when it has none. */
  getFeatureState(featureId: number | string): Promise<Record<string, Object> | undefined> {
    return getState(sourceKeyOf(this), undefined, featureId);
  }

  /** Removes one value from a feature's state, or the whole state when `key` is left out. */
  removeFeatureState(featureId: number | string, key?: string): Promise<boolean> {
    return removeState(sourceKeyOf(this), undefined, featureId, key);
  }

  /** Removes the state of every feature in the source. */
  resetFeatureStates(): Promise<boolean> {
    return removeState(sourceKeyOf(this), undefined, undefined, undefined);
  }

  /** The zoom at which a cluster splits into smaller clusters or points. */
  getClusterExpansionZoom(cluster: GeoJsonFeature): Promise<number | undefined> {
    return queryCluster(sourceKeyOf(this), cluster, 'expansion zoom',
      (session: RenderSessionHandle, id: number) => session.getClusterExpansionZoom(this.id, id));
  }

  /** The clusters and points that a cluster splits into at the next zoom level. */
  getClusterChildren(cluster: GeoJsonFeature): Promise<GeoJsonFeatureCollection | undefined> {
    return queryCluster(sourceKeyOf(this), cluster, 'children', (session: RenderSessionHandle, id: number) =>
      session.getClusterChildren(this.id, id) as Promise<GeoJsonFeatureCollection>);
  }

  /** Up to `limit` of the points in a cluster, skipping the first `offset`. */
  getClusterLeaves(cluster: GeoJsonFeature, limit: number, offset: number):
    Promise<GeoJsonFeatureCollection | undefined> {
    const most = checkCount('limit', limit);
    const skipped = checkCount('offset', offset);
    return queryCluster(sourceKeyOf(this), cluster, 'leaves', (session: RenderSessionHandle, id: number) =>
      session.getClusterLeaves(this.id, id, most, skipped) as Promise<GeoJsonFeatureCollection>);
  }
}

/** A vector tile source of the loaded style. Its feature state methods take a source layer. */
export class VectorSourceHandle extends SourceHandle {
  /** Merges values into a feature's state, replacing values with the same names. */
  setFeatureState(sourceLayer: string, featureId: number | string, state: Record<string, Object>): Promise<boolean> {
    return setState(sourceKeyOf(this), checkSourceLayer(sourceLayer), featureId, state);
  }

  /** A feature's state, which is empty when it has none. */
  getFeatureState(sourceLayer: string, featureId: number | string): Promise<Record<string, Object> | undefined> {
    return getState(sourceKeyOf(this), checkSourceLayer(sourceLayer), featureId);
  }

  /** Removes one value from a feature's state, or the whole state when `key` is left out. */
  removeFeatureState(sourceLayer: string, featureId: number | string, key?: string): Promise<boolean> {
    return removeState(sourceKeyOf(this), checkSourceLayer(sourceLayer), featureId, key);
  }

  /** Removes the state of every feature in a source layer. */
  resetFeatureStates(sourceLayer: string): Promise<boolean> {
    return removeState(sourceKeyOf(this), checkSourceLayer(sourceLayer), undefined, undefined);
  }
}

/** An image source of the loaded style. */
export class ImageSourceHandle extends SourceHandle {
  /** Replaces the source's image. The app can release the pixel map once the call returns. */
  setImage(pixelMap: image.PixelMap): Promise<boolean> {
    const pixels = readPixelMap(pixelMap);
    return sourceKeyOf(this).send(`setting the image of source ${this.id}`,
      (map) => map.setImageSourceImage(this.id, pixels));
  }

  /** Loads the source's image from a URL. */
  setUrl(url: string): Promise<boolean> {
    return sourceKeyOf(this).send(`setting the URL of source ${this.id}`,
      (map) => map.setImageSourceUrl(this.id, url));
  }

  /** Moves the image's four corners, clockwise from the top left. */
  setCoordinates(coordinates: LatLng[]): Promise<boolean> {
    if (coordinates.length !== 4) {
      throw new Error(`An image source needs its four corners, not ${coordinates.length}`);
    }
    coordinates.forEach((coordinate: LatLng) => checkLatLng(coordinate, 'Each corner of an image source'));
    return sourceKeyOf(this).send(`setting the coordinates of source ${this.id}`,
      (map) => map.setImageSourceCoordinates(this.id, coordinates));
  }
}
