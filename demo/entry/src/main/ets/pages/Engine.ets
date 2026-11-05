import {
  addRuntimeEventListener,
  getDefaultRuntime,
  OfflineRegionDefinition,
  OfflineRegionDownloadState,
  OfflineRegionInfo,
  OfflineRegionStatus,
  removeRuntimeEventListener,
  ResourceKind,
  ResourceTransformRequestHandle,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeHandle,
  snapshot,
} from '@maplibre/arkui';
import image from '@ohos.multimedia.image';
import util from '@ohos.util';

import { LIBERTY } from './TwoMaps';

// A style URL on a host that doesn't exist, which the page's resource
// transform rewrites to LIBERTY.
const REWRITTEN = 'https://styles.demo.invalid/liberty';

const PARIS: OfflineRegionDefinition = {
  kind: 'tilePyramid',
  value: {
    styleUrl: LIBERTY,
    bounds: { southwest: { latitude: 48.81, longitude: 2.22 }, northeast: { latitude: 48.91, longitude: 2.42 } },
    minZoom: 10,
    maxZoom: 14,
    pixelRatio: 2,
    includeIdeographs: false,
  },
};

// A snapshot of a style whose URL a resource transform rewrites, and the
// download of an offline region, on the default runtime.
@ComponentV2
export struct Engine {
  @Local preview: image.PixelMap | undefined = undefined;
  @Local requests: number = 0;
  @Local region: OfflineRegionInfo | undefined = undefined;
  @Local status: OfflineRegionStatus | undefined = undefined;
  @Local message: string = '';
  private runtime: RuntimeHandle | undefined = undefined;
  private readonly listener: (event: RuntimeEvent) => void = (event: RuntimeEvent) => this.onEvent(event);

  aboutToAppear(): void {
    this.start().catch((error: Error) => this.message = error.message);
  }

  aboutToDisappear(): void {
    const runtime = this.runtime;
    if (runtime !== undefined) {
      runtime.discarding.clearResourceTransform();
      removeRuntimeEventListener(runtime, this.listener);
    }
    this.preview?.release();
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          Text('A snapshot, which no map on screen renders').fontSize(16).fontWeight(FontWeight.Medium)
          if (this.preview !== undefined) {
            Image(this.preview)
              .width(320)
              .height(200)
              .borderRadius(8)
          } else {
            Text('Rendering…').height(200)
          }
          Text(`Its style URL is ${REWRITTEN}, which a resource transform rewrites. ` +
            `The transform has seen ${this.requests} requests.`)
            .fontSize(14)
          Text('An offline region of Paris, zoom 10 to 14').fontSize(16).fontWeight(FontWeight.Medium)
          Text(this.describeRegion()).fontSize(14)
          Row({ space: 8 }) {
            Button('Download').onClick(() => this.report(this.download()))
            Button('Pause').enabled(this.region !== undefined).onClick(() => this.report(this.pause()))
            Button('Delete').enabled(this.region !== undefined).onClick(() => this.report(this.delete()))
          }
          if (this.message !== '') {
            Text(this.message).fontSize(14).fontColor(Color.Red)
          }
        }
        .padding(16)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
    }
    .title('Snapshots, requests, offline')
  }

  private async start(): Promise<void> {
    const runtime = await getDefaultRuntime();
    this.runtime = runtime;
    runtime.discarding.setResourceTransform({
      callback: (kind: ResourceKind, url: string, request: ResourceTransformRequestHandle) => {
        this.requests++;
        if (url === REWRITTEN) {
          console.info(`MapLibre demo: the transform rewrote ${url} to ${LIBERTY}`);
          request.complete(LIBERTY);
        } else {
          request.complete(url);
        }
      },
    });
    addRuntimeEventListener(runtime, this.listener);
    // The cache database outlasts the app, so a region from an earlier launch
    // is still there.
    const regions = await runtime.listOfflineRegions();
    if (regions.length > 0) {
      await this.show(regions[0]);
    }
    this.preview = await snapshot({
      style: REWRITTEN,
      width: 320,
      height: 200,
      camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14, pitch: 45 },
    });
  }

  private async download(): Promise<void> {
    const runtime = await getDefaultRuntime();
    let region = this.region;
    if (region === undefined) {
      region = await runtime.createOfflineRegion(PARIS, new util.TextEncoder().encodeInto('Paris'));
      await this.show(region);
    }
    await runtime.setOfflineRegionDownloadState(region.id, OfflineRegionDownloadState.active);
  }

  private async pause(): Promise<void> {
    if (this.region !== undefined) {
      const runtime = await getDefaultRuntime();
      await runtime.setOfflineRegionDownloadState(this.region.id, OfflineRegionDownloadState.inactive);
      this.status = await runtime.getOfflineRegionStatus(this.region.id);
    }
  }

  private async delete(): Promise<void> {
    if (this.region !== undefined) {
      const runtime = await getDefaultRuntime();
      const id = this.region.id;
      this.region = undefined;
      this.status = undefined;
      await runtime.deleteOfflineRegion(id);
    }
  }

  // Shows a region's progress, and the progress events of its download.
  private async show(region: OfflineRegionInfo): Promise<void> {
    const runtime = await getDefaultRuntime();
    this.region = region;
    this.status = await runtime.getOfflineRegionStatus(region.id);
    await runtime.setOfflineRegionObserved(region.id,
      RuntimeEventFlag.offlineRegionStatusChanged | RuntimeEventFlag.offlineRegionResponseError);
  }

  private onEvent(event: RuntimeEvent): void {
    const payload = event.payload;
    if (payload.kind === 'offlineRegionStatus' && payload.value.regionId === this.region?.id) {
      this.status = payload.value.status;
    } else if (payload.kind === 'offlineRegionResponseError' && payload.value.regionId === this.region?.id) {
      this.message = event.message;
    }
  }

  private describeRegion(): string {
    const status = this.status;
    if (status === undefined) {
      return 'Not downloaded';
    }
    const megabytes = (Number(status.completedResourceSize) / 1e6).toFixed(1);
    const state = status.complete ? 'complete' :
      status.downloadState === OfflineRegionDownloadState.active ? 'downloading' : 'paused';
    return `${status.completedResourceCount} of ${status.requiredResourceCount} resources, ` +
      `${megabytes} MB, ${state}`;
  }

  private report(work: Promise<void>): void {
    this.message = '';
    work.catch((error: Error) => this.message = error.message);
  }
}
