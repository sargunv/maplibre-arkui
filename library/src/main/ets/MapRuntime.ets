// What maps and snapshots share: the cache database, the handling of requests,
// and offline regions, behind FFI's runtime, which opens on first use. MapLibre
// keeps the default runtime, the connectivity mode, and the log once per
// process, so they're static members of `MapRuntime`.

import {
  CacheDatabaseOperation,
  MapHandle,
  OfflineRegionInfo,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeEventSourceType,
  RuntimeHandle,
} from '@maplibre/native-ffi';
import application from '@ohos.app.ability.application';

import { ConnectivityMode, followConnectivity, getConnectivityMode, setConnectivityMode } from './connectivity';
import { logError, MapLogHandler, setLogHandler } from './log';
import { checkProvider, MapResourceProvider, MapResourceRequest, toFfiProvider, toFfiTransform } from './MapResource';
import { OfflineRegion, OfflineRegionDefinition, RegionOwner, StoredRegion, toFfiDefinition } from './OfflineRegion';

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

// A map or a snapshot on a runtime, which stops as the runtime is released.
export interface RuntimeUser {
  runtimeReleased(): void;
}

const DEFAULT_AMBIENT_CACHE_BYTES = 50 * 1024 * 1024;
const REGION_EVENTS: RuntimeEventFlag = RuntimeEventFlag.offlineRegionStatusChanged |
  RuntimeEventFlag.offlineRegionResponseError | RuntimeEventFlag.offlineRegionTileCountLimitExceeded;

// The cache files of the runtimes that aren't released.
const cachePaths: Set<string> = new Set<string>();
let defaultRuntime: MapRuntime | undefined = undefined;
let defaultOptions: MapRuntimeOptions = {};
// The constructor makes the default runtime while this is set.
let creatingDefault: boolean = false;

