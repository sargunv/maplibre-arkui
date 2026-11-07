// The user's location: the indicator that the map draws, and a camera that
// follows it through the user's input until the app stops it. The locations and headings are made up, as an
// app's test or its simulated walk makes them; the emulator's Location Kit has
// no fixes, and it has no compass.

import { beforeEach, describe, expect, it } from '@ohos/hypium';
import { FollowBearing, LatLng, StyleLayerInfo } from '@maplibre/arkui';
import { MapHandle } from '@maplibre/native-ffi';
import {
  BORDER_RADIUS,
  DOT_COLOR,
  DOT_RADIUS,
  USER_LOCATION_LAYER,
} from '@maplibre/arkui/src/main/ets/location';

import geoLocationManager from '@ohos.geoLocationManager';
import { Driver, Point } from '@ohos.UiTest';

import { backgroundStyle, showsMap, testMap } from '../testability/TestMaps';
import {
  camera,
  eventually,
  expectNear,
  frames,
  gesture,
  mapCenter,
  mapSnapshot,
  near,
  offset,
  rgb,
  screenPixel,
  setStyle,
  speed,
  twist,
  twoFingers,
  until,
  withMap,
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
  const snapshot = testMap.controller.withFfiMap((map: MapHandle) => map.getSnapshot());
  return snapshot !== undefined && !snapshot.transitionInProgress &&
    near(snapshot.view.camera.center.latitude, latitude, 0.0001) &&
    near(snapshot.view.camera.center.longitude, longitude, 0.0001);
}

// The location that the indicator layer draws, as latitude and longitude, or
// undefined without the layer.
async function drawnLocation(): Promise<number[] | undefined> {
  if (await withMap((ffi: MapHandle) => ffi.getStyleLayer(USER_LOCATION_LAYER)) === undefined) {
    return undefined;
  }
  const value = await withMap((ffi: MapHandle) => ffi.getStyleLayerProperty(USER_LOCATION_LAYER, 'location')) as
    number[];
  return [value[0], value[1]];
}

// Waits until the indicator draws at `latitude`, `longitude`.
async function drawnAt(latitude: number, longitude: number): Promise<void> {
  await eventually(`the indicator draws at ${latitude}, ${longitude}`, async () => {
    const drawn = await drawnLocation();
    return drawn !== undefined && near(drawn[0], latitude, 1e-9) && near(drawn[1], longitude, 1e-9) ?
      true : undefined;
  });
}

// A property of the indicator layer, as JSON.
async function property(name: string): Promise<string> {
  return JSON.stringify(await withMap((ffi: MapHandle) => ffi.getStyleLayerProperty(USER_LOCATION_LAYER, name)));
}

// The name of an image property of the indicator layer, which the style
// normalizes to an object with the name.
async function imageName(name: string): Promise<string> {
  const value = await withMap((ffi: MapHandle) => ffi.getStyleLayerProperty(USER_LOCATION_LAYER, name)) as
    Record<string, Object>;
  return value['name'] as string;
}

async function accuracyRadius(): Promise<number> {
  return await withMap((ffi: MapHandle) => ffi.getStyleLayerProperty(USER_LOCATION_LAYER, 'accuracy-radius')) as number;
}

async function arrowBearing(): Promise<number> {
  return await withMap((ffi: MapHandle) => ffi.getStyleLayerProperty(USER_LOCATION_LAYER, 'bearing')) as number;
}

// Where the camera's center is as the next gesture ends, before the camera
// catches up with the location.
function centerAtEnd(): LatLng[] {
  const centers: LatLng[] = [];
  testMap.onGestureEnd = () => {
    const center = mapSnapshot().view.camera.center;
    centers.push({ latitude: center.latitude, longitude: center.longitude });
  };
  return centers;
}

function expectAt(centers: LatLng[], latitude: number, longitude: number): void {
  expect(centers.length).assertEqual(1);
  expectNear(centers[0].latitude, latitude, 1e-6);
  expectNear(centers[0].longitude, longitude, 1e-6);
}

function wrap(degrees: number): number {
  return (((degrees + 180) % 360) + 360) % 360 - 180;
}

// How far the middle of the arrow is from the dot's center, in vp.
const ARROW_DISTANCE = 13;

// Whether the indicator's blue is on screen `dx`, `dy` vp from the map's
// center, over the white background of the case's style.
async function blueAt(dx: number, dy: number): Promise<boolean> {
  const pixel = await screenPixel(offset(await mapCenter(), dx, dy));
  const blue = rgb(DOT_COLOR);
  return pixel.every((channel: number, index: number) => near(channel, blue[index], 16));
}

