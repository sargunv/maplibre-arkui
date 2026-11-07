import {
  AttributionText,
  MapResourceRequest,
  MapRuntime,
  MapSnapshot,
  OfflineRegion,
  OfflineRegionDefinition,
  renderSnapshot,
} from '@maplibre/arkui';
import util from '@ohos.util';

import { LIBERTY } from './common';

// A style URL on a host that doesn't exist, which the page's runtime rewrites
// to LIBERTY.
const REWRITTEN = 'https://styles.demo.invalid/liberty';

const PARIS: OfflineRegionDefinition = {
  styleUrl: LIBERTY,
  bounds: { southwest: { latitude: 48.81, longitude: 2.22 }, northeast: { latitude: 48.91, longitude: 2.42 } },
  minZoom: 10,
  maxZoom: 14,
};

// What a runtime does besides maps: a snapshot of a style whose URL the page's
// runtime rewrites, and the download of an offline region on the default
// runtime, whose cache database outlasts the app.
@ComponentV2
export struct RuntimeDemo {
  @Local preview: MapSnapshot | undefined = undefined;
  @Local requests: number = 0;
  @Local region: OfflineRegion | undefined = undefined;
  @Local message: string = '';
  // A runtime of the page's own, with its cache in memory, which rewrites
  // REWRITTEN.
  private readonly runtime: MapRuntime = new MapRuntime({
    rewriteUrl: (request: MapResourceRequest) => {
      this.requests++;
      return request.url === REWRITTEN ? LIBERTY : undefined;
    },
  });
  private gone: boolean = false;

  aboutToAppear(): void {
    this.start().catch((error: Error) => this.message = error.message);
  }

  aboutToDisappear(): void {
    this.gone = true;
    this.preview?.image.release();
    this.runtime.release().catch((error: Error) => console.error(error.message));
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          Text('A snapshot, which no map on screen renders').fontSize(16).fontWeight(FontWeight.Medium)
          if (this.preview !== undefined) {
            Image(this.preview.image)
              .width(320)
              .height(200)
              .borderRadius(8)
            AttributionText({ attributions: this.preview.attributions })
          } else {
            Text('Rendering…').height(200)
          }
          Text(`Its style URL is ${REWRITTEN}, which the runtime's rewriteUrl rewrites. ` +
            `It has seen ${this.requests} requests.`)
            .fontSize(14)
          Text('An offline region of Paris, zoom 10 to 14').fontSize(16).fontWeight(FontWeight.Medium)
          if (this.region !== undefined) {
            // The region's status is observable, so the progress follows the
            // download.
            Progress({
              value: this.region.status.completedResourceCount,
              total: Math.max(1, this.region.status.requiredResourceCount),
            })
              .width(320)
          }
          Text(this.describeRegion()).fontSize(14)
          Row({ space: 8 }) {
            Button('Download').onClick(() => this.report(this.download()))
            Button('Pause').enabled(this.region !== undefined).onClick(() => this.report(this.region!.pauseDownload()))
            Button('Delete').enabled(this.region !== undefined).onClick(() => this.report(this.delete()))
          }
          if (this.region?.downloadError !== undefined) {
            Text(this.region.downloadError.message).fontSize(14).fontColor(Color.Red)
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
    .title('Runtime')
  }

  private async start(): Promise<void> {
    // A region from an earlier launch is still there.
    const regions = await MapRuntime.getDefault().getOfflineRegions();
    if (!this.gone && regions.length > 0) {
      this.region = regions[0];
    }
    const preview = await renderSnapshot({
      style: REWRITTEN,
      width: 320,
      height: 200,
      camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14, pitch: 45 },
      uiContext: this.getUIContext(),
      runtime: this.runtime,
    });
    if (this.gone) {
      preview.image.release();
    } else {
      this.preview = preview;
    }
  }

  private async download(): Promise<void> {
    if (this.region === undefined) {
      this.region = await MapRuntime.getDefault().createOfflineRegion(PARIS,
        new util.TextEncoder().encodeInto('Paris'));
    }
    await this.region.startDownload();
  }

  private async delete(): Promise<void> {
    const region = this.region;
    this.region = undefined;
    await region?.delete();
  }

  private describeRegion(): string {
    const region = this.region;
    if (region === undefined) {
      return 'Not downloaded';
    }
    const status = region.status;
    const megabytes = (status.completedResourceBytes / 1e6).toFixed(1);
    const state = status.complete ? 'complete' : status.downloading ? 'downloading' : 'paused';
    return `${status.completedResourceCount} of ${status.requiredResourceCount} resources, ` +
      `${megabytes} MB, ${state}`;
  }

  private report(work: Promise<void>): void {
    this.message = '';
    work.catch((error: Error) => this.message = error.message);
  }
}
