import { GeoJsonGeometry } from '../geometry/GeoJson';
import { LatLngBounds } from '../geometry/Geometry';

/**
 * The area, zoom range, and style of an offline region. Give exactly one of
 * `bounds` and `geometry`.
 */
export interface OfflineRegionDefinition {
  /**
   * The style whose resources the region holds. Maps use the region when they
   * load the same URL.
   */
  styleUrl: string;
  /** The rectangle that the region covers. */
  bounds?: LatLngBounds;
  /** The area that the region covers, such as a route's line. */
  geometry?: GeoJsonGeometry;
  /** The lowest zoom to download. Finite and at least 0; 0 by default. */
  minZoom?: number;
  /**
   * The highest zoom to download, at least `minZoom`. Every zoom that the
   * style's sources have by default (`Infinity`). Each zoom needs about four
   * times the tiles of the one before, so keep it as low as the app allows.
   */
  maxZoom?: number;
  /** The pixel ratio of the images to download. Finite and greater than 0; the default display's density by default. */
  pixelRatio?: number;
  /** Whether the region holds the glyphs of CJK ideographs. False by default. */
  includeIdeographs?: boolean;
}

/** How much of an offline region has downloaded. */
export interface OfflineRegionStatus {
  /** Whether the region is downloading, from `startDownload()` until `pauseDownload()`. */
  downloading: boolean;
  /** Whether the region holds every resource that it needs. */
  complete: boolean;
  /** The resources downloaded so far, tiles included. */
  completedResourceCount: number;
  /** The resources that the region needs, tiles included; only a lower bound until `requiredResourceCountPrecise`. */
  requiredResourceCount: number;
  /** Whether `requiredResourceCount` is exact. */
  requiredResourceCountPrecise: boolean;
  /** The size of the downloaded resources, tiles included. */
  completedResourceBytes: number;
  /** The tiles downloaded so far. */
  completedTileCount: number;
  /** The tiles that the region needs. */
  requiredTileCount: number;
  /** The size of the downloaded tiles. */
  completedTileBytes: number;
}

/**
 * An offline region in a runtime's cache database, which the library creates
 * and keeps one object of for each region: from `MapRuntime`'s
 * `createOfflineRegion()`, `getOfflineRegions()`, or `mergeOfflineRegions()`.
 * Members may be added in later releases.
 *
 * Its getters are observable, so a component that reads `status` updates as
 * the download goes. The methods reject with an `Error` once its runtime is
 * released, and when the cache database fails. Once the region is deleted,
 * they reject with an `Error` too, except `delete()`, which does nothing.
 */
export interface OfflineRegion {
  /** The region's ID in the cache database. */
  readonly id: string;
  /**
   * The region's area, zoom range, and style, or undefined when it's of a kind
   * that this version of the library can't read. Such a region can still be
   * deleted.
   */
  readonly definition: OfflineRegionDefinition | undefined;
  /** The bytes that the app stored with the region, such as its name. */
  readonly metadata: Uint8Array;
  /** How much of the region has downloaded. */
  readonly status: OfflineRegionStatus;
  /** Whether the region was deleted, by `delete()` or `MapRuntime.resetCache()`. */
  readonly deleted: boolean;
  /**
   * What went wrong in the download since `startDownload()`, or undefined: a
   * `MapResourceError` for a resource that failed while the download goes on,
   * or an `Error` when the download stopped because the cache database holds
   * the most tiles of MapLibre's demo server that it allows. Match it with
   * `instanceof`.
   */
  readonly downloadError: Error | undefined;

  /**
   * Starts downloading what the region lacks, or goes on with a paused
   * download. A download stops when its runtime is released or the app
   * exits, and doesn't start again by itself.
   */
  startDownload(): Promise<void>;

  /** Pauses the download, and keeps what it downloaded. */
  pauseDownload(): Promise<void>;

  /**
   * Makes maps check each of the region's resources with its server before
   * they use it. The region keeps its resources; download it again to bring
   * them up to date.
   */
  invalidate(): Promise<void>;

  /** Replaces the bytes stored with the region. */
  setMetadata(metadata: Uint8Array): Promise<void>;

  /** Deletes the region and its resources that no other region holds. Does nothing for a deleted region. */
  delete(): Promise<void>;
}
