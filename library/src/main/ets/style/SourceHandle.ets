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
 * A source of the style that `MapStyle` reads.
 *
 * A handle belongs to one style. It expires when that style goes, as
 * `MapStyle` describes, and when its source leaves the style: by `remove()`,
 * or as the content removes or replaces it. Then its reads resolve undefined,
 * and its writes `false`. Get a new handle for the source of a new style. Its
 * writes throw an `Error` for a source of the content, as `MapStyle`
 * describes, except those of feature state.
 *
 * Feature state is a set of values by name for each feature of a source,
 * which the `featureState()` expressions of paint properties read, such as to
 * highlight a selected feature. It works on every source, those of the base
 * style and the content too. The map keeps it by the source's ID, and the
 * source layer's name, until the app removes it: a source that replaces this
 * one, or a source of a later style, with the same ID shows it. A change draws
 * on the next frame, even on a map that's idle. A feature state method takes
 * the feature's `id`, a number or a string. The map compares IDs as text, so 7
 * and '7' name one feature. It throws an `Error` for a state that
 * `JSON.stringify()` can't write.
 *
 * A GeoJSON source's handle is a `GeoJsonSourceHandle`, a vector tile
 * source's a `VectorSourceHandle`, and an image source's an
 * `ImageSourceHandle`; match them with `instanceof`. Subclasses for other
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
 * A GeoJSON source of the style, as `SourceHandle` describes.
 *
 * The cluster queries read the source's clusters, from a feature of the
 * source with the `cluster_id` property, such as a feature that a click or a
 * query found in a layer that draws the source. They read the data that the
 * map last drew, and resolve undefined for a feature without a `cluster_id`
 * that's a whole number from 0 to 4294967295, for a cluster that isn't in
 * that data, for a source that doesn't cluster, while no map shows a frame,
 * and once the handle expires. A cluster's ID belongs to one version of the
 * data: after the data changes, find the cluster again. They reject when the
 * map rejects the query for another reason.
 */
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

  /**
   * Merges `state` into the state of the feature with the ID `featureId`: its
   * values replace those with the same names, and the others stay.
   */
  setFeatureState(featureId: number | string, state: Record<string, Object>): Promise<boolean> {
    return setState(sourceKeyOf(this), undefined, featureId, state);
  }

  /** The state of the feature with the ID `featureId`, which is empty when it has none. */
  getFeatureState(featureId: number | string): Promise<Record<string, Object> | undefined> {
    return getState(sourceKeyOf(this), undefined, featureId);
  }

  /** Removes the value `key` from the state of the feature with the ID `featureId`, or its whole state without `key`. */
  removeFeatureState(featureId: number | string, key?: string): Promise<boolean> {
    return removeState(sourceKeyOf(this), undefined, featureId, key);
  }

  /** Removes the state of every feature of the source. */
  resetFeatureStates(): Promise<boolean> {
    return removeState(sourceKeyOf(this), undefined, undefined, undefined);
  }

  /** The zoom level at which `cluster` splits into two or more clusters or points. */
  getClusterExpansionZoom(cluster: GeoJsonFeature): Promise<number | undefined> {
    return queryCluster(sourceKeyOf(this), cluster, 'expansion zoom',
      (session: RenderSessionHandle, id: number) => session.getClusterExpansionZoom(this.id, id));
  }

  /** The clusters and points that `cluster` splits into at the next zoom level. */
  getClusterChildren(cluster: GeoJsonFeature): Promise<GeoJsonFeatureCollection | undefined> {
    return queryCluster(sourceKeyOf(this), cluster, 'children', (session: RenderSessionHandle, id: number) =>
      session.getClusterChildren(this.id, id) as Promise<GeoJsonFeatureCollection>);
  }

  /**
   * The points in `cluster`, also those in the clusters within it: up to
   * `limit` of them, after the first `offset`. A `limit` of 0 gives none. It
   * throws an `Error` for a `limit` or `offset` that isn't a whole number of 0
   * or more.
   */
  getClusterLeaves(cluster: GeoJsonFeature, limit: number, offset: number):
    Promise<GeoJsonFeatureCollection | undefined> {
    const most = checkCount('limit', limit);
    const skipped = checkCount('offset', offset);
    return queryCluster(sourceKeyOf(this), cluster, 'leaves', (session: RenderSessionHandle, id: number) =>
      session.getClusterLeaves(this.id, id, most, skipped) as Promise<GeoJsonFeatureCollection>);
  }
}

/**
 * A vector tile source of the style, as `SourceHandle` describes. Its
 * features are in source layers, so the feature state methods take the name
 * of one, and throw an `Error` for an empty name.
 */
export class VectorSourceHandle extends SourceHandle {
  /**
   * Merges `state` into the state of the feature with the ID `featureId` in
   * the source layer `sourceLayer`: its values replace those with the same
   * names, and the others stay.
   */
  setFeatureState(sourceLayer: string, featureId: number | string, state: Record<string, Object>): Promise<boolean> {
    return setState(sourceKeyOf(this), checkSourceLayer(sourceLayer), featureId, state);
  }

  /**
   * The state of the feature with the ID `featureId` in the source layer
   * `sourceLayer`, which is empty when it has none.
   */
  getFeatureState(sourceLayer: string, featureId: number | string): Promise<Record<string, Object> | undefined> {
    return getState(sourceKeyOf(this), checkSourceLayer(sourceLayer), featureId);
  }

  /**
   * Removes the value `key` from the state of the feature with the ID
   * `featureId` in the source layer `sourceLayer`, or its whole state without
   * `key`.
   */
  removeFeatureState(sourceLayer: string, featureId: number | string, key?: string): Promise<boolean> {
    return removeState(sourceKeyOf(this), checkSourceLayer(sourceLayer), featureId, key);
  }

  /** Removes the state of every feature in the source layer `sourceLayer`. */
  resetFeatureStates(sourceLayer: string): Promise<boolean> {
    return removeState(sourceKeyOf(this), checkSourceLayer(sourceLayer), undefined, undefined);
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
