import { describe, expect, it } from '@ohos/hypium';
import {
  CameraUpdateMode,
  defaultScaleBarUnits,
  LatLng,
  MapProjectionHandle,
  scaleBarLength,
  ScaleBarUnits,
  ScreenPoint,
} from '@maplibre/arkui';
import { Driver, MatchPattern, ON } from '@ohos.UiTest';

import { STYLE, testMap } from '../testability/TestMaps';
import { until } from './until';

// The meters per vp at the equator at zoom 0: the earth's circumference over
// a 512 vp world.
const EQUATOR_METERS_PER_PIXEL = 40075016.686 / 512;

function near(a: number, b: number, tolerance: number): boolean {
  return Math.abs(a - b) <= tolerance;
}

export default function ornamentsTest(): void {
  describe('Ornaments', () => {
    const map = testMap.controller;

    it('measures the scale bar at the zoom and latitude of the frame', 0, async () => {
      testMap.scaleBar = true;
      await until('the style loads', () => map.styleLoaded);
      await map.updateCamera({
        mode: CameraUpdateMode.jump,
        camera: { center: { latitude: 60, longitude: 10 }, zoom: 5, bearing: 0, pitch: 0 },
      });
      await until('the frame shows the camera', () => near(map.frameCamera?.zoom ?? 0, 5, 0.001));
      // At 60 degrees, a meter spans twice as many vp as at the equator.
      const metersPerPixel = map.metersPerPixelAtLatitude(60) ?? 0;
      expect(metersPerPixel).assertClose(EQUATOR_METERS_PER_PIXEL / 32 / 2, 0.01);

      const metric = scaleBarLength(metersPerPixel, 100, ScaleBarUnits.METRIC);
      expect(metric.label).assertEqual('100 km');
      expect(metric.width).assertClose(100000 / metersPerPixel, 0.001);
      const imperial = scaleBarLength(metersPerPixel, 100, ScaleBarUnits.IMPERIAL);
      expect(imperial.label).assertEqual('50 mi');
      expect(scaleBarLength(0.5, 100, ScaleBarUnits.METRIC).label).assertEqual('50 m');
      expect(scaleBarLength(0.5, 100, ScaleBarUnits.IMPERIAL).label).assertEqual('100 ft');

      // The bar on the map shows the same distance in the system's units.
      const shown = defaultScaleBarUnits() === ScaleBarUnits.METRIC ? metric.label : imperial.label;
      const bar = await Driver.create().waitForComponent(ON.text(shown), 5000);
      expect(bar !== null && bar !== undefined).assertTrue();
      testMap.scaleBar = false;
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
      testMap.marker = undefined;
    });

    // MapLibre Native reads the attribution of tiled sources only, so the
    // style has no layers, which keeps the map from requesting their tiles.
    it('collects the attribution of the style sources', 0, async () => {
      const attribution = '<a href="https://example.com/">Example &amp; Co</a> &copy; Test';
      testMap.style = JSON.stringify({
        version: 8,
        sources: {
          a: { type: 'vector', tiles: ['file:///nonexistent/{z}/{x}/{y}.pbf'], attribution: attribution },
          b: { type: 'vector', tiles: ['file:///nonexistent/{z}/{x}/{y}.pbf'], attribution: attribution },
        },
        layers: [],
      });
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
