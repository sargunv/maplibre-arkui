// What runs on a runtime without a map on the page: snapshots, resource
// requests, and offline regions.

import { describe, expect, it } from '@ohos/hypium';
import {
  addRuntimeEventListener,
  getDefaultRuntime,
  OfflineRegionDefinition,
  OfflineRegionDownloadState,
  OfflineRegionStatus,
  removeRuntimeEventListener,
  ResourceErrorReason,
  ResourceKind,
  ResourceRequestHandle,
  ResourceRequestInfo,
  ResourceResponseStatus,
  ResourceTransformRequestHandle,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeHandle,
  snapshot,
  UrlMatchFlag,
} from '@maplibre/arkui';

import application from '@ohos.app.ability.application';
import display from '@ohos.display';
import fs from '@ohos.file.fs';
import util from '@ohos.util';

import { STYLE_JSON } from '../testability/TestMaps';
import { expectNear, settled } from './helpers';

// A style that the cases' resource provider serves.
const APP_STYLE = 'app://styles/test.json';

// Gives `use` a runtime of its own, with a cache file that no other case uses,
// and deletes the file after.
async function withRuntime(name: string, use: (runtime: RuntimeHandle) => Promise<void>): Promise<void> {
  const path = `${application.getApplicationContext().cacheDir}/${name}-${Date.now()}.db`;
  const runtime = await RuntimeHandle.create({ cachePath: path });
  try {
    await use(runtime);
  } finally {
    await runtime.release();
    for (const file of [path, `${path}-journal`, `${path}-wal`, `${path}-shm`]) {
      if (fs.accessSync(file)) {
        fs.unlinkSync(file);
      }
    }
  }
}

// Serves the test style at APP_STYLE, and records what it served.
function serveStyle(runtime: RuntimeHandle, served: string[]): void {
  runtime.discarding.setResourceProvider({
    routes: [{ flags: UrlMatchFlag.glob, url: 'app://**' }],
    callback: (request: ResourceRequestInfo, handle: ResourceRequestHandle) => {
      served.push(request.requestedUrl);
      if (request.requestedUrl === APP_STYLE) {
        handle.complete({ status: ResourceResponseStatus.ok, bytes: new util.TextEncoder().encodeInto(STYLE_JSON) });
      } else {
        handle.complete({ status: ResourceResponseStatus.error, errorReason: ResourceErrorReason.notFound });
      }
    },
  });
}

const WORLD: OfflineRegionDefinition = {
  kind: 'tilePyramid',
  value: {
    styleUrl: APP_STYLE,
    bounds: { southwest: { latitude: -10, longitude: -10 }, northeast: { latitude: 10, longitude: 10 } },
    minZoom: 0,
    maxZoom: 1,
    pixelRatio: 1,
    includeIdeographs: false,
  },
};

export default function runtimeTest(): void {
  describe('Runtime', () => {
    it('renders a snapshot of the requested size', 0, async () => {
      const pixelMap = await snapshot({
        style: STYLE_JSON, width: 64, height: 32, scaleFactor: 2, camera: { zoom: 0 },
      });
      const size = pixelMap.getImageInfoSync().size;
      expect(size.width).assertEqual(128);
      expect(size.height).assertEqual(64);
      await pixelMap.release();
    });

    it('renders a snapshot at the display\'s density by default', 0, async () => {
      const density = display.getDefaultDisplaySync().densityPixels;
      const pixelMap = await snapshot({ style: STYLE_JSON, width: 64, height: 32, camera: { zoom: 0 } });
      const size = pixelMap.getImageInfoSync().size;
      expectNear(size.width, 64 * density, 1);
      expectNear(size.height, 32 * density, 1);
      await pixelMap.release();
    });

    it('rejects a snapshot whose style document is not JSON', 0, async () => {
      await expect(snapshot({ style: '{"version": 8, "sources": ', width: 16, height: 16, scaleFactor: 1 }))
        .assertPromiseIsRejected();
    });

    it('rejects a snapshot whose style fails to load', 0, async () => {
      await expect(snapshot({ style: 'file:///nonexistent/style.json', width: 16, height: 16, scaleFactor: 1 }))
        .assertPromiseIsRejected();
    });

    // This case needs the network: the transform rewrites a host that doesn't
    // exist to one that does.
    it('rewrites request URLs with a resource transform', 0, async () => {
      await withRuntime('transform', async (runtime: RuntimeHandle) => {
        const original = 'https://maps.invalid/style.json';
        const transformed: string[] = [];
        runtime.discarding.setResourceTransform({
          callback: (kind: ResourceKind, url: string, request: ResourceTransformRequestHandle) => {
            transformed.push(url);
            request.complete(url === original ? 'https://demotiles.maplibre.org/style.json' : url);
          },
        });
        const pixelMap = await snapshot({ style: original, width: 16, height: 16, scaleFactor: 1, runtime: runtime });
        await pixelMap.release();
        expect(transformed.indexOf(original)).assertLarger(-1);
      });
    });

    it('keeps the default runtime\'s offline regions in the app\'s files', 0, async () => {
      const runtime = await getDefaultRuntime();
      const metadata = new util.TextEncoder().encodeInto('world');
      const region = await runtime.createOfflineRegion(WORLD, metadata);
      try {
        const listed = (await runtime.listOfflineRegions()).map((stored) => stored.id);
        expect(listed.indexOf(region.id)).assertLarger(-1);
        const files = application.getApplicationContext().filesDir;
        expect(fs.accessSync(`${files}/maplibre-cache.db`)).assertTrue();
      } finally {
        await runtime.deleteOfflineRegion(region.id);
      }
      const remaining = (await runtime.listOfflineRegions()).map((stored) => stored.id);
      expect(remaining.indexOf(region.id)).assertEqual(-1);
    });

    it('reports offline download progress to runtime listeners', 0, async () => {
      await withRuntime('offline', async (runtime: RuntimeHandle) => {
        const served: string[] = [];
        serveStyle(runtime, served);
        const region = await runtime.createOfflineRegion(WORLD, new Uint8Array(0));
        let listener: (event: RuntimeEvent) => void = () => {
        };
        const completed = new Promise<OfflineRegionStatus>((resolve) => {
          listener = (event: RuntimeEvent) => {
            const payload = event.payload;
            if (payload.kind === 'offlineRegionStatus' && payload.value.regionId === region.id &&
              payload.value.status.complete) {
              resolve(payload.value.status);
            }
          };
        });
        addRuntimeEventListener(runtime, listener);
        try {
          await runtime.setOfflineRegionObserved(region.id, RuntimeEventFlag.offlineRegionStatusChanged);
          await runtime.setOfflineRegionDownloadState(region.id, OfflineRegionDownloadState.active);
          const status = await settled('the download completes', completed);
          expect(Number(status.completedResourceCount)).assertLarger(0);
          expect(served.indexOf(APP_STYLE)).assertLarger(-1);
        } finally {
          removeRuntimeEventListener(runtime, listener);
          await runtime.setOfflineRegionDownloadState(region.id, OfflineRegionDownloadState.inactive);
        }
      });
    });
  });
}
