// The user's location: the indicator that the map draws, and a camera that
// follows it until a gesture. The locations are made up, as an app's test or
// its simulated walk makes them; the emulator's Location Kit has no fixes.

import { beforeEach, describe, expect, it } from '@ohos/hypium';
import { CameraUpdateMode, MapHandle, readPixelMap } from '@maplibre/arkui';
import {
  BORDER_RADIUS,
  DOT_COLOR,
  DOT_RADIUS,
  USER_LOCATION_LAYER,
} from '@maplibre/arkui/src/main/ets/location';

import application from '@ohos.app.ability.application';
import fs from '@ohos.file.fs';
import geoLocationManager from '@ohos.geoLocationManager';
import image from '@ohos.multimedia.image';
import { Driver, Point } from '@ohos.UiTest';

import { backgroundStyle, testMap } from '../testability/TestMaps';
import {
  camera,
  eventually,
  expectNear,
  frames,
  mapCenter,
  near,
  offset,
  requireMap,
  setStyle,
  until,
  vp2px,
} from './helpers';

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

// The pixel of the display at `point` in px, as red, green, and blue.
async function screenPixel(point: Point): Promise<number[]> {
  const path = `${application.getApplicationContext().cacheDir}/location-${Date.now()}.png`;
  expect(await Driver.create().screenCap(path)).assertTrue();
  const source = image.createImageSource(path);
  const pixelMap = await source.createPixelMap();
  try {
    const pixels = readPixelMap(pixelMap);
    const i = point.y * pixels.stride + point.x * 4;
    return [pixels.pixels[i], pixels.pixels[i + 1], pixels.pixels[i + 2]];
  } finally {
    pixelMap.release();
    source.release();
    fs.unlinkSync(path);
  }
}

// A color written #rrggbb, as red, green, and blue.
function rgb(color: string): number[] {
  return [1, 3, 5].map((start: number) => parseInt(color.slice(start, start + 2), 16));
}

async function accuracyRadius(): Promise<number> {
  return await requireMap().getStyleLayerProperty(USER_LOCATION_LAYER, 'accuracy-radius') as number;
}

export default function locationTest(): void {
  describe('Location', () => {
    // The map's center is at the camera's.
    beforeEach(async () => {
      await testMap.reset();
      await testMap.controller.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 10 } });
    });

    it('draws the indicator at the location, and removes it', 0, async () => {
      testMap.userLocation = fix(0, 0);
      await drawnAt(0, 0);
      expect(await accuracyRadius()).assertEqual(0);

      // On screen: a blue dot in a white ring, at the camera's center, which
      // the test style's background doesn't have, once a frame draws it.
      const c = await mapCenter();
      const ring = await eventually('the ring draws', async () => {
        const pixel = await screenPixel(offset(c, (DOT_RADIUS + BORDER_RADIUS) / 2, 0));
        // Near white, though the image's edges blend with the dot's.
        return pixel.every((channel: number) => channel > 180) ? pixel : undefined;
      });
      expect(ring.length).assertEqual(3);
      // The dot's blue, which isn't the background's.
      const dot = await screenPixel(c);
      const blue = rgb(DOT_COLOR);
      expectNear(dot[0], blue[0], 16);
      expectNear(dot[2], blue[2], 16);
      const away = await screenPixel(offset(c, 4 * BORDER_RADIUS, 0));
      expect(away[0]).assertLess(150);

      testMap.userLocation = fix(1, 2, 25);
      await drawnAt(1, 2);
      expect(await accuracyRadius()).assertEqual(25);
      testMap.userLocation = undefined;
      await eventually('the indicator goes', async () =>
        await requireMap().getStyleLayer(USER_LOCATION_LAYER) === undefined ? true : undefined);
    });

    it('draws the indicator again in a new style', 0, async () => {
      testMap.userLocation = fix(3, 4);
      await drawnAt(3, 4);
      await setStyle(backgroundStyle('#ffffff'));
      await drawnAt(3, 4);
    });

    it('moves the camera with each location while it follows', 0, async () => {
      const map = testMap.controller;
      map.followUserLocation({ zoom: 8 });
      expect(map.followingUserLocation).assertTrue();
      // Without a location, the camera stays.
      expectNear(camera().zoom, 10, 0.001);

      testMap.userLocation = fix(5, 6);
      await until('the camera reaches the location', () => restsAt(5, 6));
      expectNear(camera().zoom, 8, 0.001);
      testMap.userLocation = fix(5.5, 6.5);
      await until('the camera reaches the next location', () => restsAt(5.5, 6.5));
      // The zoom applied only as the camera started to follow.
      await map.updateCamera({ mode: CameraUpdateMode.jump, camera: { zoom: 9 } });
      testMap.userLocation = fix(5.6, 6.6);
      await until('the camera reaches a third location', () => restsAt(5.6, 6.6));
      expectNear(camera().zoom, 9, 0.001);
      expect(Math.abs(camera().bearing)).assertLessOrEqual(0.001);

      // With the course, the map turns while the location moves.
      map.followUserLocation({ course: true });
      testMap.userLocation = fix(5.7, 6.7, 10, 3, 90);
      await until('the camera turns to the course', () =>
        restsAt(5.7, 6.7) && near(camera().bearing, 90, 0.001));
      // At rest, the direction isn't a course, so the bearing stays.
      testMap.userLocation = fix(5.8, 6.8, 10, 0, 180);
      await until('the camera reaches the resting location', () => restsAt(5.8, 6.8));
      expectNear(camera().bearing, 90, 0.001);
      // The hidden arrow keeps its course, so the next one eases from it.
      expect(await requireMap().getStyleLayerProperty(USER_LOCATION_LAYER, 'bearing') as number).assertEqual(90);
    });

    it('reaches the zoom it follows with while locations come quickly', 0, async () => {
      const map = testMap.controller;
      map.followUserLocation({ zoom: 14 });
      // A location every few frames replaces each move, which takes a
      // second, before it ends.
      for (let i = 0; i < 8; i++) {
        testMap.userLocation = fix(1 + i * 0.001, 1);
        await frames(9);
      }
      await until('the camera reaches the last location', () => restsAt(1.007, 1));
      expectNear(camera().zoom, 14, 0.001);
    });

    it('stops following as a gesture starts, until the app resumes', 0, async () => {
      const map = testMap.controller;
      map.followUserLocation();
      testMap.userLocation = fix(0.01, 0.01);
      await until('the camera follows', () => restsAt(0.01, 0.01));

      const c = await mapCenter();
      const from = offset(c, 100, 0);
      const to = offset(c, -100, 0);
      const starts = testMap.gestureStarts;
      await Driver.create().swipe(from.x, from.y, to.x, to.y, Math.round(vp2px(200)));
      await until('a gesture starts', () => testMap.gestureStarts > starts);
      expect(map.followingUserLocation).assertFalse();
      await until('the gesture ends', () => testMap.gestureEnds === testMap.gestureStarts &&
        !(map.map?.getSnapshot().transitionInProgress ?? true));
      const panned = camera().center;
      expect(panned.longitude).assertLarger(0.05);

      // A new location moves the indicator but not the camera.
      testMap.userLocation = fix(0.02, 0.02);
      await drawnAt(0.02, 0.02);
      await frames(30);
      expect(map.map?.getSnapshot().transitionInProgress).assertFalse();
      expectNear(camera().center.longitude, panned.longitude, 1e-9);

      map.followUserLocation();
      await until('the camera follows again', () => restsAt(0.02, 0.02));
    });
  });
}
