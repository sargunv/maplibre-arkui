// What runs on a runtime without a map on the page: snapshots, resource
// requests, offline regions, and the runtimes themselves.

import { describe, expect, it } from '@ohos/hypium';
import {
  GeoJsonGeometry,
  MapContent,
  MapResourceError,
  MapResourceErrorReason,
  MapResourceLoadRequest,
  MapResourceProvider,
  MapResourceRequest,
  MapResourceResponse,
  MapRuntime,
  MapRuntimeOptions,
  OfflineRegionDefinition,
  renderSnapshot,
} from '@maplibre/arkui';

import application from '@ohos.app.ability.application';
import display from '@ohos.display';
import fs from '@ohos.file.fs';
import util from '@ohos.util';

import { STYLE, STYLE_JSON, styleDocument } from '../testability/TestMaps';
import { expectNear, pixelAt, readPixels, until } from './helpers';

// A style that the cases' resource provider serves.
const APP_STYLE = 'app://styles/test.json';

// A cache file that no other case uses.
function cachePath(name: string): string {
  return `${application.getApplicationContext().cacheDir}/${name}-${Date.now()}.db`;
}

function deleteCache(path: string): void {
  for (const file of [path, `${path}-journal`, `${path}-wal`, `${path}-shm`]) {
    if (fs.accessSync(file)) {
      fs.unlinkSync(file);
    }
  }
}

// Gives `use` a runtime of its own with `options`, on a cache file that no
// other case uses, and releases it and deletes the file after.
async function withRuntime(name: string, options: MapRuntimeOptions,
  use: (runtime: MapRuntime) => Promise<void>): Promise<void> {
  const path = cachePath(name);
  const runtime = new MapRuntime({
    cachePath: path,
    resourceProvider: options.resourceProvider,
    rewriteUrl: options.rewriteUrl,
  });
  try {
    await use(runtime);
  } finally {
    await runtime.release();
    deleteCache(path);
  }
}

// Serves the test style at APP_STYLE, records what it served, and finds no
// other app:// resource.
function styleProvider(served: string[]): MapResourceProvider {
  return {
    urlPatterns: ['app://**'],
    load: async (request: MapResourceLoadRequest): Promise<MapResourceResponse | undefined> => {
      served.push(request.url);
      if (request.url === APP_STYLE) {
        return { data: new util.TextEncoder().encodeInto(STYLE_JSON) };
      }
      throw new MapResourceError(MapResourceErrorReason.NOT_FOUND, `No ${request.url}`);
    },
  };
}

