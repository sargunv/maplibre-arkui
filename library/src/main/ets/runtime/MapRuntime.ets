// What maps and snapshots share: the cache database, the handling of requests,
// and offline regions, behind FFI's runtime, which opens on first use. MapLibre
// keeps the default runtime, the connectivity mode, and the log once per
// process, so they're static members of `MapRuntime`.

import { CacheDatabaseOperation } from '@maplibre/native-ffi';
import application from '@ohos.app.ability.application';

import { ConnectivityMode } from './ConnectivityMode';
import { getConnectivityMode, setConnectivityMode } from './internal/Connectivity';
import { checkProvider } from './internal/FfiRequests';
import { setLogHandler } from './internal/Log';
import { cachePaths, registerRuntimeState, RuntimeState } from './internal/RuntimeRegistry';
import { MapLogHandler } from './Logs';
import { OfflineRegion, OfflineRegionDefinition } from './OfflineRegion';
import { MapResourceProvider, MapResourceRequest } from './Requests';

/** Settings of a `MapRuntime`. */
export interface MapRuntimeOptions {
  /**
   * The cache database file, which holds the ambient cache and offline
   * regions. Without one, they're in memory and gone once the runtime is
   * released. Two runtimes that aren't released can't share a file.
   */
  cachePath?: string;
  /**
   * How large the ambient cache, which holds what maps loaded, can grow, in
   * bytes. Offline regions don't count toward it. A non-negative integer;
   * 50 MiB by default. It applies each time the runtime opens.
   */
  maximumAmbientCacheSizeBytes?: number;
  /**
   * Loads the requests that its patterns match, in place of MapLibre. None by
   * default. MapLibre loads `asset://` URLs only through a provider, such as
   * one that reads the app's rawfile resources.
   */
  resourceProvider?: MapResourceProvider;
  /**
   * Gives the URL to load in place of a request's, or undefined to keep it,
   * such as to add an API key. It applies to the requests that MapLibre loads
   * itself from the network, not to those that `resourceProvider` loads.
   *
   * It runs on the UI thread, and must answer at once: it's for pure URL
   * transforms, and a provider covers I/O. One that throws is logged, and the
   * request keeps its URL.
   */
  rewriteUrl?: (request: MapResourceRequest) => string | undefined;
}

let defaultRuntime: MapRuntime | undefined = undefined;
let defaultOptions: MapRuntimeOptions = {};
// The constructor makes the default runtime while this is set.
let creatingDefault: boolean = false;

function defaultCachePath(options: MapRuntimeOptions = defaultOptions): string {
  return options.cachePath ?? `${application.getApplicationContext().filesDir}/maplibre-cache.db`;
}

function checkOptions(options: MapRuntimeOptions): void {
  if (options.cachePath === '') {
    throw new Error('A runtime\'s cachePath must not be empty; leave it out for a cache in memory');
  }
  const size = options.maximumAmbientCacheSizeBytes;
  if (size !== undefined && !(Number.isInteger(size) && size >= 0)) {
    throw new Error(`A runtime's maximumAmbientCacheSizeBytes must be a non-negative integer: ${size}`);
  }
  if (options.resourceProvider !== undefined) {
    checkProvider(options.resourceProvider);
  }
}

/**
 * What maps and snapshots on it share: a cache database, which holds the
 * ambient cache and offline regions, and the handling of their requests.
 *
 * Every `MaplibreMap` and `renderSnapshot()` uses the default runtime, from
 * `MapRuntime.getDefault()`, unless the app passes another. Create another
 * for a cache of its own or other request handling, keep it in a field, pass
 * it to each map and snapshot that uses it, and `release()` it once they're
 * gone.
 *
 * A runtime opens on first use: when a map or snapshot uses it, or the app
 * calls an offline region or cache method. One that fails to open reports a
 * `MapError` to its maps' `onError` and to the log, and its methods reject;
 * it tries to open again on the next use. Call its methods on the UI thread.
 *
 * MapLibre keeps some settings once per app, so they're static: the default
 * runtime and its options, the connectivity mode, and the log handler.
 */
export class MapRuntime {
  private readonly state: RuntimeState;

  /**
   * Creates a runtime with `options`, which opens on first use. It throws an
   * `Error` with the value for an invalid option, and for a `cachePath` that
   * another runtime that isn't released uses, the default runtime's included.
   */
  constructor(options: MapRuntimeOptions = {}) {
    checkOptions(options);
    const isDefault = creatingDefault;
    const cachePath = isDefault ? defaultCachePath() : options.cachePath;
    if (cachePath !== undefined &&
      (cachePaths.has(cachePath) || (!isDefault && defaultRuntime === undefined && cachePath === defaultCachePath()))) {
      throw new Error(`Another runtime uses the cache database ${cachePath}`);
    }
    if (cachePath !== undefined) {
      cachePaths.add(cachePath);
    }
    this.state = new RuntimeState(options, cachePath, isDefault);
    registerRuntimeState(this, this.state);
  }

