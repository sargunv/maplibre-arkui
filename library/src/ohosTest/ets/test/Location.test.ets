// The user's location: the indicator that the map draws, and a camera that
// follows it until a gesture. The locations are made up, as an app's test or
// its simulated walk makes them; the emulator's Location Kit has no fixes.

import { describe, expect, it } from '@ohos/hypium';
import {
  CameraPosition,
  CameraUpdateMode,
  MapHandle,
  MapController,
  readPixelMap,
  USER_LOCATION_LAYER,
} from '@maplibre/arkui';

import application from '@ohos.app.ability.application';
import geoLocationManager from '@ohos.geoLocationManager';
import image from '@ohos.multimedia.image';
import { Driver, ON, Point, Rect as Bounds } from '@ohos.UiTest';

import { STYLE, testMap } from '../testability/TestMaps';
import { eventually, nextFrame, until } from './until';

// A location as Location Kit reports one.
function fix(latitude: number, longitude: number, accuracy: number = 0, speed: number = 0,
  direction: number = 0): geoLocationManager.Location {
  return {
    latitude: latitude,
    longitude: longitude,
    altitude: 0,
    accuracy: accuracy,
    speed: speed,
    direction: direction,
    timeStamp: Date.now(),
    timeSinceBoot: 0,
  };
}

function camera(): CameraPosition {
  const current = testMap.controller.getCamera();
  if (current === undefined) {
    throw new Error('The controller has no camera');
  }
  return current;
}

function requireMap(): MapHandle {
  const map = testMap.controller.map;
  if (map === undefined) {
    throw new Error('No map shows the controller');
  }
  return map;
}

function near(actual: number, expected: number, tolerance: number): boolean {
  return Math.abs(actual - expected) <= tolerance;
}

// Whether the camera is at rest with its center at `latitude`, `longitude`.
function restsAt(latitude: number, longitude: number): boolean {
  const snapshot = testMap.controller.map?.getSnapshot();
  return snapshot !== undefined && !snapshot.transitionInProgress &&
    near(snapshot.view.camera.center.latitude, latitude, 0.0001) &&
    near(snapshot.view.camera.center.longitude, longitude, 0.0001);
}

// The location that the indicator layer draws, as latitude and longitude, or
// undefined without the layer.
async function drawnLocation(map: MapHandle): Promise<number[] | undefined> {
  if (await map.getStyleLayer(USER_LOCATION_LAYER) === undefined) {
    return undefined;
  }
  const value = await map.getStyleLayerProperty(USER_LOCATION_LAYER, 'location') as number[];
  return [value[0], value[1]];
}

// Waits until the indicator draws at `latitude`, `longitude`.
async function drawnAt(latitude: number, longitude: number): Promise<void> {
  const map = requireMap();
  await eventually(`the indicator draws at ${latitude}, ${longitude}`, async () => {
    const drawn = await drawnLocation(map);
    return drawn !== undefined && near(drawn[0], latitude, 1e-9) && near(drawn[1], longitude, 1e-9) ?
      true : undefined;
  });
}

// Shows the map alone on the page, without a location, and puts the camera at
// a known place, with its center at the map's.
async function reset(): Promise<void> {
  const map: MapController = testMap.controller;
  map.stopFollowingUserLocation();
  testMap.userLocation = undefined;
  if (testMap.inScroll) {
    const loads = testMap.styleLoads;
    testMap.inScroll = false;
    await until('the map moves', () => testMap.styleLoads > loads);
  }
  await until('the style loads', () => map.styleLoaded);
  await map.updateCamera({
    mode: CameraUpdateMode.jump,
    camera: {
      center: { latitude: 0, longitude: 0 },
      zoom: 10,
      bearing: 0,
      pitch: 0,
      padding: { top: 0, left: 0, bottom: 0, right: 0 },
    },
  });
}

// The pixel of the display at `point` in px, as red, green, and blue.
async function pixelAt(point: Point): Promise<number[]> {
  const path = `${application.getApplicationContext().cacheDir}/location.png`;
  expect(await Driver.create().screenCap(path)).assertTrue();
  const source = image.createImageSource(path);
  const pixelMap = await source.createPixelMap();
  try {
    const pixels = readPixelMap(pixelMap);
    const offset = point.y * pixels.stride + point.x * 4;
    return [pixels.pixels[offset], pixels.pixels[offset + 1], pixels.pixels[offset + 2]];
  } finally {
    pixelMap.release();
    source.release();
  }
}

function vp2px(vp: number): number {
  return testMap.context?.vp2px(vp) ?? vp;
}

// The map's center on the display, in px.
async function mapCenter(): Promise<Point> {
  const map = await Driver.create().findComponent(ON.type('XComponent'));
  const bounds: Bounds = await map.getBounds();
  return { x: Math.round((bounds.left + bounds.right) / 2), y: Math.round((bounds.top + bounds.bottom) / 2) };
}

async function accuracyRadius(): Promise<number> {
  return await requireMap().getStyleLayerProperty(USER_LOCATION_LAYER, 'accuracy-radius') as number;
}

