import { beforeEach, describe, expect, it } from '@ohos/hypium';
import { CameraUpdateMode, LatLng, ScaleBarUnits, ScreenPoint } from '@maplibre/arkui';
import { Component, Driver, MatchPattern, ON, On, Point, Rect as Bounds } from '@ohos.UiTest';

import { STYLE, testMap, TestOverlay } from '../testability/TestMaps';
import {
  eventually,
  expectNear,
  frames,
  inMap,
  mapBounds,
  mapCenter,
  near,
  offset,
  pixelFor,
  until,
  vp2px,
  WAIT_MS,
} from './helpers';

// The meters per vp at the equator at zoom 0: the earth's circumference over
// a 512 vp world.
const EQUATOR_METERS_PER_PIXEL = 40075016.686 / 512;

const map = testMap.controller;

async function jumpTo(latitude: number, zoom: number, bearing: number = 0): Promise<void> {
  await map.updateCamera({
    mode: CameraUpdateMode.jump,
    camera: { center: { latitude: latitude, longitude: 10 }, zoom: zoom, bearing: bearing, pitch: 0 },
  });
  await until('the frame shows the camera', () => near(map.frameCamera?.zoom ?? 0, zoom, 0.001) &&
    near(map.frameCamera?.bearing ?? 0, bearing, 0.001));
}

// A style whose two sources have this attribution. MapLibre Native reads the
// attribution of tiled sources only, so the style has no layers, which keeps
// the map from requesting their tiles.
const ATTRIBUTION = '<a href="https://example.com/">Example &amp; Co</a> &copy; Test';
const ATTRIBUTION_TEXT = ON.text('Example & Co', MatchPattern.CONTAINS);

function attributedStyle(attribution: string = ATTRIBUTION): string {
  const source: Record<string, Object> = {
    'type': 'vector',
    'tiles': ['file:///nonexistent/{z}/{x}/{y}.pbf'],
    'attribution': attribution,
  };
  const sources: Record<string, Object> = { 'a': source, 'b': source };
  const style: Record<string, Object> = { 'version': 8, 'sources': sources, 'layers': [] as Object[] };
  return JSON.stringify(style);
}

// Waits until `find` finds a component, or finds none.
async function untilFound(what: string, find: () => Promise<Component | null>): Promise<Component> {
  return eventually(what, async () => (await find()) ?? undefined);
}

async function untilGone(what: string, find: () => Promise<Component | null>): Promise<void> {
  await eventually(what, async () => (await find()) === null ? true : undefined);
}

// UiTest searches the whole display, with the status bar, so these search
// the test page.
function onPage(on: On): On {
  return on.within(ON.id('map-host'));
}

function find(on: On): () => Promise<Component | null> {
  return () => Driver.create().findComponent(onPage(on));
}

async function count(on: On): Promise<number> {
  return (await Driver.create().findComponents(onPage(on)) ?? []).length;
}

// The scale bar in these units shows this label.
async function expectScaleBar(units: ScaleBarUnits, label: string): Promise<void> {
  testMap.scaleBar = units;
  const bar = await Driver.create().waitForComponent(ON.text(label), WAIT_MS);
  expect(bar !== null && bar !== undefined).assertTrue();
}

// Shows the map with `overlay` and the attributed style. A map without a
// trailing closure is a map of its own, so the page makes it afresh.
async function showOverlay(overlay: TestOverlay): Promise<void> {
  if (overlay === 'omitted') {
    testMap.shown = false;
    await until('the map leaves', () => map.map === undefined);
  }
  const loads = testMap.styleLoads;
  testMap.overlay = overlay;
  testMap.style = attributedStyle();
  testMap.shown = true;
  await until('the map loads the style', () => testMap.styleLoads > loads && map.styleLoaded);
  await until('the map shows a frame', () => map.frameCamera !== undefined);
}

// Whether the content that a placement wraps, the box with `id`, shows.
function placedVisible(id: string): boolean {
  return testMap.context!.getFrameNodeById(id)?.getParent()?.isVisible() ?? false;
}

async function bounds(id: string): Promise<Bounds | undefined> {
  return (await Driver.create().findComponent(ON.id(id)))?.getBounds();
}

