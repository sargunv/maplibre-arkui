import { GeoJsonGeometry } from '../geometry/GeoJson';
import { LatLngBounds } from '../geometry/Geometry';

/**
 * What an offline region downloads: a style, an area, and a zoom range. Give
 * exactly one of `bounds` and `geometry`.
 */
export interface OfflineRegionDefinition {
  /** The URL of the style to download. Maps use the region when they load this URL. */
  styleUrl: string;
  /** The area to download, as a rectangle. */
  bounds?: LatLngBounds;
  /** The area to download, as a geometry, such as a route's line. */
  geometry?: GeoJsonGeometry;
  /** The lowest zoom level to download. Finite and at least 0; 0 by default. */
  minZoom?: number;
  /**
   * The highest zoom level to download, at least `minZoom`. `Infinity` by
   * default, which downloads every zoom level the style's sources have.
   */
  maxZoom?: number;
  /** The pixel ratio of the images to download. Finite and greater than 0; the default display's density by default. */
  pixelRatio?: number;
  /** Whether to download glyphs for CJK ideographs. False by default. */
  includeIdeographs?: boolean;
}

/** The download progress of an offline region. */
export interface OfflineRegionStatus {
  /** Whether the region is downloading, from `startDownload()` until `pauseDownload()`. */
  readonly downloading: boolean;
  /** Whether the region has every resource it needs. */
  readonly complete: boolean;
  /** The number of resources downloaded so far, including tiles. */
  readonly completedResourceCount: number;
  /**
   * The number of resources the region needs, including tiles. A lower bound
   * until `requiredResourceCountPrecise` is true.
   */
  readonly requiredResourceCount: number;
  /** Whether `requiredResourceCount` is exact. */
  readonly requiredResourceCountPrecise: boolean;
  /** The total size of the downloaded resources, including tiles. */
  readonly completedResourceBytes: number;
  /** The number of tiles downloaded so far. */
  readonly completedTileCount: number;
  /** The number of tiles the region needs. */
  readonly requiredTileCount: number;
  /** The total size of the downloaded tiles. */
  readonly completedTileBytes: number;
}

/**
 * An offline region in a runtime's cache database. Members may be added in
 * later releases.
 *
 * Its fields are observable. Its methods reject with an `Error` after its
 * runtime is released, when the cache database fails, and after the region is
 * deleted, except `delete()`.
 */
export interface OfflineRegion {
  /** The region's ID in the cache database. */
  readonly id: string;
  /**
   * What the region downloads, or undefined if this version of the library
   * can't read its definition. Such a region can still be deleted.
   */
  readonly definition: OfflineRegionDefinition | undefined;
  /** The bytes stored with the region, such as its name. */
  readonly metadata: Uint8Array;
  /** The region's download progress. */
  readonly status: OfflineRegionStatus;
  /** Whether the region was deleted, by `delete()` or `MapRuntime.resetCache()`. */
  readonly deleted: boolean;
  /**
   * The last download error since `startDownload()`, or undefined. A
   * `MapResourceError` means a resource failed and the download goes on. Any
   * other `Error` means the download stopped because it reached MapLibre's
   * tile limit for its demo tile server.
   */
  readonly downloadError: Error | undefined;

  /**
   * Starts or resumes downloading what the region lacks. The download stops
   * when its runtime is released or the app exits, and doesn't resume by
   * itself.
   */
  startDownload(): Promise<void>;

  /** Pauses the download. What it downloaded stays. */
  pauseDownload(): Promise<void>;

  /**
   * Marks the region's resources as stale, so maps check each with its server
   * before they use it. The resources stay until a new download replaces them.
   */
  invalidate(): Promise<void>;

  /** Replaces the bytes stored with the region. */
  setMetadata(metadata: Uint8Array): Promise<void>;

  /** Deletes the region, and its resources that no other region uses. Does nothing if the region is already deleted. */
  delete(): Promise<void>;
}