export default function locationTest(): void {
  describe('Location', () => {
    it('draws the indicator at the location, and removes it', 0, async () => {
      await reset();
      testMap.userLocation = fix(0, 0);
      await drawnAt(0, 0);
      expect(await accuracyRadius()).assertEqual(0);

      // On screen: a blue dot in a white ring, at the camera's center, which
      // the test style's background doesn't have, once a frame draws it.
      const c = await mapCenter();
      const ring = await eventually('the ring draws', async () => {
        const pixel = await pixelAt({ x: c.x + Math.round(vp2px(8.5)), y: c.y });
        // Near white, though the image's edges blend with the dot's.
        return pixel.every((channel: number) => channel > 180) ? pixel : undefined;
      });
      expect(ring.length).assertEqual(3);
      const dot = await pixelAt(c);
      // #1e88e5, not the background's #4a90d9.
      expect(Math.abs(dot[0] - 0x1e)).assertLessOrEqual(16);
      expect(Math.abs(dot[2] - 0xe5)).assertLessOrEqual(16);
      const away = await pixelAt({ x: c.x + Math.round(vp2px(40)), y: c.y });
      expect(away[0]).assertLess(150);

      testMap.userLocation = fix(1, 2, 25);
      await drawnAt(1, 2);
      expect(await accuracyRadius()).assertEqual(25);
      testMap.userLocation = undefined;
      await eventually('the indicator goes', async () =>
        await requireMap().getStyleLayer(USER_LOCATION_LAYER) === undefined ? true : undefined);
    });

    it('draws the indicator again in a new style', 0, async () => {
      await reset();
      testMap.userLocation = fix(3, 4);
      await drawnAt(3, 4);
      const loads = testMap.styleLoads;
      testMap.style = STYLE.replace('#4a90d9', '#ffffff');
      try {
        await until('the new style loads', () => testMap.styleLoads > loads && testMap.controller.styleLoaded);
        await drawnAt(3, 4);
      } finally {
        testMap.style = STYLE;
      }
      await until('the test style loads', () => testMap.controller.styleLoaded);
    });

    it('moves the camera with each location while it follows', 0, async () => {
      await reset();
      const map = testMap.controller;
      map.followUserLocation({ zoom: 8 });
      expect(map.followingUserLocation).assertTrue();
      // Without a location, the camera stays.
      expect(camera().zoom).assertClose(10, 0.001);

      testMap.userLocation = fix(5, 6);
      await until('the camera reaches the location', () => restsAt(5, 6));
      expect(camera().zoom).assertClose(8, 0.001);
      testMap.userLocation = fix(5.5, 6.5);
      await until('the camera reaches the next location', () => restsAt(5.5, 6.5));
      // The zoom applied only as the camera started to follow.
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 9 } });
      testMap.userLocation = fix(5.6, 6.6);
      await until('the camera reaches a third location', () => restsAt(5.6, 6.6));
      expect(camera().zoom).assertClose(9, 0.001);
      expect(Math.abs(camera().bearing)).assertLessOrEqual(0.001);

      // With the course, the map turns while the location moves.
      map.followUserLocation({ course: true });
      testMap.userLocation = fix(5.7, 6.7, 10, 3, 90);
      await until('the camera turns to the course', () =>
        restsAt(5.7, 6.7) && near(camera().bearing, 90, 0.001));
      // At rest, the direction isn't a course, so the bearing stays.
      testMap.userLocation = fix(5.8, 6.8, 10, 0, 180);
      await until('the camera reaches the resting location', () => restsAt(5.8, 6.8));
      expect(camera().bearing).assertClose(90, 0.001);
      map.stopFollowingUserLocation();
    });

    it('stops following as a gesture starts, until the app resumes', 0, async () => {
      await reset();
      const map = testMap.controller;
      map.followUserLocation();
      testMap.userLocation = fix(0.01, 0.01);
      await until('the camera follows', () => restsAt(0.01, 0.01));

      const c = await mapCenter();
      const starts = testMap.gestureStarts;
      await Driver.create().swipe(c.x + Math.round(vp2px(100)), c.y, c.x - Math.round(vp2px(100)), c.y,
        Math.round(vp2px(200)));
      await until('a gesture starts', () => testMap.gestureStarts > starts);
      expect(map.followingUserLocation).assertFalse();
      await until('the gesture ends', () => testMap.gestureEnds === testMap.gestureStarts &&
        !(map.map?.getSnapshot().transitionInProgress ?? true));
      const panned = camera().center;
      expect(panned.longitude).assertLarger(0.05);

      // A new location moves the indicator but not the camera.
      testMap.userLocation = fix(0.02, 0.02);
      await drawnAt(0.02, 0.02);
      for (let frame = 0; frame < 30; frame++) {
        await nextFrame();
      }
      expect(map.map?.getSnapshot().transitionInProgress).assertFalse();
      expect(camera().center.longitude).assertClose(panned.longitude, 1e-9);

      map.followUserLocation();
      await until('the camera follows again', () => restsAt(0.02, 0.02));
      map.stopFollowingUserLocation();
      testMap.userLocation = undefined;
    });
  });
}