// Waits until the box with `id` has the point that `corner` picks on
// `expected`, in the map's vp, to within ArkUI's rounding of layout to whole
// px. The box moves in the frame after the map draws, and ArkUI lays it out
// again once it knows its size, so the case waits for it to settle rather
// than reading it once.
async function untilPlaced(id: string, expected: ScreenPoint, corner: (box: Bounds) => Point): Promise<void> {
  const map = await mapBounds();
  let last: ScreenPoint = { x: NaN, y: NaN };
  try {
    await eventually(`the box is placed at ${JSON.stringify(expected)}`, async () => {
      const box = await bounds(id);
      if (box === undefined) {
        return undefined;
      }
      last = inMap(map, corner(box));
      return near(last.x, expected.x, 1) && near(last.y, expected.y, 1) ? true : undefined;
    });
  } catch (error) {
    throw new Error(`${(error as Error).message}; it was at ${JSON.stringify(last)}`);
  }
}

const TOP_LEFT = (box: Bounds): Point => ({ x: box.left, y: box.top });
const CENTER = (box: Bounds): Point => ({ x: (box.left + box.right) / 2, y: (box.top + box.bottom) / 2 });
const END_MIDDLE = (box: Bounds): Point => ({ x: box.right, y: (box.top + box.bottom) / 2 });
const TOP_MIDDLE = (box: Bounds): Point => ({ x: (box.left + box.right) / 2, y: box.top });

