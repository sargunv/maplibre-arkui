// Examples for the "Use maps offline" guide.

import util from '@ohos.util';

import { ConnectivityMode, MapRuntime, OfflineRegion, OfflineRegionDefinition } from '@maplibre/arkui';

import { STYLE } from './Common';

@ComponentV2
export struct DownloadExample {
  // #region download
  @Local region: OfflineRegion | undefined = undefined;

  async download(): Promise<void> {
    const definition: OfflineRegionDefinition = {
      styleUrl: STYLE,
      bounds: { southwest: { latitude: 48.81, longitude: 2.22 }, northeast: { latitude: 48.91, longitude: 2.42 } },
      minZoom: 10,
      maxZoom: 14,
    };
    const name = new util.TextEncoder().encodeInto('Paris');
    this.region = await MapRuntime.getDefault().createOfflineRegion(definition, name);
    await this.region.startDownload();
  }

  build() {
    Column({ space: 8 }) {
      if (this.region === undefined) {
        Button('Download Paris')
          .onClick(() => this.download().catch((error: Error) => console.error(error.message)))
      } else {
        Progress({
          value: this.region.status.completedResourceCount,
          total: Math.max(1, this.region.status.requiredResourceCount),
        })
        Text(this.region.status.complete ? 'Paris is ready offline' : 'Downloading Paris')
      }
    }
  }
  // #endregion download
}

// #region list-regions
async function regionNames(): Promise<string[]> {
  const regions = await MapRuntime.getDefault().getOfflineRegions();
  const decoder = new util.TextDecoder();
  return regions.map((region: OfflineRegion) => decoder.decodeToString(region.metadata));
}
// #endregion list-regions

// #region connectivity
function setMapsUseNetwork(allowed: boolean): void {
  MapRuntime.setConnectivityMode(allowed ? ConnectivityMode.AUTOMATIC : ConnectivityMode.FORCE_OFFLINE);
}
// #endregion connectivity

export const OFFLINE_FUNCTIONS: Object[] = [regionNames, setMapsUseNetwork];
