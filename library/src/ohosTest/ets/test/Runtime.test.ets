// What runs on a runtime without a map on the page: snapshots, resource
// requests, and offline regions.

import { describe, expect, it } from '@ohos/hypium';
import {
  addRuntimeEventListener,
  GeoJsonGeometry,
  getDefaultRuntime,
  MapContent,
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
  renderSnapshot,
  RuntimeHandle,
  UrlMatchFlag,
} from '@maplibre/arkui';

import application from '@ohos.app.ability.application';
import display from '@ohos.display';
import fs from '@ohos.file.fs';
import util from '@ohos.util';

import { STYLE, STYLE_JSON, styleDocument } from '../testability/TestMaps';
import { expectNear, pixelAt, readPixels, settled } from './helpers';

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
      const image = (await renderSnapshot({ style: STYLE, width: 64, height: 32, pixelRatio: 2 })).image;
      const size = image.getImageInfoSync().size;
      expect(size.width).assertEqual(128);
      expect(size.height).assertEqual(64);
      await image.release();
    });

    it('renders a snapshot at the display\'s density by default', 0, async () => {
      const density = display.getDefaultDisplaySync().densityPixels;
      const image = (await renderSnapshot({ style: STYLE, width: 64, height: 32 })).image;
      const size = image.getImageInfoSync().size;
      expectNear(size.width, 64 * density, 1);
      expectNear(size.height, 32 * density, 1);
      await image.release();
    });

    it('rounds a snapshot\'s size up to whole pixels', 0, async () => {
      const image = (await renderSnapshot({ style: STYLE, width: 33, height: 20, pixelRatio: 1.5 })).image;
      const size = image.getImageInfoSync().size;
      expect(size.width).assertEqual(50);
      expect(size.height).assertEqual(30);
      await image.release();
    });

    it('throws for a snapshot size of 0 before it renders', 0, () => {
      expect(() => renderSnapshot({ style: STYLE, width: 0, height: 16 })).assertThrowError(
        'A snapshot\'s width must be finite and at least 1 vp once rounded: 0');
    });

    it('centers a snapshot camera that sets only a zoom at 0, 0, not at the style\'s center', 0, async () => {
      // The style's own camera is far from 0, 0, where the content draws a dot.
      const style = styleDocument('{"version":8,"center":[100,40],"zoom":3,"sources":{},"layers":[' +
        '{"id":"background","type":"background","paint":{"background-color":"#0000ff"}}]}');
      const origin: GeoJsonGeometry = { type: 'Point', coordinates: [0, 0] };
      const dot: MapContent = {
        sources: [{ id: 'dot', json: { 'type': 'geojson', 'data': origin } }],
        layers: [{ id: 'dot', type: 'circle', source: 'dot', paint: { 'circle-color': '#ff0000', 'circle-radius': 8 } }],
      };
      const image = (await renderSnapshot({
        style: style, content: dot, width: 64, height: 32, pixelRatio: 1, camera: { zoom: 0 },
      })).image;
      const pixels = await readPixels(image);
      await image.release();
      expect(pixelAt(pixels, 64, 32, 16).join()).assertEqual('255,0,0,255');
    });

    it('lists the style\'s source attributions with a snapshot', 0, async () => {
      const style = styleDocument('{"version":8,"sources":{' +
        '"a":{"type":"geojson","data":{"type":"FeatureCollection","features":[]},"attribution":"<b>A</b>"},' +
        '"b":{"type":"geojson","data":{"type":"FeatureCollection","features":[]},"attribution":"B"},' +
        '"c":{"type":"geojson","data":{"type":"FeatureCollection","features":[]},"attribution":"<b>A</b>"}},' +
        '"layers":[]}');
      const snapshot = await renderSnapshot({ style: style, width: 16, height: 16, pixelRatio: 1 });
      await snapshot.image.release();
      expect(snapshot.attributions.join()).assertEqual('<b>A</b>,B');
    });

    it('rejects a snapshot whose style fails to load', 0, async () => {
      await expect(renderSnapshot({ style: 'file:///nonexistent/style.json', width: 16, height: 16, pixelRatio: 1 }))
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
        const snapshot = await renderSnapshot({ style: original, width: 16, height: 16, pixelRatio: 1, runtime: runtime });
        await snapshot.image.release();
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