  /**
   * The runtime that maps and snapshots use unless the app passes another. The
   * library creates it on the first call and keeps it for the app's life,
   * with the options of `configureDefault()`. Its cache database is
   * `maplibre-cache.db` in the app's files directory unless they name
   * another, so offline regions last until the app deletes them.
   */
  static getDefault(): MapRuntime {
    if (defaultRuntime === undefined) {
      creatingDefault = true;
      try {
        defaultRuntime = new MapRuntime(defaultOptions);
      } finally {
        creatingDefault = false;
      }
    }
    return defaultRuntime;
  }

  /**
   * Sets the options of the default runtime, such as in the ability's
   * `onCreate()`, before the first map or `getDefault()` call. Without a
   * `cachePath`, it keeps its cache database in the app's files directory.
   *
   * It throws an `Error` once `getDefault()` has run, for an invalid option,
   * and for a `cachePath` that another runtime that isn't released uses.
   */
  static configureDefault(options: MapRuntimeOptions): void {
    if (defaultRuntime !== undefined) {
      throw new Error('MapRuntime.configureDefault() must come before the first MapRuntime.getDefault()');
    }
    checkOptions(options);
    const cachePath = defaultCachePath(options);
    if (cachePaths.has(cachePath)) {
      throw new Error(`Another runtime uses the cache database ${cachePath}`);
    }
    defaultOptions = options;
  }

  /**
   * Sets how MapLibre decides whether it may use the network, for every
   * runtime of the app and its maps, snapshots, and offline downloads. The
   * mode is `ConnectivityMode.AUTOMATIC` until the app sets another, and it
   * applies at once.
   *
   * While MapLibre is offline, it starts no network requests, and the
   * requests that wait start once it's online again. Requests that have
   * started may finish, and a resource provider does its own networking.
   */
  static setConnectivityMode(mode: ConnectivityMode): void {
    setConnectivityMode(mode);
  }

  /** The connectivity mode that `setConnectivityMode()` set last. */
  static getConnectivityMode(): ConnectivityMode {
    return getConnectivityMode();
  }

  /**
   * Sends the log of the whole app to `handler`, or to hilog only for
   * undefined, as before the first call. The log holds the library's
   * messages and MapLibre Native's, which hilog has with the tag
   * `MapLibreNative`.
   *
   * MapLibre Native's messages reach the handler later than they happen, in
   * batches, and some may be lost under load. Records of `MapLogLevel.ERROR`
   * still go to hilog. The handler runs on the UI thread; one that throws is
   * written to hilog, and is still called with later records.
   */
  static setLogHandler(handler: MapLogHandler | undefined): void {
    setLogHandler(handler);
  }

  /**
   * Creates an offline region in the cache database, with `metadata`, such as
   * its name, stored with it (none by default). It resolves once the region's
   * status is read, and the region downloads once the app calls its
   * `startDownload()`.
   *
   * It throws an `Error` with the value for a definition that has both or
   * neither of `bounds` and `geometry`, or another invalid field.
   */
  createOfflineRegion(definition: OfflineRegionDefinition, metadata?: Uint8Array): Promise<OfflineRegion> {
    return this.state.createOfflineRegion(definition, metadata ?? new Uint8Array(0));
  }

  /**
   * Lists the offline regions in the cache database, those of earlier
   * launches included, with their status read. Each region has one object
   * across calls. A region that's no longer in the database is `deleted`.
   */
  getOfflineRegions(): Promise<OfflineRegion[]> {
    return this.state.getOfflineRegions();
  }

  /**
   * Copies the offline regions of another cache database, such as one that the
   * app ships, into this runtime's, and resolves with this runtime's copy of
   * each. A region that the cache database already has with the same
   * definition and metadata isn't copied again.
   *
   * It rejects with an `Error` when the file isn't a readable cache database,
   * and when the copy would pass the limit on tiles of MapLibre's demo
   * server.
   */
  mergeOfflineRegions(databasePath: string): Promise<OfflineRegion[]> {
    return this.state.mergeOfflineRegions(databasePath);
  }

  /** Deletes the ambient cache, and keeps offline regions. */
  clearAmbientCache(): Promise<void> {
    return this.state.runCacheOperation(CacheDatabaseOperation.clear);
  }

  /**
   * Makes maps check each resource of the ambient cache with its server before
   * they use it again, and keeps offline regions as they are.
   */
  invalidateAmbientCache(): Promise<void> {
    return this.state.runCacheOperation(CacheDatabaseOperation.invalidate);
  }

  /** Deletes the ambient cache and every offline region, whose objects become `deleted`. */
  resetCache(): Promise<void> {
    return this.state.runCacheOperation(CacheDatabaseOperation.reset);
  }

  /**
   * Releases the runtime. Its downloads stop, its maps report a `MapError` to
   * their `onError` and show nothing, and its methods and new snapshots
   * reject. It resolves once the cache database is closed, after the
   * snapshots that render have finished, and from then another runtime can
   * use its `cachePath`.
   *
   * It throws an `Error` for the default runtime, which lasts for the app's
   * life.
   */
  release(): Promise<void> {
    if (this.state.isDefault) {
      throw new Error('The default runtime can\'t be released');
    }
    return this.state.release();
  }
}