const WORLD: OfflineRegionDefinition = {
  styleUrl: APP_STYLE,
  bounds: { southwest: { latitude: -10, longitude: -10 }, northeast: { latitude: 10, longitude: 10 } },
  minZoom: 0,
  maxZoom: 1,
  pixelRatio: 1,
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
      // No layer draws the sources, so the map requests none of their tiles.
      const source = (attribution: string): string =>
        `{"type":"vector","tiles":["https://tiles.invalid/{z}/{x}/{y}.pbf"],"attribution":"${attribution}"}`;
      const style = styleDocument(`{"version":8,"sources":{"a":${source('<b>A</b>')},"b":${source('B')},` +
        `"c":${source('<b>A</b>')}},"layers":[]}`);
      const snapshot = await renderSnapshot({ style: style, width: 16, height: 16, pixelRatio: 1 });
      await snapshot.image.release();
      expect(snapshot.attributions.join()).assertEqual('<b>A</b>,B');
    });

    it('rejects a snapshot whose style fails to load', 0, async () => {
      await expect(renderSnapshot({ style: 'file:///nonexistent/style.json', width: 16, height: 16, pixelRatio: 1 }))
        .assertPromiseIsRejected();
    });

    it('draws nothing for a tile that a provider rejects as not found', 0, async () => {
      // A raster over a blue background, whose tiles the provider rejects.
      const style = styleDocument('{"version":8,"sources":{"raster":{"type":"raster","tileSize":256,' +
        '"tiles":["app://tiles/{z}/{x}/{y}.png"]}},"layers":[' +
        '{"id":"background","type":"background","paint":{"background-color":"#0000ff"}},' +
        '{"id":"raster","type":"raster","source":"raster"}]}');
      const served: string[] = [];
      await withRuntime('not-found', { resourceProvider: styleProvider(served) }, async (runtime: MapRuntime) => {
        const snapshot = await renderSnapshot({ style: style, width: 16, height: 16, pixelRatio: 1, runtime: runtime });
        const pixels = await readPixels(snapshot.image);
        await snapshot.image.release();
        expect(served.some((url: string) => url.startsWith('app://tiles/'))).assertTrue();
        expect(pixelAt(pixels, 16, 8, 8).join()).assertEqual('0,0,255,255');
      });
    });

    // This case needs the network: rewriteUrl rewrites a host that doesn't
    // exist to one that does.
    it('rewrites request URLs with rewriteUrl', 0, async () => {
      const original = 'https://maps.invalid/style.json';
      const rewritten: string[] = [];
      const rewriteUrl = (request: MapResourceRequest): string | undefined => {
        rewritten.push(request.url);
        return request.url === original ? 'https://demotiles.maplibre.org/style.json' : undefined;
      };
      await withRuntime('rewrite', { rewriteUrl: rewriteUrl }, async (runtime: MapRuntime) => {
        const snapshot = await renderSnapshot({ style: original, width: 16, height: 16, pixelRatio: 1, runtime: runtime });
        await snapshot.image.release();
        expect(rewritten.indexOf(original)).assertLarger(-1);
      });
    });

    it('throws for a second runtime on a cache file that one uses', 0, async () => {
      const path = cachePath('shared');
      const first = new MapRuntime({ cachePath: path });
      try {
        expect(() => new MapRuntime({ cachePath: path })).assertThrowError(
          `Another runtime uses the cache database ${path}`);
      } finally {
        await first.release();
      }
      // Once the first is released, another can take the file.
      await new MapRuntime({ cachePath: path }).release();
      deleteCache(path);

      const files = application.getApplicationContext().filesDir;
      expect(() => new MapRuntime({ cachePath: `${files}/maplibre-cache.db` })).assertThrowError(
        `Another runtime uses the cache database ${files}/maplibre-cache.db`);
    });

    it('throws for configureDefault() once the default runtime exists', 0, () => {
      MapRuntime.getDefault();
      expect(() => MapRuntime.configureDefault({})).assertThrowError(
        'MapRuntime.configureDefault() must come before the first MapRuntime.getDefault()');
    });

    it('throws for an offline region without exactly one of bounds and geometry', 0, () => {
      const origin: GeoJsonGeometry = { type: 'Point', coordinates: [0, 0] };
      expect(() => MapRuntime.getDefault().createOfflineRegion({ styleUrl: APP_STYLE })).assertThrowError(
        `An offline region needs exactly one of bounds and geometry, not neither: {"styleUrl":"${APP_STYLE}"}`);
      expect(() => MapRuntime.getDefault().createOfflineRegion({
        styleUrl: APP_STYLE, bounds: WORLD.bounds, geometry: origin,
      })).assertThrowError(
        'An offline region needs exactly one of bounds and geometry, not both: ' +
          JSON.stringify({ styleUrl: APP_STYLE, bounds: WORLD.bounds, geometry: origin }));
    });

    it('keeps the default runtime\'s offline regions in the app\'s files, one object each', 0, async () => {
      const runtime = MapRuntime.getDefault();
      const region = await runtime.createOfflineRegion(WORLD, new util.TextEncoder().encodeInto('world'));
      try {
        // Its status is read by the time it resolves.
        expect(region.status.downloading).assertFalse();
        expect(region.status.complete).assertFalse();
        expect(new util.TextDecoder().decodeToString(region.metadata)).assertEqual('world');
        expect(region.definition?.bounds?.northeast.latitude).assertEqual(10);
        expect((await runtime.getOfflineRegions()).indexOf(region)).assertLarger(-1);
        const files = application.getApplicationContext().filesDir;
        expect(fs.accessSync(`${files}/maplibre-cache.db`)).assertTrue();
      } finally {
        await region.delete();
      }
      expect(region.deleted).assertTrue();
      expect((await runtime.getOfflineRegions()).indexOf(region)).assertEqual(-1);
    });

    it('downloads an offline region, whose status follows the download', 0, async () => {
      const served: string[] = [];
      await withRuntime('offline', { resourceProvider: styleProvider(served) }, async (runtime: MapRuntime) => {
        const region = await runtime.createOfflineRegion(WORLD);
        await region.startDownload();
        await until('the download completes', () => region.status.complete);
        expect(region.status.completedResourceCount).assertLarger(0);
        expect(region.downloadError).assertUndefined();
        expect(served.indexOf(APP_STYLE)).assertLarger(-1);
        await region.pauseDownload();
        expect(region.status.downloading).assertFalse();
      });
    });
  });
}
