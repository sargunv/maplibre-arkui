import { describe, expect, it } from '@ohos/hypium';
import {
  addRuntimeEventListener,
  clearLogCallback,
  LogEvent,
  OfflineRegionDefinition,
  OfflineRegionDownloadState,
  getDefaultRuntime,
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
  setLogCallback,
  snapshot,
  UrlMatchFlag,
} from '@maplibre/arkui';

import application from '@ohos.app.ability.application';
import fs from '@ohos.file.fs';
import util from '@ohos.util';

// Blue, with the western hemisphere red, so the image's halves differ.
const HALVES = '{"version":8,"sources":{"west":{"type":"geojson","data":{"type":"Polygon",' +
  '"coordinates":[[[-180,-85],[0,-85],[0,85],[-180,85],[-180,-85]]]}}},"layers":[' +
  '{"id":"background","type":"background","paint":{"background-color":"#0000ff"}},' +
  '{"id":"west","type":"fill","source":"west","paint":{"fill-color":"#ff0000","fill-antialias":false}}]}';

// A style that the cases' resource provider serves.
const APP_STYLE = 'app://styles/halves.json';

// A runtime of its own, with a cache file that no other case uses.
function createRuntime(name: string): Promise<RuntimeHandle> {
  const cache = application.getApplicationContext().cacheDir;
  const path = `${cache}/${name}-${Date.now()}.db`;
  return RuntimeHandle.create({ cachePath: path });
}

// Serves the halves style at APP_STYLE, and records what it served.
function serveStyle(runtime: RuntimeHandle, served: string[]): void {
  runtime.discarding.setResourceProvider({
    routes: [{ flags: UrlMatchFlag.glob, url: 'app://**' }],
    callback: (request: ResourceRequestInfo, handle: ResourceRequestHandle) => {
      served.push(request.requestedUrl);
      if (request.requestedUrl === APP_STYLE) {
        handle.complete({ status: ResourceResponseStatus.ok, bytes: new util.TextEncoder().encodeInto(HALVES) });
      } else {
        handle.complete({ status: ResourceResponseStatus.error, errorReason: ResourceErrorReason.notFound });
      }
    },
  });
}

// Reads a pixel as [r, g, b, a].
function pixelAt(pixels: Uint8Array, width: number, x: number, y: number): number[] {
  const offset = (y * width + x) * 4;
  return [pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3]];
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

export default function engineTest(): void {
  describe('Engine', () => {
    it('renders a snapshot of the requested size', 0, async () => {
      const pixelMap = await snapshot({ style: HALVES, width: 64, height: 32, scaleFactor: 2, camera: { zoom: 0 } });
      const size = pixelMap.getImageInfoSync().size;
      expect(size.width).assertEqual(128);
      expect(size.height).assertEqual(64);
      const buffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
      await pixelMap.readPixelsToBuffer(buffer);
      const pixels = new Uint8Array(buffer);
      // The PixelMap's channels are in RGBA order.
      expect(pixelAt(pixels, 128, 32, 32).join()).assertEqual('255,0,0,255');
      expect(pixelAt(pixels, 128, 96, 32).join()).assertEqual('0,0,255,255');
      await pixelMap.release();
    });

    it('rejects a snapshot whose style fails to load', 0, async () => {
      let failed = false;
      try {
        await snapshot({ style: 'file:///nonexistent/style.json', width: 16, height: 16, scaleFactor: 1 });
      } catch (error) {
        failed = true;
      }
      expect(failed).assertTrue();
    });

    it('serves requests from a resource provider', 0, async () => {
      const runtime = await createRuntime('provider');
      const served: string[] = [];
      serveStyle(runtime, served);
      const pixelMap = await snapshot({ style: APP_STYLE, width: 16, height: 16, scaleFactor: 1, runtime: runtime });
      await pixelMap.release();
      expect(served.indexOf(APP_STYLE)).assertLarger(-1);
      await runtime.release();
    });

    // This case needs the network: the transform rewrites a host that doesn't
    // exist to one that does.
    it('rewrites request URLs with a resource transform', 0, async () => {
      const runtime = await createRuntime('transform');
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
      await runtime.release();
    });

    it('keeps the default runtime\'s offline regions in the app\'s files', 0, async () => {
      const runtime = await getDefaultRuntime();
      const metadata = new util.TextEncoder().encodeInto('world');
      const region = await runtime.createOfflineRegion(WORLD, metadata);
      const listed = (await runtime.listOfflineRegions()).map((stored) => stored.id);
      expect(listed.indexOf(region.id)).assertLarger(-1);
      const files = application.getApplicationContext().filesDir;
      expect(fs.accessSync(`${files}/maplibre-cache.db`)).assertTrue();
      await runtime.deleteOfflineRegion(region.id);
      const remaining = (await runtime.listOfflineRegions()).map((stored) => stored.id);
      expect(remaining.indexOf(region.id)).assertEqual(-1);
    });

    it('reports offline download progress to runtime listeners', 0, async () => {
      const runtime = await createRuntime('offline');
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
      await runtime.setOfflineRegionObserved(region.id, RuntimeEventFlag.offlineRegionStatusChanged);
      await runtime.setOfflineRegionDownloadState(region.id, OfflineRegionDownloadState.active);
      const status = await completed;
      removeRuntimeEventListener(runtime, listener);
      expect(Number(status.completedResourceCount)).assertLarger(0);
      expect(served.indexOf(APP_STYLE)).assertLarger(-1);
      await runtime.setOfflineRegionDownloadState(region.id, OfflineRegionDownloadState.inactive);
      await runtime.deleteOfflineRegion(region.id);
      await runtime.release();
    });

    it('sends the library\'s logs to the log callback', 0, async () => {
      const logged = new Promise<string>((resolve) => {
        setLogCallback({
          callback: (severity: number, event: LogEvent, code: bigint, message: string) => {
            if (event === LogEvent.parseStyle) {
              resolve(message);
            }
          },
        });
      });
      // MapLibre warns about a center that isn't a coordinate as it parses the
      // style.
      const style = '{"version":8,"center":"nowhere","sources":{},"layers":[]}';
      const pixelMap = await snapshot({ style: style, width: 16, height: 16, scaleFactor: 1 });
      await pixelMap.release();
      const message = await logged;
      clearLogCallback();
      expect(message.indexOf('center')).assertLarger(-1);
    });
  });
}