export default function locationTest(): void {
  describe('Location', () => {
    // The map's center is at the camera's.
    beforeEach(async () => {
      await testMap.reset();
      await testMap.controller.updateCamera({ zoom: 10 });
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
        await withMap((ffi: MapHandle) => ffi.getStyleLayer(USER_LOCATION_LAYER)) === undefined ? true : undefined);
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
      await map.updateCamera({ zoom: 9 });
      testMap.userLocation = fix(5.6, 6.6);
      await until('the camera reaches a third location', () => restsAt(5.6, 6.6));
      expectNear(camera().zoom, 9, 0.001);
      expect(Math.abs(camera().bearing)).assertLessOrEqual(0.001);

      // With the course, the map turns while the location moves.
      map.followUserLocation({ bearing: FollowBearing.course });
      testMap.userLocation = fix(5.7, 6.7, 10, 3, 90);
      await until('the camera turns to the course', () =>
        restsAt(5.7, 6.7) && near(camera().bearing, 90, 0.001));
      // At rest, the direction isn't a course, so the bearing stays.
      testMap.userLocation = fix(5.8, 6.8, 10, 0, 180);
      await until('the camera reaches the resting location', () => restsAt(5.8, 6.8));
      expectNear(camera().bearing, 90, 0.001);
      // The hidden arrow keeps its course, so the next one eases from it.
      expect(await arrowBearing()).assertEqual(90);
    });

    it('points the arrow to the heading, or to the course while it moves', 0, async () => {
      await setStyle(backgroundStyle('#ffffff'));
      // At rest without a heading, there's no arrow.
      testMap.userLocation = fix(0, 0);
      await eventually('the dot draws', async () => await blueAt(0, 0) ? true : undefined);
      expect(await blueAt(0, -ARROW_DISTANCE)).assertFalse();

      // On screen, a heading to the east turns the arrow there, with north up.
      testMap.userHeading = 90;
      await eventually('the arrow points east', async () => await blueAt(ARROW_DISTANCE, 0) ? true : undefined);
      expect(await blueAt(0, -ARROW_DISTANCE)).assertFalse();
      expect(await blueAt(-ARROW_DISTANCE, 0)).assertFalse();

      // The heading wins over the course of a moving location.
      testMap.userLocation = fix(0.001, 0, 0, 3, 180);
      await drawnAt(0.001, 0);
      expect(await arrowBearing()).assertEqual(90);
      // Without a heading, the arrow shows the course.
      testMap.userHeading = undefined;
      await eventually('the arrow turns to the course', async () =>
        await arrowBearing() === 180 ? true : undefined);

      // At rest again without a heading, the arrow goes.
      testMap.userHeading = undefined;
      testMap.userLocation = fix(0, 0);
      await drawnAt(0, 0);
      await eventually('the arrow goes', async () => !(await blueAt(0, -ARROW_DISTANCE)) &&
        !(await blueAt(ARROW_DISTANCE, 0)) ? true : undefined);
    });

    it('turns the camera with each heading while it follows the heading', 0, async () => {
      const map = testMap.controller;
      map.followUserLocation({ bearing: FollowBearing.heading });
      // The course of a moving location doesn't turn it.
      testMap.userLocation = fix(5, 6, 10, 3, 90);
      testMap.userHeading = 30;
      await until('the camera turns to the heading', () => restsAt(5, 6) && near(camera().bearing, 30, 0.001));
      // A new heading turns the camera without a new location.
      testMap.userHeading = 60;
      await until('the camera turns to the next heading', () => restsAt(5, 6) && near(camera().bearing, 60, 0.001));
      // Without a heading, the camera keeps its bearing.
      testMap.userHeading = undefined;
      testMap.userLocation = fix(5.1, 6.1, 10, 3, 90);
      await until('the camera reaches the location', () => restsAt(5.1, 6.1));
      expectNear(camera().bearing, 60, 0.001);

      // While it follows without the heading, a new heading leaves a camera
      // change that the app makes.
      map.followUserLocation({ bearing: FollowBearing.course });
      await until('the camera turns to the course', () => restsAt(5.1, 6.1) && near(camera().bearing, 90, 0.001));
      await map.updateCamera({ center: { latitude: 5.2, longitude: 6.2 } });
      testMap.userHeading = 120;
      await eventually('the arrow turns to the heading', async () =>
        await arrowBearing() === 120 ? true : undefined);
      await frames(30);
      expect(restsAt(5.2, 6.2)).assertTrue();
    });

    it('follows from the start a map that appears after the app asks', 0, async () => {
      const map = testMap.controller;
      testMap.shown = false;
      await until('the map leaves', () => !showsMap(map));
      map.followUserLocation({ zoom: 8 });
      expect(map.followingUserLocation).assertTrue();
      testMap.userLocation = fix(7, 8);

      testMap.shown = true;
      await until('the camera reaches the location', () => restsAt(7, 8));
      expectNear(camera().zoom, 8, 0.001);
      expect(map.followingUserLocation).assertTrue();
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

    it('stops following where pan\'s onStart stops it, until the app resumes', 0, async () => {
      const map = testMap.controller;
      let pans = 0;
      testMap.interactions = {
        pan: {
          onStart: () => {
            pans++;
            map.stopFollowingUserLocation();
          },
        },
      };
      map.followUserLocation();
      testMap.userLocation = fix(0.01, 0.01);
      await until('the camera follows', () => restsAt(0.01, 0.01));

      const c = await mapCenter();
      const from = offset(c, 100, 0);
      const to = offset(c, -100, 0);
      await gesture(() => Driver.create().swipe(from.x, from.y, to.x, to.y, speed(200)));
      expect(pans).assertEqual(1);
      expect(map.followingUserLocation).assertFalse();
      const panned = camera().center;
      expect(panned.longitude).assertLarger(0.05);

      // A new location moves the indicator but not the camera.
      testMap.userLocation = fix(0.02, 0.02);
      await drawnAt(0.02, 0.02);
      await frames(30);
      expect(mapSnapshot().transitionInProgress).assertFalse();
      expectNear(camera().center.longitude, panned.longitude, 1e-9);

      map.followUserLocation();
      await until('the camera follows again', () => restsAt(0.02, 0.02));
    });

    it('keeps following through a pinch, about the location, and catches up after it', 0, async () => {
      const map = testMap.controller;
      map.followUserLocation();
      testMap.userLocation = fix(0.01, 0.01);
      await until('the camera follows', () => restsAt(0.01, 0.01));
      // A location that comes during the pinch waits for it.
      testMap.onGestureStart = () => {
        testMap.userLocation = fix(0.011, 0.011);
      };
      const ended = centerAtEnd();

      // Off the center, and drifting, which would zoom about the fingers and
      // pan.
      const c = await mapCenter();
      const from: Point[] = [offset(c, 20, 100), offset(c, 120, 100)];
      const to: Point[] = [offset(c, -60, 130), offset(c, 200, 130)];
      await gesture(async () => {
        await Driver.create().injectMultiPointerAction(twoFingers(from, to, 20), speed(400));
      });
      expect(map.followingUserLocation).assertTrue();
      expect(camera().zoom).assertLarger(10.8);
      expectAt(ended, 0.01, 0.01);
      await until('the camera reaches the location that came during the pinch', () => restsAt(0.011, 0.011));
      expect(map.followingUserLocation).assertTrue();
    });

    it('keeps following through a twist, about the location, with its bearing', 0, async () => {
      const map = testMap.controller;
      map.followUserLocation();
      testMap.userLocation = fix(0.01, 0.01);
      await until('the camera follows', () => restsAt(0.01, 0.01));

      const ended = centerAtEnd();
      const c = offset(await mapCenter(), 60, 120);
      await gesture(async () => {
        await Driver.create().injectMultiPointerAction(twist(c, 100, 60, 20), speed(300));
      });
      expect(map.followingUserLocation).assertTrue();
      expectAt(ended, 0.01, 0.01);
      await until('the camera rests at the location', () => restsAt(0.01, 0.01));
      const bearing = camera().bearing;
      expect(Math.abs(wrap(bearing))).assertLarger(40);

      // The next location keeps the user's bearing.
      testMap.userLocation = fix(0.012, 0.012);
      await until('the camera follows the next location', () => restsAt(0.012, 0.012));
      expectNear(camera().bearing, bearing, 0.001);
    });

    it('turns back to the course after a twist, unless rotate\'s onStart follows without it', 0, async () => {
      const map = testMap.controller;
      map.followUserLocation({ bearing: FollowBearing.course });
      testMap.userLocation = fix(0.01, 0.01, 10, 3, 90);
      await until('the camera turns to the course', () => restsAt(0.01, 0.01) && near(camera().bearing, 90, 0.001));

      const c = await mapCenter();
      await gesture(async () => {
        await Driver.create().injectMultiPointerAction(twist(c, 100, 60, 20), speed(300));
      });
      await until('the camera turns back to the course', () =>
        restsAt(0.01, 0.01) && near(camera().bearing, 90, 0.001));

      testMap.interactions = { rotate: { onStart: () => map.followUserLocation() } };
      await gesture(async () => {
        await Driver.create().injectMultiPointerAction(twist(c, 100, 60, 20), speed(300));
      });
      expect(map.followingUserLocation).assertTrue();
      await until('the camera rests at the location', () => restsAt(0.01, 0.01));
      const bearing = camera().bearing;
      expect(Math.abs(wrap(bearing - 90))).assertLarger(40);
      testMap.userLocation = fix(0.012, 0.012, 10, 3, 90);
      await until('the camera follows the next location', () => restsAt(0.012, 0.012));
      expectNear(camera().bearing, bearing, 0.001);
    });

    it('draws the indicator with the options\' colors, images, and layer', 0, async () => {
      // A layer of content for the indicator to go under.
      const top: Record<string, Object> = { 'background-color': '#00ff00', 'background-opacity': 0 };
      testMap.content = { layers: [{ id: 'top', type: 'background', paint: top }] };
      testMap.userLocationIndicator = {
        color: '#ff0000',
        accuracyColor: '#00ff00',
        accuracyBorderColor: 'rgba(0, 0, 255, 0.5)',
        bearingImage: 'custom-arrow',
        shadowImage: '',
        below: 'top',
      };
      testMap.userLocation = fix(0, 0, 25, 3, 45);
      await drawnAt(0, 0);
      // The style's normalized forms, as JSON.
      expect(await property('accuracy-radius-color')).assertEqual('["rgba",0,255,0,1]');
      expect(await property('accuracy-radius-border-color')).assertEqual('["rgba",0,0,255,0.5]');
      expect(await imageName('top-image')).assertEqual('maplibre-arkui-user-location-dot');
      expect(await imageName('bearing-image')).assertEqual('custom-arrow');
      expect(await imageName('shadow-image')).assertEqual('');
      const ids = (await withMap((ffi: MapHandle) => ffi.listStyleLayers())).map((layer: StyleLayerInfo) => layer.id);
      expect(ids.indexOf(USER_LOCATION_LAYER)).assertEqual(ids.indexOf('top') - 1);

      // On screen, the default dot in the options' color.
      const c = await mapCenter();
      const dot = await eventually('the red dot draws', async () => {
        const pixel = await screenPixel(c);
        return pixel[0] > 200 && pixel[1] < 60 && pixel[2] < 60 ? pixel : undefined;
      });
      expect(dot.length).assertEqual(3);

      // Without the options, the indicator is the default again, at the top.
      testMap.userLocationIndicator = {};
      await eventually('the default accuracy color', async () =>
        await withMap((ffi: MapHandle) => ffi.getStyleLayer(USER_LOCATION_LAYER)) !== undefined &&
          await property('accuracy-radius-color') !== '["rgba",0,255,0,1]' ? true : undefined);
      expect(await imageName('shadow-image')).assertEqual('maplibre-arkui-user-location-shadow');
      const after = (await withMap((ffi: MapHandle) => ffi.listStyleLayers())).map((layer: StyleLayerInfo) => layer.id);
      expect(after[after.length - 1]).assertEqual(USER_LOCATION_LAYER);
    });

    it('goes above every layer when the style and content lack the one to go under', 0, async () => {
      // A layer that only the app added doesn't count.
      const clear: Record<string, Object> = { 'background-opacity': 0 };
      const added: Record<string, Object> = { 'id': 'added', 'type': 'background', 'paint': clear };
      await withMap((ffi: MapHandle) => ffi.addStyleLayerJson(added));
      testMap.userLocationIndicator = { below: 'added' };
      testMap.userLocation = fix(0, 0);
      await drawnAt(0, 0);
      const ids = (await withMap((ffi: MapHandle) => ffi.listStyleLayers())).map((layer: StyleLayerInfo) => layer.id);
      expect(ids[ids.length - 1]).assertEqual(USER_LOCATION_LAYER);
      expect(testMap.errors.length).assertEqual(0);
    });
  });
}