function defaultCachePath(): string {
  return defaultOptions.cachePath ?? `${application.getApplicationContext().filesDir}/maplibre-cache.db`;
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

function regionIdOf(event: RuntimeEvent): bigint | undefined {
  const payload = event.payload;
  if (payload.kind === 'offlineRegionStatus') {
    return payload.value.regionId;
  } else if (payload.kind === 'offlineRegionResponseError') {
    return payload.value.regionId;
  } else if (payload.kind === 'offlineRegionTileCountLimit') {
    return payload.value.regionId;
  }
  return undefined;
}

// What the library keeps of a runtime: its FFI runtime once open, and the
// maps, snapshots, and offline regions on it, which take its events.
export class RuntimeState implements RegionOwner {
  readonly isDefault: boolean;
  private readonly options: MapRuntimeOptions;
  private readonly cachePath: string | undefined;
  private opening: Promise<RuntimeHandle> | undefined = undefined;
  private isReleased: boolean = false;
  private releasing: Promise<void> | undefined = undefined;
  private readonly maps: Map<bigint, (event: RuntimeEvent) => void> = new Map<bigint, (event: RuntimeEvent) => void>();
  private readonly users: Set<RuntimeUser> = new Set<RuntimeUser>();
  // The teardowns of maps and the snapshots that render, which the FFI
  // runtime's release waits for.
  private readonly work: Set<Promise<void>> = new Set<Promise<void>>();
  private readonly regions: Map<bigint, StoredRegion> = new Map<bigint, StoredRegion>();

  constructor(options: MapRuntimeOptions, cachePath: string | undefined, isDefault: boolean) {
    this.options = options;
    this.cachePath = cachePath;
    this.isDefault = isDefault;
  }

  get released(): boolean {
    return this.isReleased;
  }

  // Opens the FFI runtime on first use. One that fails to open opens again on
  // the next use.
  open(): Promise<RuntimeHandle> {
    if (this.released) {
      return Promise.reject(new Error('The runtime was released'));
    }
    if (this.opening === undefined) {
      const opening = this.create();
      this.opening = opening;
      opening.catch(() => {
        if (this.opening === opening) {
          this.opening = undefined;
        }
      });
    }
    return this.opening;
  }

  private async create(): Promise<RuntimeHandle> {
    followConnectivity();
    const where = this.cachePath === undefined ? 'in memory' : `with the cache database ${this.cachePath}`;
    let runtime: RuntimeHandle;
    try {
      runtime = await RuntimeHandle.create({ cachePath: this.cachePath });
    } catch (error) {
      throw new Error(`Can't open the runtime ${where}: ${(error as Error).message}`);
    }
    try {
      // Before any map, so the handler gets each map's first events.
      runtime.discarding.setEventHandler({ callback: (events: readonly RuntimeEvent[]) => this.dispatch(events) });
      const rewriteUrl = this.options.rewriteUrl;
      if (rewriteUrl !== undefined) {
        runtime.discarding.setResourceTransform(toFfiTransform(rewriteUrl));
      }
      const provider = this.options.resourceProvider === undefined ? undefined :
        toFfiProvider(this.options.resourceProvider);
      if (provider !== undefined) {
        runtime.discarding.setResourceProvider(provider);
      }
      await runtime.setMaximumAmbientCacheSize(
        BigInt(this.options.maximumAmbientCacheSizeBytes ?? DEFAULT_AMBIENT_CACHE_BYTES));
    } catch (error) {
      await runtime.release().catch(() => {
      });
      throw new Error(`Can't open the runtime ${where}: ${(error as Error).message}`);
    }
    return runtime;
  }

  private dispatch(events: readonly RuntimeEvent[]): void {
    for (const event of events) {
      try {
        if (event.sourceType === RuntimeEventSourceType.map) {
          const listener = this.maps.get(event.source);
          if (listener !== undefined) {
            listener(event);
          }
        } else {
          const id = regionIdOf(event);
          const region = id === undefined ? undefined : this.regions.get(id);
          region?.onEvent(event);
        }
      } catch (error) {
        logError(`handling a runtime event threw: ${(error as Error).message}`);
      }
    }
  }

  // A map's events go to `listener` until it's removed.
  addMap(map: MapHandle, listener: (event: RuntimeEvent) => void): void {
    this.maps.set(map.id, listener);
  }

  removeMap(map: MapHandle): void {
    this.maps.delete(map.id);
  }

  addUser(user: RuntimeUser): void {
    this.users.add(user);
  }

  removeUser(user: RuntimeUser): void {
    this.users.delete(user);
  }

  // Work that ends with an FFI map released, which the runtime waits for
  // before it closes.
  track(work: Promise<void>): void {
    const settled = work.catch(() => {
    });
    this.work.add(settled);
    settled.then(() => this.work.delete(settled));
  }

  createOfflineRegion(definition: OfflineRegionDefinition, metadata: Uint8Array): Promise<OfflineRegion> {
    const ffi = toFfiDefinition(definition);
    return this.open().then(async (runtime: RuntimeHandle) =>
      this.regionFor(runtime, await runtime.createOfflineRegion(ffi, metadata)));
  }

  async getOfflineRegions(): Promise<OfflineRegion[]> {
    const runtime = await this.open();
    const infos = await runtime.listOfflineRegions();
    // A region that's gone was deleted, such as by another runtime on the file.
    const listed = new Set<bigint>(infos.map((info: OfflineRegionInfo) => info.id));
    Array.from(this.regions.values()).forEach((region: StoredRegion) => {
      if (!listed.has(region.regionId)) {
        region.markDeleted();
      }
    });
    return this.regionsFor(runtime, infos);
  }

  async mergeOfflineRegions(databasePath: string): Promise<OfflineRegion[]> {
    const runtime = await this.open();
    return this.regionsFor(runtime, await runtime.mergeOfflineRegions(databasePath));
  }

  async runCacheOperation(operation: CacheDatabaseOperation): Promise<void> {
    await (await this.open()).runCacheDatabaseOperation(operation);
    if (operation === CacheDatabaseOperation.reset) {
      Array.from(this.regions.values()).forEach((region: StoredRegion) => region.markDeleted());
    }
  }

  forget(region: StoredRegion): void {
    if (this.regions.get(region.regionId) === region) {
      this.regions.delete(region.regionId);
    }
  }

  private async regionsFor(runtime: RuntimeHandle, infos: readonly OfflineRegionInfo[]): Promise<OfflineRegion[]> {
    const regions: OfflineRegion[] = [];
    for (const info of infos) {
      regions.push(await this.regionFor(runtime, info));
    }
    return regions;
  }

  // The one object of the region that `info` describes, with its status read,
  // whose events the runtime reports from when it's created.
  private async regionFor(runtime: RuntimeHandle, info: OfflineRegionInfo): Promise<StoredRegion> {
    let region = this.regions.get(info.id);
    if (region === undefined) {
      region = new StoredRegion(info, this);
      this.regions.set(info.id, region);
      await runtime.setOfflineRegionObserved(info.id, REGION_EVENTS);
    }
    await region.refresh(runtime, info);
    return region;
  }

  release(): Promise<void> {
    if (this.releasing === undefined) {
      this.isReleased = true;
      this.releasing = this.close();
    }
    return this.releasing;
  }

  // Stops the maps on the runtime, and closes the FFI runtime once they and
  // the snapshots that render have released their FFI maps, which FFI needs.
  private async close(): Promise<void> {
    const users = Array.from(this.users);
    this.users.clear();
    users.forEach((user: RuntimeUser) => user.runtimeReleased());
    try {
      const opening = this.opening;
      const runtime = opening === undefined ? undefined :
        await opening.catch((): RuntimeHandle | undefined => undefined);
      await Promise.all(Array.from(this.work));
      this.regions.forEach((region: StoredRegion) => region.stopped());
      if (runtime !== undefined) {
        await runtime.release();
      }
    } finally {
      if (this.cachePath !== undefined) {
        cachePaths.delete(this.cachePath);
      }
    }
  }
}

// Each runtime's state, which only the library reaches.
const states: WeakMap<MapRuntime, RuntimeState> = new WeakMap<MapRuntime, RuntimeState>();

// Internal: the state of `runtime`, which its maps and snapshots use.
export function runtimeState(runtime: MapRuntime): RuntimeState {
  return states.get(runtime)!;
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
    states.set(this, this.state);
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
    if (options.cachePath !== undefined && cachePaths.has(options.cachePath)) {
      throw new Error(`Another runtime uses the cache database ${options.cachePath}`);
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
