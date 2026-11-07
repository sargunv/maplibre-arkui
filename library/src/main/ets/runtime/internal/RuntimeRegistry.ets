// What the library keeps of each MapRuntime, which its maps, snapshots, and
// offline regions reach, and the cache files that the runtimes hold.

import {
  CacheDatabaseOperation,
  MapHandle,
  OfflineRegionInfo,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeEventSourceType,
  RuntimeHandle,
} from '@maplibre/native-ffi';

import { MapRuntime, MapRuntimeOptions } from '../MapRuntime';
import { OfflineRegion, OfflineRegionDefinition } from '../OfflineRegion';
import { followConnectivity } from './Connectivity';
import { toFfiProvider, toFfiTransform } from './FfiRequests';
import { logError } from './Log';
import { RegionOwner, StoredRegion, toFfiDefinition } from './OfflineRegionImpl';

// A map or a snapshot on a runtime, which stops as the runtime is released.
export interface RuntimeUser {
  runtimeReleased(): void;
}

const DEFAULT_AMBIENT_CACHE_BYTES = 50 * 1024 * 1024;
const REGION_EVENTS: RuntimeEventFlag = RuntimeEventFlag.offlineRegionStatusChanged |
  RuntimeEventFlag.offlineRegionResponseError | RuntimeEventFlag.offlineRegionTileCountLimitExceeded;

// The cache files of the runtimes that aren't released.
export const cachePaths: Set<string> = new Set<string>();

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

// Keeps `state` as the state of `runtime`, as the runtime is created.
export function registerRuntimeState(runtime: MapRuntime, state: RuntimeState): void {
  states.set(runtime, state);
}

// The state of `runtime`, which its maps and snapshots use.
export function runtimeState(runtime: MapRuntime): RuntimeState {
  return states.get(runtime)!;
}
