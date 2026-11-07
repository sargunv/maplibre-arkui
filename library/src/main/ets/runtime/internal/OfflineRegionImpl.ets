// Offline regions: areas of a style whose resources a runtime downloads into
// its cache database, so maps show them without the network.

import {
  OfflineRegionDefinition as FfiDefinition,
  OfflineRegionDownloadState,
  OfflineRegionInfo,
  OfflineRegionStatus as FfiStatus,
  RuntimeEvent,
  RuntimeHandle,
} from '@maplibre/native-ffi';
import display from '@ohos.display';

import { GeoJsonGeometry } from '../../geometry/GeoJson';
import { checkBounds, checkGeometry } from '../../geometry/internal/FfiGeometry';
import { OfflineRegion, OfflineRegionDefinition, OfflineRegionStatus } from '../OfflineRegion';
import { MapResourceError } from '../Requests';
import { fromFfiReason } from './FfiRequests';

const NO_STATUS: OfflineRegionStatus = {
  downloading: false,
  complete: false,
  completedResourceCount: 0,
  requiredResourceCount: 0,
  requiredResourceCountPrecise: false,
  completedResourceBytes: 0,
  completedTileCount: 0,
  requiredTileCount: 0,
  completedTileBytes: 0,
};

// Throws for a definition that FFI would reject, with the value.
export function toFfiDefinition(definition: OfflineRegionDefinition): FfiDefinition {
  const bounds = definition.bounds;
  const geometry = definition.geometry;
  if ((bounds === undefined) === (geometry === undefined)) {
    throw new Error(`An offline region needs exactly one of bounds and geometry, not ${
      bounds === undefined ? 'neither' : 'both'}: ${JSON.stringify(definition)}`);
  }
  const minZoom = definition.minZoom ?? 0;
  const maxZoom = definition.maxZoom ?? Infinity;
  const pixelRatio = definition.pixelRatio ?? display.getDefaultDisplaySync().densityPixels;
  if (!(Number.isFinite(minZoom) && minZoom >= 0)) {
    throw new Error(`An offline region's minZoom must be finite and at least 0: ${minZoom}`);
  }
  if (!(maxZoom >= minZoom)) {
    throw new Error(`An offline region's maxZoom must be at least its minZoom, ${minZoom}: ${maxZoom}`);
  }
  if (!(Number.isFinite(pixelRatio) && pixelRatio > 0)) {
    throw new Error(`An offline region's pixelRatio must be finite and greater than 0: ${pixelRatio}`);
  }
  const includeIdeographs = definition.includeIdeographs ?? false;
  if (bounds !== undefined) {
    checkBounds(bounds);
    return {
      kind: 'tilePyramid',
      value: {
        styleUrl: definition.styleUrl,
        bounds: { southwest: bounds.southwest, northeast: bounds.northeast },
        minZoom: minZoom,
        maxZoom: maxZoom,
        pixelRatio: pixelRatio,
        includeIdeographs: includeIdeographs,
      },
    };
  }
  checkGeometry(geometry!);
  return {
    kind: 'geometry',
    value: {
      styleUrl: definition.styleUrl,
      geometry: geometry,
      minZoom: minZoom,
      maxZoom: maxZoom,
      pixelRatio: pixelRatio,
      includeIdeographs: includeIdeographs,
    },
  };
}

function fromFfiDefinition(definition: FfiDefinition): OfflineRegionDefinition | undefined {
  if (definition.kind === 'tilePyramid') {
    const value = definition.value;
    return {
      styleUrl: value.styleUrl,
      bounds: {
        southwest: { latitude: value.bounds.southwest.latitude, longitude: value.bounds.southwest.longitude },
        northeast: { latitude: value.bounds.northeast.latitude, longitude: value.bounds.northeast.longitude },
      },
      minZoom: value.minZoom,
      maxZoom: value.maxZoom,
      pixelRatio: value.pixelRatio,
      includeIdeographs: value.includeIdeographs,
    };
  }
  if (definition.kind === 'geometry') {
    const value = definition.value;
    return {
      styleUrl: value.styleUrl,
      geometry: value.geometry as GeoJsonGeometry,
      minZoom: value.minZoom,
      maxZoom: value.maxZoom,
      pixelRatio: value.pixelRatio,
      includeIdeographs: value.includeIdeographs,
    };
  }
  return undefined;
}

function fromFfiStatus(status: FfiStatus): OfflineRegionStatus {
  return {
    downloading: status.downloadState === OfflineRegionDownloadState.active,
    complete: status.complete,
    completedResourceCount: Number(status.completedResourceCount),
    requiredResourceCount: Number(status.requiredResourceCount),
    requiredResourceCountPrecise: status.requiredResourceCountIsPrecise,
    completedResourceBytes: Number(status.completedResourceSize),
    completedTileCount: Number(status.completedTileCount),
    requiredTileCount: Number(status.requiredTileCount),
    completedTileBytes: Number(status.completedTileSize),
  };
}

