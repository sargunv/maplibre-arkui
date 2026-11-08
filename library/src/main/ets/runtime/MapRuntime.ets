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

/** Settings for a `MapRuntime`. */
export interface MapRuntimeOptions {
  /**
   * The path of the cache database, which holds the ambient cache and offline
   * regions. Without one, both live in memory and are lost when the runtime
   * is released. Must not be empty, and no two unreleased runtimes can use
   * the same file.
   */
  cachePath?: string;
  /**
   * The largest size of the ambient cache, which holds what maps have loaded.
   * Offline regions don't count toward it. A non-negative integer; 50 MiB by
   * default.
   */
  maximumAmbientCacheSizeBytes?: number;
  /**
   * Loads the requests that its URL patterns match, in place of MapLibre.
   * `asset://` URLs load only through a provider. None by default.
   */
  resourceProvider?: MapResourceProvider;
  /**
   * Returns the URL to load in place of a request's, or undefined to keep it.
   * It applies to requests that MapLibre loads itself, not to those that
   * `resourceProvider` loads.
   *
   * It runs on the UI thread and must return at once. If it throws, the error
   * is logged and the request keeps its URL.
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
 * A cache database and request handling that maps and snapshots share.
 *
 * Maps and snapshots use the default runtime unless they're given another.
 * A runtime that the app creates must be released with `release()` once no
 * map or snapshot uses it.
 *
 * A runtime opens when it's first used. If it fails to open, its maps report
 * a `MapError` to `onError`, its methods reject, and it tries again on the
 * next use. Call its methods on the UI thread.
 *
 * The static members are settings for the whole app.
 */
export class MapRuntime {
  private readonly state: RuntimeState;

  /**
   * Creates a runtime. Throws an `Error` for an invalid option, or for a
   * `cachePath` that another unreleased runtime uses, including the default
   * runtime.
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
   * Returns the default runtime, which lasts for the life of the app. It has
   * the options of `configureDefault()`. Its cache database is
   * `maplibre-cache.db` in the app's files directory, unless those options
   * name another.
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
   * Sets the options of the default runtime. Throws an `Error` once the
   * default runtime exists, after the first map or `getDefault()` call, for an
   * invalid option, or for a `cachePath` that another unreleased runtime uses.
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
   * Sets when MapLibre may use the network, for every runtime in the app. It
   * applies at once. `ConnectivityMode.AUTOMATIC` by default.
   *
   * While offline, MapLibre starts no network requests, and waiting requests
   * start once it's online again. Requests that a `resourceProvider` matches
   * still go to the provider.
   */
  static setConnectivityMode(mode: ConnectivityMode): void {
    setConnectivityMode(mode);
  }

  /** Returns the current connectivity mode. */
  static getConnectivityMode(): ConnectivityMode {
    return getConnectivityMode();
  }

  /**
   * Sends the library's and MapLibre Native's log messages to `handler`
   * instead of hilog, for the whole app. Errors still go to hilog too. Pass
   * undefined to send everything to hilog again.
   *
   * The handler runs on the UI thread. If it throws, the error is logged and
   * the handler still gets later records.
   */
  static setLogHandler(handler: MapLogHandler | undefined): void {
    setLogHandler(handler);
  }

  /**
   * Creates an offline region in the cache database, storing `metadata` with
   * it. The region doesn't download until `startDownload()`.
   *
   * Throws an `Error` for a definition with both or neither of `bounds` and
   * `geometry`, or with another invalid field.
   */
  createOfflineRegion(definition: OfflineRegionDefinition, metadata?: Uint8Array): Promise<OfflineRegion> {
    return this.state.createOfflineRegion(definition, metadata ?? new Uint8Array(0));
  }

  /** Lists the offline regions in the cache database, including those from earlier launches. */
  getOfflineRegions(): Promise<OfflineRegion[]> {
    return this.state.getOfflineRegions();
  }

  /**
   * Copies the offline regions of another cache database into this runtime's,
   * and resolves with the copied regions. Regions with the same definition and
   * metadata as an existing one aren't copied again.
   *
   * Rejects with an `Error` if the file isn't a readable cache database, or if
   * the copy would exceed MapLibre's tile limit for its demo tile server.
   */
  mergeOfflineRegions(databasePath: string): Promise<OfflineRegion[]> {
    return this.state.mergeOfflineRegions(databasePath);
  }

  /** Deletes the ambient cache. Offline regions stay. */
  clearAmbientCache(): Promise<void> {
    return this.state.runCacheOperation(CacheDatabaseOperation.clear);
  }

  /**
   * Marks the ambient cache as stale, so maps check each resource with its
   * server before they use it again. Offline regions stay as they are.
   */
  invalidateAmbientCache(): Promise<void> {
    return this.state.runCacheOperation(CacheDatabaseOperation.invalidate);
  }

  /** Deletes the ambient cache and every offline region. */
  resetCache(): Promise<void> {
    return this.state.runCacheOperation(CacheDatabaseOperation.reset);
  }

  /**
   * Releases the runtime. Its downloads stop, its maps report a `MapError` and
   * show nothing, and its methods and new snapshots reject. Resolves once
   * snapshots in progress finish and the cache database closes; then another
   * runtime can use its `cachePath`.
   *
   * Throws an `Error` for the default runtime.
   */
  release(): Promise<void> {
    if (this.state.isDefault) {
      throw new Error('The default runtime can\'t be released');
    }
    return this.state.release();
  }
}
