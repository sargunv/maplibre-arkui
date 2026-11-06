import { beforeEach, describe, expect, it } from '@ohos/hypium';
import { CameraUpdateMode, LatLng, ScaleBarUnits, ScreenPoint } from '@maplibre/arkui';
import { Component, Driver, MatchPattern, ON, Point, Rect as Bounds } from '@ohos.UiTest';

import { STYLE, testMap } from '../testability/TestMaps';
import {
  eventually,
  expectNear,
  inMap,
  mapBounds,
  near,
  pixelFor,
  rgb,
  screenPixel,
  until,
  vp2px,
  WAIT_MS,
} from './helpers';

// The meters per vp at the equator at zoom 0: the earth's circumference over
// a 512 vp world.
const EQUATOR_METERS_PER_PIXEL = 40075016.686 / 512;

const map = testMap.controller;

async function jumpTo(latitude: number, zoom: number): Promise<void> {
  await map.updateCamera({
    mode: CameraUpdateMode.jump,
    camera: { center: { latitude: latitude, longitude: 10 }, zoom: zoom, bearing: 0, pitch: 0 },
  });
  await until('the frame shows the camera', () => near(map.frameCamera?.zoom ?? 0, zoom, 0.001));
}

// The test style's background, which the map shows where no ornament covers it.
const BACKGROUND = rgb('#4a90d9');

// A style whose two sources have this attribution. MapLibre Native reads the
// attribution of tiled sources only, so the style has no layers, which keeps
// the map from requesting their tiles.
const ATTRIBUTION = '<a href="https://example.com/">Example &amp; Co</a> &copy; Test';

function attributedStyle(): string {
  const source: Record<string, Object> = {
    'type': 'vector',
    'tiles': ['file:///nonexistent/{z}/{x}/{y}.pbf'],
    'attribution': ATTRIBUTION,
  };
  const sources: Record<string, Object> = { 'a': source, 'b': source };
  const style: Record<string, Object> = { 'version': 8, 'sources': sources, 'layers': [] as Object[] };
  return JSON.stringify(style);
}

// Whether a pixel is far from the map's background, as an ornament's is.
function covered(pixel: number[]): boolean {
  return pixel.some((channel: number, i: number) => Math.abs(channel - BACKGROUND[i]) > 40);
}

// Waits until `find` finds a component, or finds none.
async function untilFound(what: string, find: () => Promise<Component | null>): Promise<Component> {
  return eventually(what, async () => (await find()) ?? undefined);
}

async function untilGone(what: string, find: () => Promise<Component | null>): Promise<void> {
  await eventually(what, async () => (await find()) === null ? true : undefined);
}

function center(bounds: Bounds): Point {
  return { x: Math.round((bounds.left + bounds.right) / 2), y: Math.round((bounds.top + bounds.bottom) / 2) };
}

// The scale bar in these units shows this label.
async function expectScaleBar(units: ScaleBarUnits, label: string): Promise<void> {
  testMap.scaleBar = units;
  const bar = await Driver.create().waitForComponent(ON.text(label), WAIT_MS);
  expect(bar !== null && bar !== undefined).assertTrue();
}