export default function overlayTest(): void {
  describe('Overlay', () => {
    beforeEach(async () => {
      await testMap.reset();
    });

    it('draws the default preset without a trailing closure', 0, async () => {
      await showOverlay('omitted');
      // The logo and the attribution show, and the attribution's button is
      // the only button.
      await untilFound('the logo shows', find(ON.type('Image')));
      await untilFound('the attribution shows', find(ATTRIBUTION_TEXT));
      expect(await count(ON.type('Button'))).assertEqual(1);
      // The scale bar shows as the zoom changes, in either units: at zoom 2 on
      // the equator, 100 vp spans 1957 km, or 1216 mi.
      await jumpTo(0, 2);
      await untilFound('the scale bar shows', find(ON.text('1,000 ', MatchPattern.STARTS_WITH)));
      // The compass shows once the map turns.
      expect(await count(ON.type('Polygon'))).assertEqual(0);
      await jumpTo(0, 2, 90);
      await untilFound('the compass shows', find(ON.type('Polygon')));
    });

    it('draws a preset that the app includes in its block, beside its own content', 0, async () => {
      testMap.placedAt = { latitude: 0, longitude: 0 };
      await showOverlay('default');
      await untilFound('the logo shows', find(ON.type('Image')));
      await untilFound('the attribution shows', find(ATTRIBUTION_TEXT));
      await untilFound('the placed box shows', find(ON.id('placed-at')));
    });

    it('adds zoom buttons in the full preset', 0, async () => {
      await showOverlay('full');
      await untilFound('the attribution shows', find(ATTRIBUTION_TEXT));
      // The attribution's button and the two zoom buttons.
      expect(await count(ON.type('Button'))).assertEqual(3);
    });

    it('keeps only the logo and the attribution in the attribution-only preset', 0, async () => {
      await showOverlay('attributionOnly');
      await untilFound('the logo shows', find(ON.type('Image')));
      await untilFound('the attribution shows', find(ATTRIBUTION_TEXT));
      expect(await count(ON.type('Button'))).assertEqual(1);
      await jumpTo(0, 2, 90);
      await frames(30);
      expect(await count(ON.type('Polygon'))).assertEqual(0);
      expect(await Driver.create().findComponent(ON.text('1,000 ', MatchPattern.STARTS_WITH))).assertNull();
    });

    it('draws nothing for an empty block', 0, async () => {
      await showOverlay('none');
      await until('the attribution is known', () => map.attributions.length > 0);
      await jumpTo(0, 2, 90);
      await frames(30);
      expect(await count(ON.type('Image'))).assertEqual(0);
      expect(await count(ON.type('Button'))).assertEqual(0);
      expect(await count(ON.type('Polygon'))).assertEqual(0);
      expect(await Driver.create().findComponent(ATTRIBUTION_TEXT)).assertNull();
    });

    it('keeps the presets\' controls clear of the viewport insets', 0, async () => {
      // Each control sits 8 vp in from the part of the map that the insets
      // leave. The case compares edges with where they belong, rather than
      // with where they were, and waits for the layout to settle.
      testMap.overlay = 'full';
      testMap.viewportInsets = { top: 40, left: 30, bottom: 100, right: 60 };
      const map = await mapBounds();
      const edge = async (on: On, pick: (box: Bounds) => number, expected: number, what: string) => {
        let last = NaN;
        try {
          await eventually(what, async () => {
            const boxes = await Driver.create().findComponents(onPage(on)) ?? [];
            // UiTest takes one call at a time.
            last = NaN;
            for (const box of boxes) {
              const value = pick(await box.getBounds());
              if (!(Math.abs(last - expected) <= Math.abs(value - expected))) {
                last = value;
              }
            }
            return near(last, expected, 2) ? true : undefined;
          });
        } catch (error) {
          throw new Error(`${(error as Error).message}; the nearest was ${last} px, not ${expected} px`);
        }
      };
      // The zoom buttons' end edge, and the logo's start and bottom edges.
      await edge(ON.type('Button'), (box: Bounds) => box.right, map.right - vp2px(68),
        'the zoom buttons stay clear of the end inset');
      await edge(ON.type('Image'), (box: Bounds) => box.bottom, map.bottom - vp2px(108),
        'the logo stays clear of the bottom inset');
      await edge(ON.type('Image'), (box: Bounds) => box.left, map.left + vp2px(38),
        'the logo stays clear of the start inset');
    });

    it('keeps the expanded attribution beside the logo as the insets change', 0, async () => {
      // An attribution long enough to reach the logo.
      testMap.overlay = 'attributionOnly';
      testMap.style = attributedStyle(`${ATTRIBUTION} ${'and a long list of other sources '.repeat(8)}`);
      const text = await untilFound('the attribution shows', find(ATTRIBUTION_TEXT));
      const logo = await untilFound('the logo shows', find(ON.type('Image')));
      testMap.viewportInsets = { top: 0, left: 120, bottom: 0, right: 0 };
      const map = await mapBounds();
      await eventually('the logo moves in', async () =>
        near((await logo.getBounds()).left, map.left + vp2px(128), 2) ? true : undefined);
      await eventually('the attribution narrows beside the logo', async () =>
        (await text.getBounds()).left >= (await logo.getBounds()).right ? true : undefined);
    });

    it('labels the controls in the app\'s language, from the library\'s resources', 0, async () => {
      const manager = testMap.context!.getHostContext()!.resourceManager;
      expect(manager.getStringByNameSync('maplibre_compass').length > 0).assertTrue();
      expect(manager.getMediaByNameSync('maplibre_logo').length > 0).assertTrue();
      const inLocale = (locale: string, name: string): string => {
        const configuration = manager.getOverrideConfiguration();
        configuration.locale = locale;
        return manager.getOverrideResourceManager(configuration).getStringByNameSync(name);
      };
      expect(inLocale('en-US', 'maplibre_zoom_in')).assertEqual('Zoom in');
      expect(inLocale('zh-Hans-CN', 'maplibre_compass')).assertEqual('指南针');
      expect(inLocale('zh-Hans-CN', 'maplibre_zoom_out')).assertEqual('缩小');
      expect(inLocale('zh-Hant-TW', 'maplibre_compass')).assertEqual('指南針');
      expect(inLocale('zh-Hant-HK', 'maplibre_attribution')).assertEqual('地圖資訊出處');
      expect(inLocale('de-DE', 'maplibre_attribution')).assertEqual('Kartenattribution');
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

    it('grows the scale bar up to its maxWidth', 0, async () => {
      // 100 vp spans 122 km here, so 50 vp spans 61 km and 300 vp 367 km.
      await jumpTo(60, 5);
      testMap.scaleBarMaxWidth = 50;
      await expectScaleBar(ScaleBarUnits.metric, '50 km');
      testMap.scaleBarMaxWidth = 300;
      await expectScaleBar(ScaleBarUnits.metric, '200 km');
    });

    it('shows the disappearing scale bar as the zoom changes, until it stays', 0, async () => {
      // At zoom 1 on the equator, 100 vp spans 3914 km, and at zoom 2, 1957 km.
      // It shows as it finds the map's first zoom, and hides after 500 ms.
      testMap.disappearingScaleBarMs = 500;
      await untilGone('the scale bar hides', find(ON.text(' km', MatchPattern.ENDS_WITH)));

      const zoomed = Date.now();
      await jumpTo(0, 2);
      await untilFound('the scale bar shows', find(ON.text('1,000 km')));
      await untilGone('the scale bar hides', find(ON.text('1,000 km')));
      expect(Date.now() - zoomed).assertLarger(500);

      // A pan that keeps the zoom leaves it hidden.
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { center: { latitude: 10, longitude: 20 } } });
      await frames(30);
      expect(await Driver.create().findComponent(ON.text(' km', MatchPattern.ENDS_WITH))).assertNull();
    });

    it('shows the disappearing compass while the map turns, and a while after', 0, async () => {
      testMap.compass = true;
      await frames(30);
      expect(await count(ON.type('Polygon'))).assertEqual(0);
      await jumpTo(0, 1, 90);
      await untilFound('the compass shows', find(ON.type('Polygon')));

      // It stays for its visibilityDurationMs, 1000 by default, once the map
      // faces north again.
      const north = Date.now();
      await jumpTo(0, 1, 0);
      expect(await count(ON.type('Polygon'))).assertLarger(0);
      await untilGone('the compass hides', find(ON.type('Polygon')));
      expect(Date.now() - north).assertLarger(1000);
    });

    it('turns the map north when the compass is tapped', 0, async () => {
      testMap.compass = true;
      await jumpTo(0, 3, 90);
      // UiTest doesn't see accessibility text, so it finds the needle, the
      // page's only polygons.
      const needle = await untilFound('the compass shows', find(ON.type('Polygon')));
      await needle.click();
      await until('the camera rests facing north', () => {
        const bearing = map.camera?.bearing ?? 90;
        return near(bearing, 0, 0.001) || near(bearing, 360, 0.001);
      });
    });

    it('shows the compass button while the map faces north', 0, async () => {
      testMap.alwaysShownCompass = true;
      await untilFound('the compass shows', find(ON.type('Polygon')));
    });

    it('collects the attribution of the style sources', 0, async () => {
      testMap.attribution = true;
      testMap.style = attributedStyle();
      await until('the attribution shows', () => map.attributions.length > 0);
      expect(JSON.stringify(map.attributions)).assertEqual(JSON.stringify([ATTRIBUTION]));
      await untilFound('the text shows', find(ATTRIBUTION_TEXT));

      testMap.style = STYLE;
      await until('the attribution goes', () => map.attributions.length === 0 && map.styleLoaded);
      await untilGone('the attribution button goes', find(ON.type('Button')));
    });

    it('folds the attribution when its button is tapped', 0, async () => {
      testMap.attribution = true;
      testMap.style = attributedStyle();
      await untilFound('the attribution shows', find(ATTRIBUTION_TEXT));
      // The page's only button, without the zoom buttons, folds it.
      const button = await untilFound('the button shows', find(ON.type('Button')));
      await button.click();
      await untilGone('the attribution folds', find(ATTRIBUTION_TEXT));
      await button.click();
      await untilFound('the attribution unfolds', find(ATTRIBUTION_TEXT));
    });

    it('folds the attribution as the user starts a gesture', 0, async () => {
      testMap.attribution = true;
      testMap.style = attributedStyle();
      await untilFound('the attribution shows', find(ATTRIBUTION_TEXT));
      const starts = testMap.gestureStarts;
      const c = await mapCenter();
      const from = offset(c, 0, -60);
      const to = offset(c, 0, 60);
      await Driver.create().swipe(from.x, from.y, to.x, to.y, Math.round(vp2px(400)));
      await until('a gesture starts', () => testMap.gestureStarts > starts);
      await untilGone('the attribution folds', find(ATTRIBUTION_TEXT));
      // The button stays, to unfold it.
      expect(await count(ON.type('Button'))).assertEqual(1);
    });

    it('zooms in and out with the zoom buttons', 0, async () => {
      testMap.zoomButtons = true;
      await untilFound('the zoom buttons show', find(ON.type('Button')));
      // Zoom in is above zoom out, and the style has no attribution button.
      const buttons = await Driver.create().findComponents(ON.type('Button'));
      expect(buttons.length).assertEqual(2);
      await buttons[0].click();
      await until('the camera rests a level in', () => near(map.camera?.zoom ?? 0, 2, 0.001));
      await buttons[1].click();
      await until('the camera rests a level out', () => near(map.camera?.zoom ?? 0, 1, 0.001));
    });

    it('places content at a coordinate by its alignment', 0, async () => {
      const coordinate: LatLng = { latitude: 20, longitude: 30 };
      await map.updateCamera({
        mode: CameraUpdateMode.jump,
        camera: { center: { latitude: 15, longitude: 25 }, zoom: 4, bearing: 30, pitch: 20 },
      });
      await until('the frame shows the camera', () => near(map.frameCamera?.bearing ?? 0, 30, 0.001));
      // The controller projects with the frame's view, as FFI does.
      const expected: ScreenPoint = pixelFor(coordinate);
      const point = map.pixelForLatLng(coordinate)!;
      expectNear(point.x, expected.x, 0.001);
      expectNear(point.y, expected.y, 0.001);
      expectNear(map.latLngForPixel(point)?.latitude ?? NaN, coordinate.latitude, 1e-6);

      // By default, the box's center sits on the coordinate.
      testMap.placedAt = coordinate;
      await untilPlaced('placed-at', expected, CENTER);
      // Its top-left corner.
      testMap.placedAtAlignment = Alignment.TopStart;
      await untilPlaced('placed-at', expected, TOP_LEFT);
      // The middle of its end edge.
      testMap.placedAtAlignment = Alignment.End;
      await untilPlaced('placed-at', expected, END_MIDDLE);
    });

    it('places content at a coordinate from inside a padded parent', 0, async () => {
      const coordinate: LatLng = { latitude: 10, longitude: 20 };
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { center: coordinate, zoom: 4 } });
      await until('the frame shows the camera', () => near(map.frameCamera?.zoom ?? 0, 4, 0.001));
      testMap.placementPadding = 40;
      testMap.placedAt = coordinate;
      await untilPlaced('placed-at', pixelFor(coordinate), CENTER);
    });

    it('hides placed content while it is off the map', 0, async () => {
      await jumpTo(0, 4);
      testMap.placedAt = { latitude: 0, longitude: 10 };
      await until('the box shows', () => placedVisible('placed-at'));
      testMap.placedAt = { latitude: 0, longitude: 120 };
      await until('the box hides', () => !placedVisible('placed-at'));
    });

    it('places content towards an off-screen coordinate, on the oval', 0, async () => {
      await jumpTo(0, 4);
      const bounds = await mapBounds();
      const width = (bounds.right - bounds.left) / vp2px(1);
      const height = (bounds.bottom - bounds.top) / vp2px(1);
      // East of the map, level with its center: the box's end edge on the
      // middle of the map's end edge, pointing at 90 degrees.
      testMap.placedTowards = { latitude: 0, longitude: 120 };
      await untilPlaced('placed-towards', { x: width, y: height / 2 }, END_MIDDLE);
      expectNear(testMap.placedTowardsAngles[testMap.placedTowardsAngles.length - 1], 90, 0.5);
      // North of it, inside a padded parent: the box's top edge on the middle
      // of the parent's top edge.
      testMap.placementPadding = 40;
      testMap.placedTowards = { latitude: 80, longitude: 10 };
      await untilPlaced('placed-towards', { x: width / 2, y: 40 }, TOP_MIDDLE);
      const angle = testMap.placedTowardsAngles[testMap.placedTowardsAngles.length - 1];
      expect(near(angle, 0, 0.5) || near(angle, 360, 0.5)).assertTrue();
      // It hides once the coordinate is on the map.
      testMap.placedTowards = { latitude: 0, longitude: 12 };
      await until('the box hides', () => !placedVisible('placed-towards'));
    });

    it('taps a pointer pin that points off the map', 0, async () => {
      await jumpTo(0, 4);
      testMap.pointerPin = { latitude: 0, longitude: 120 };
      // The pin settles once it knows its angle, so the case taps where it
      // stays.
      let last: Bounds | undefined = undefined;
      const box = await eventually('the pin settles', async () => {
        const now = await bounds('pin-content');
        const settled = now !== undefined && last !== undefined && JSON.stringify(now) === JSON.stringify(last);
        last = now;
        return settled ? now : undefined;
      });
      const at = CENTER(box!);
      await Driver.create().click(Math.round(at.x), Math.round(at.y));
      await until('the tap reaches the app', () => testMap.pointerPinTaps === 1);
    });
  });
}
