import { describe, expect, it } from '@ohos/hypium';
import { CameraUpdateMode, LatLng, MapProjectionHandle, ScaleBarUnits, ScreenPoint } from '@maplibre/arkui';
import { Driver, MatchPattern, ON } from '@ohos.UiTest';

import { STYLE, testMap } from '../testability/TestMaps';
import { until } from './until';

// The meters per vp at the equator at zoom 0: the earth's circumference over
// a 512 vp world.
const EQUATOR_METERS_PER_PIXEL = 40075016.686 / 512;

function near(a: number, b: number, tolerance: number): boolean {
  return Math.abs(a - b) <= tolerance;
}

const map = testMap.controller;

async function jumpTo(latitude: number, zoom: number): Promise<void> {
  await map.updateCamera({
    mode: CameraUpdateMode.jump,
    camera: { center: { latitude: latitude, longitude: 10 }, zoom: zoom, bearing: 0, pitch: 0 },
  });
  await until('the frame shows the camera', () => near(map.frameCamera?.zoom ?? 0, zoom, 0.001));
}

// The scale bar in these units shows this label.
async function expectScaleBar(units: ScaleBarUnits, label: string): Promise<void> {
  testMap.scaleBar = units;
  const bar = await Driver.create().waitForComponent(ON.text(label), 5000);
  expect(bar !== null && bar !== undefined).assertTrue();
}

export default function ornamentsTest(): void {
  describe('Ornaments', () => {
    it('measures the scale bar at the zoom and latitude of the frame', 0, async () => {
      await until('the style loads', () => map.styleLoaded);
      // At 60 degrees, a meter spans twice as many vp as at the equator.
      await jumpTo(60, 5);
      expect(map.metersPerPixelAtLatitude(60) ?? 0).assertClose(EQUATOR_METERS_PER_PIXEL / 32 / 2, 0.01);
      try {
        // The bar is at most 100 vp, which spans 122 km, or 76 mi, here, and
        // 60 m, or 196 ft, at zoom 16.
        await expectScaleBar(ScaleBarUnits.metric, '100 km');
        await expectScaleBar(ScaleBarUnits.imperial, '50 mi');
        await jumpTo(60, 16);
        await expectScaleBar(ScaleBarUnits.metric, '50 m');
        await expectScaleBar(ScaleBarUnits.imperial, '100 ft');
        // At 85 degrees and zoom 22, 100 vp spans 0.16 m, or 0.53 ft, so the
        // bar counts in fractions rather than growing past 100 vp.
        await jumpTo(85, 22);
        await expectScaleBar(ScaleBarUnits.metric, '0.1 m');
        await expectScaleBar(ScaleBarUnits.imperial, '0.5 ft');
      } finally {
        testMap.scaleBar = undefined;
      }
    });

    it('turns the map north when the compass is tapped', 0, async () => {
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 3, bearing: 90, pitch: 0 } });
      await until('the frame shows the rotation', () => near(map.frameCamera?.bearing ?? 0, 90, 0.001));
      // UiTest doesn't see accessibility text, so it finds the needle, the
      // page's only polygons.
      const needle = await Driver.create().waitForComponent(ON.type('Polygon'), 5000);
      expect(needle !== null && needle !== undefined).assertTrue();
      await needle.click();
      await until('the camera rests facing north', () => {
        const bearing = map.camera?.bearing ?? 90;
        return near(bearing, 0, 0.001) || near(bearing, 360, 0.001);
      });
    });

    it('places a marker where FFI projects its coordinate', 0, async () => {
      const coordinate: LatLng = { latitude: 20, longitude: 30 };
      await map.updateCamera({
        mode: CameraUpdateMode.jump,
        camera: { center: { latitude: 15, longitude: 25 }, zoom: 4, bearing: 30, pitch: 20 },
      });
      testMap.marker = coordinate;
      try {
        await until('the frame shows the camera', () => near(map.frameCamera?.bearing ?? 0, 30, 0.001));
        const context = testMap.context!;
        await until('the marker is placed', () => context.getComponentUtils().getRectangleById('marker').size.width > 0);

        // The controller projects with the frame's view, as FFI does.
        const handle = map.map!;
        const projection = MapProjectionHandle.create(handle.getSnapshot().view);
        const expected: ScreenPoint = projection.pixelForLatLng(coordinate);
        projection.release();
        const point = map.pixelForLatLng(coordinate)!;
        expect(point.x).assertClose(expected.x, 0.01);
        expect(point.y).assertClose(expected.y, 0.01);
        expect(map.latLngForPixel(point)?.latitude).assertClose(coordinate.latitude, 0.0001);

        // The marker's bottom center sits on that point of the map.
        const utils = context.getComponentUtils();
        const box = utils.getRectangleById('marker');
        const host = utils.getRectangleById('map-host');
        const x = context.px2vp(box.windowOffset.x + box.size.width / 2 - host.windowOffset.x);
        const y = context.px2vp(box.windowOffset.y + box.size.height - host.windowOffset.y);
        expect(x).assertClose(expected.x, 1);
        expect(y).assertClose(expected.y, 1);
      } finally {
        testMap.marker = undefined;
      }
    });

    // MapLibre Native reads the attribution of tiled sources only, so the
    // style has no layers, which keeps the map from requesting their tiles.
    it('collects the attribution of the style sources', 0, async () => {
      const attribution = '<a href="https://example.com/">Example &amp; Co</a> &copy; Test';
      const source: Record<string, Object> = {
        'type': 'vector',
        'tiles': ['file:///nonexistent/{z}/{x}/{y}.pbf'],
        'attribution': attribution,
      };
      const sources: Record<string, Object> = { 'a': source, 'b': source };
      const style: Record<string, Object> = { 'version': 8, 'sources': sources, 'layers': [] as Object[] };
      testMap.style = JSON.stringify(style);
      await until('the attribution shows', () => map.attributions.length > 0);
      expect(JSON.stringify(map.attributions)).assertEqual(JSON.stringify([attribution]));
      const driver = Driver.create();
      const text = await driver.waitForComponent(ON.text('Example & Co', MatchPattern.CONTAINS), 5000);
      expect(text !== null && text !== undefined).assertTrue();

      testMap.style = STYLE;
      await until('the attribution goes', () => map.attributions.length === 0 && map.styleLoaded);
    });
  });
}