export default function ornamentsTest(): void {
  describe('Ornaments', () => {
    beforeEach(async () => {
      await testMap.reset();
    });

    it('measures the scale bar at the zoom and latitude of the frame', 0, async () => {
      // At 60 degrees, a meter spans twice as many vp as at the equator.
      await jumpTo(60, 5);
      const expected = EQUATOR_METERS_PER_PIXEL / 32 / 2;
      expectNear(map.metersPerPixelAtLatitude(60) ?? 0, expected, expected * 1e-4);
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
    });

    it('turns the map north when the compass is tapped', 0, async () => {
      testMap.compass = true;
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 3, bearing: 90, pitch: 0 } });
      await until('the frame shows the rotation', () => near(map.frameCamera?.bearing ?? 0, 90, 0.001));
      // UiTest doesn't see accessibility text, so it finds the needle, the
      // page's only polygons.
      const needle = await Driver.create().waitForComponent(ON.type('Polygon'), WAIT_MS);
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
      const utils = testMap.context!.getComponentUtils();
      await until('the marker is placed', () => utils.getRectangleById('marker').size.width > 0);

      // The controller projects with the frame's view, as FFI does.
      const expected: ScreenPoint = pixelFor(coordinate);
      const point = map.pixelForLatLng(coordinate)!;
      expectNear(point.x, expected.x, 0.001);
      expectNear(point.y, expected.y, 0.001);
      expectNear(map.latLngForPixel(point)?.latitude ?? NaN, coordinate.latitude, 1e-6);

      // The marker's bottom center sits on that point of the map, to within
      // ArkUI's rounding of its layout to whole px. ComponentUtils misplaces
      // content that markAnchor moves, so UiTest finds it.
      const marker = await Driver.create().findComponent(ON.id('marker'));
      const box = await marker.getBounds();
      const at = inMap(await mapBounds(), { x: (box.left + box.right) / 2, y: box.bottom });
      expectNear(at.x, expected.x, 1);
      expectNear(at.y, expected.y, 1);
    });

    it('collects the attribution of the style sources', 0, async () => {
      testMap.style = attributedStyle();
      await until('the attribution shows', () => map.attributions.length > 0);
      expect(JSON.stringify(map.attributions)).assertEqual(JSON.stringify([ATTRIBUTION]));
      const driver = Driver.create();
      const text = await driver.waitForComponent(ON.text('Example & Co', MatchPattern.CONTAINS), WAIT_MS);
      expect(text !== null && text !== undefined).assertTrue();

      testMap.style = STYLE;
      await until('the attribution goes', () => map.attributions.length === 0 && map.styleLoaded);
    });
    it('folds the attribution, and hides it while attributionEnabled is off', 0, async () => {
      testMap.style = attributedStyle();
      const driver = Driver.create();
      const text = ON.text('Example & Co', MatchPattern.CONTAINS);
      await untilFound('the attribution shows', () => driver.findComponent(text));
      // The page's only button, without the zoom buttons, folds it.
      const button = await untilFound('the button shows', () => driver.findComponent(ON.type('Button')));
      await button.click();
      await untilGone('the attribution folds', () => driver.findComponent(text));
      await button.click();
      await untilFound('the attribution unfolds', () => driver.findComponent(text));

      testMap.attribution = false;
      await untilGone('the attribution goes', () => driver.findComponent(ON.type('Button')));
      expect(await driver.findComponent(text)).assertNull();
      expect(map.attributions.length).assertEqual(1);
    });

    it('shows the scale bar that scaleBarEnabled turns on', 0, async () => {
      // At zoom 1 on the equator, 100 vp spans 3914 km, or 2432 mi.
      const label = ON.text('2000 ', MatchPattern.STARTS_WITH);
      const driver = Driver.create();
      testMap.scaleBarEnabled = true;
      await untilFound('the scale bar shows', () => driver.findComponent(label));
      testMap.scaleBarEnabled = false;
      await untilGone('the scale bar goes', () => driver.findComponent(label));
    });

    it('grows the scale bar up to its maxWidth', 0, async () => {
      // 100 vp spans 122 km here, so 50 vp spans 61 km and 300 vp 367 km.
      await jumpTo(60, 5);
      testMap.scaleBarMaxWidth = 50;
      await expectScaleBar(ScaleBarUnits.metric, '50 km');
      testMap.scaleBarMaxWidth = 300;
      await expectScaleBar(ScaleBarUnits.metric, '200 km');
    });

    it('zooms in and out with the zoom buttons', 0, async () => {
      testMap.zoomButtons = true;
      const driver = Driver.create();
      await untilFound('the zoom buttons show', () => driver.findComponent(ON.type('Button')));
      // Zoom in is above zoom out, and the style has no attribution button.
      const buttons = await driver.findComponents(ON.type('Button'));
      expect(buttons.length).assertEqual(2);
      await buttons[0].click();
      await until('the camera rests a level in', () => near(map.camera?.zoom ?? 0, 2, 0.001));
      await buttons[1].click();
      await until('the camera rests a level out', () => near(map.camera?.zoom ?? 0, 1, 0.001));
    });

    it('shows an alwaysShown compass while the map faces north', 0, async () => {
      // The app's compass is at the map's top start, and the map's own at its
      // top end, 8 vp in. Each is a 40 vp disc; the points sampled are on the
      // disc but beside the needle.
      testMap.alwaysShownCompass = true;
      testMap.compass = true;
      await until('the map shows a frame', () => map.frameCamera !== undefined);
      const bounds = await mapBounds();
      const own: Point = { x: bounds.left + Math.round(vp2px(29)), y: bounds.top + Math.round(vp2px(29)) };
      const builtIn: Point = { x: bounds.right - Math.round(vp2px(19)), y: bounds.top + Math.round(vp2px(37)) };
      await eventually('the app\'s compass shows', async () => covered(await screenPixel(own)) ? true : undefined);
      expect(covered(await screenPixel(builtIn))).assertFalse();

      // The map's own compass shows once the map turns.
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { bearing: 90 } });
      await eventually('the map\'s compass shows', async () => covered(await screenPixel(builtIn)) ? true : undefined);
    });

    it('keeps the ornaments inside ornamentPadding', 0, async () => {
      testMap.compass = true;
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { bearing: 90 } });
      const driver = Driver.create();
      const needle = await untilFound('the compass shows', () => driver.findComponent(ON.type('Polygon')));
      const before = center(await needle.getBounds());

      testMap.ornamentPadding = { top: 40, right: 60 };
      const after = await eventually('the compass moves', async () => {
        const moved = await driver.findComponent(ON.type('Polygon'));
        const point = center(await moved.getBounds());
        return point.y !== before.y ? point : undefined;
      });
      expectNear(after.x - before.x, -vp2px(60), 2);
      expectNear(after.y - before.y, vp2px(40), 2);
    });

    it('places a marker by its anchor', 0, async () => {
      const coordinate: LatLng = { latitude: 10, longitude: 20 };
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { center: coordinate, zoom: 4 } });
      const utils = testMap.context!.getComponentUtils();
      const driver = Driver.create();
      const placed = async (): Promise<Bounds> => (await driver.findComponent(ON.id('marker'))).getBounds();

      // The box's top-left corner on the coordinate.
      testMap.markerAnchor = { x: 0, y: 0 };
      testMap.marker = coordinate;
      await until('the marker is placed', () => utils.getRectangleById('marker').size.width > 0);
      const expected: ScreenPoint = pixelFor(coordinate);
      const bounds = await mapBounds();
      const corner = await placed();
      let at = inMap(bounds, { x: corner.left, y: corner.top });
      expectNear(at.x, expected.x, 1);
      expectNear(at.y, expected.y, 1);

      // The middle of its end edge, as percentages of the box.
      testMap.markerAnchor = { x: '100%', y: '50%' };
      const box = await eventually('the marker moves', async () => {
        const moved = await placed();
        return near(inMap(bounds, { x: moved.right, y: moved.top }).x, expected.x, 1) ? moved : undefined;
      });
      at = inMap(bounds, { x: box.right, y: (box.top + box.bottom) / 2 });
      expectNear(at.y, expected.y, 1);
    });
  });
}