// The runtime that a region's calls go to: it opens the FFI runtime, and
// forgets a region once it's deleted.
export interface RegionOwner {
  open(): Promise<RuntimeHandle>;
  forget(region: StoredRegion): void;
}

// The one object of a region in the cache database. It takes the region's
// events from its runtime.
@ObservedV2
export class StoredRegion implements OfflineRegion {
  readonly id: string;
  readonly regionId: bigint;
  private readonly owner: RegionOwner;
  @Trace private info: OfflineRegionInfo;
  @Trace private currentStatus: OfflineRegionStatus = NO_STATUS;
  @Trace private isDeleted: boolean = false;
  @Trace private error: Error | undefined = undefined;

  constructor(info: OfflineRegionInfo, owner: RegionOwner) {
    this.id = info.id.toString();
    this.regionId = info.id;
    this.info = info;
    this.owner = owner;
  }

  get definition(): OfflineRegionDefinition | undefined {
    return fromFfiDefinition(this.info.definition);
  }

  get metadata(): Uint8Array {
    return this.info.metadata;
  }

  get status(): OfflineRegionStatus {
    return this.currentStatus;
  }

  get deleted(): boolean {
    return this.isDeleted;
  }

  get downloadError(): Error | undefined {
    return this.error;
  }

  startDownload(): Promise<void> {
    this.error = undefined;
    return this.setDownloadState(OfflineRegionDownloadState.active);
  }

  pauseDownload(): Promise<void> {
    return this.setDownloadState(OfflineRegionDownloadState.inactive);
  }

  async invalidate(): Promise<void> {
    await (await this.runtime()).invalidateOfflineRegion(this.regionId);
  }

  async setMetadata(metadata: Uint8Array): Promise<void> {
    this.info = await (await this.runtime()).updateOfflineRegionMetadata(this.regionId, metadata);
  }

  async delete(): Promise<void> {
    if (this.isDeleted) {
      return;
    }
    await (await this.runtime()).deleteOfflineRegion(this.regionId);
    this.markDeleted();
  }

  // The region as the cache database holds it now.
  async refresh(runtime: RuntimeHandle, info: OfflineRegionInfo): Promise<void> {
    this.info = info;
    this.currentStatus = fromFfiStatus(await runtime.getOfflineRegionStatus(this.regionId));
  }

  // Deleting a region stops its download, with no event to say so.
  markDeleted(): void {
    this.isDeleted = true;
    this.stopped();
    this.owner.forget(this);
  }

  // Its runtime closed, or it was deleted, which stops the download.
  stopped(): void {
    if (this.currentStatus.downloading) {
      this.currentStatus = fromStatus(this.currentStatus, false);
    }
  }

  onEvent(event: RuntimeEvent): void {
    const payload = event.payload;
    if (payload.kind === 'offlineRegionStatus') {
      this.currentStatus = fromFfiStatus(payload.value.status);
    } else if (payload.kind === 'offlineRegionResponseError') {
      // Through a variable of its own type, which the linter takes as an Error.
      const error = new MapResourceError(fromFfiReason(payload.value.reason), event.message);
      this.error = error;
    } else if (payload.kind === 'offlineRegionTileCountLimit') {
      this.error = new Error('The download stopped: the cache database holds the most tiles of MapLibre\'s ' +
        `demo server that it allows, ${payload.value.limit}`);
    }
  }

  private async setDownloadState(state: OfflineRegionDownloadState): Promise<void> {
    const runtime = await this.runtime();
    await runtime.setOfflineRegionDownloadState(this.regionId, state);
    this.currentStatus = fromFfiStatus(await runtime.getOfflineRegionStatus(this.regionId));
  }

  private runtime(): Promise<RuntimeHandle> {
    if (this.isDeleted) {
      return Promise.reject(new Error(`The offline region ${this.id} was deleted`));
    }
    return this.owner.open();
  }
}

function fromStatus(status: OfflineRegionStatus, downloading: boolean): OfflineRegionStatus {
  return {
    downloading: downloading,
    complete: status.complete,
    completedResourceCount: status.completedResourceCount,
    requiredResourceCount: status.requiredResourceCount,
    requiredResourceCountPrecise: status.requiredResourceCountPrecise,
    completedResourceBytes: status.completedResourceBytes,
    completedTileCount: status.completedTileCount,
    requiredTileCount: status.requiredTileCount,
    completedTileBytes: status.completedTileBytes,
  };
}
