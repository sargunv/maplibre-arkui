// What the suites share: waits, the test map's camera and FFI map, absolute
// comparisons, and where the map is on the display.

import { expect } from '@ohos/hypium';
import { CameraPosition, LatLng, ScreenPoint } from '@maplibre/arkui';
import { readPixelMap } from '@maplibre/arkui/src/main/ets/content/internal/PixelMaps';
import { Camera as FfiCamera, MapHandle, MapProjectionHandle, MapSnapshot } from '@maplibre/native-ffi';
import image from '@ohos.multimedia.image';
import { Driver, ON, Point, PointerMatrix, Rect as Bounds } from '@ohos.UiTest';

import { testMap, until } from '../testability/TestMaps';

export { eventually, frames, nextFrame, until, WAIT_MS } from '../testability/TestMaps';

// Lends the test map's FFI map to `block`, and fails while no map shows the
// controller.
export function withMap<T>(block: (map: MapHandle) => T): T {
  let lent = false;
  let result: T | undefined = undefined;
  testMap.controller.withFfiMap((map: MapHandle) => {
    lent = true;
    result = block(map);
  });
  if (!lent) {
    throw new Error('The test map is not ready');
  }
  return result as T;
}

// The state of the test map's FFI map.
export function mapSnapshot(): MapSnapshot {
  return withMap((map: MapHandle) => map.getSnapshot());
}

// The ID of the FFI map that shows the controller, if any.
export function mapId(): bigint | undefined {
  return testMap.controller.withFfiMap((map: MapHandle) => map.id);
}

// The test map's camera now, as its FFI map has it: its padding includes the
// viewport insets.
export function camera(): FfiCamera {
  return mapSnapshot().view.camera;
}

// Waits until the camera rests and the controller's frame shows it, also its
// padding, and returns the controller's camera, whose padding is the app's.
export async function restingCamera(): Promise<CameraPosition> {
  const controller = testMap.controller;
  await until('the controller reports the resting camera', () => {
    const snapshot = controller.withFfiMap((map: MapHandle) => map.getSnapshot());
    const viewport = controller.viewport;
    if (snapshot === undefined || snapshot.transitionInProgress || viewport === undefined) {
      return false;
    }
    const now = snapshot.view.camera;
    const rest = controller.camera;
    // The padding moves where the center is drawn.
    const drawn = viewport.project(now.center);
    const center = pixelFor(now.center);
    return near(rest.zoom, now.zoom, 1e-6) && near(rest.bearing, now.bearing, 1e-6) &&
      near(rest.pitch, now.pitch, 1e-6) && near(rest.center.latitude, now.center.latitude, 1e-9) &&
      near(rest.center.longitude, now.center.longitude, 1e-9) && near(drawn.x, center.x, 0.01) &&
      near(drawn.y, center.y, 0.01);
  });
  return controller.camera;
}

export function near(actual: number, expected: number, tolerance: number): boolean {
  return Math.abs(actual - expected) <= tolerance;
}

// hypium's assertClose divides the difference by the actual value; this
// compares it to `tolerance` itself.
export function expectNear(actual: number, expected: number, tolerance: number): void {
  expect(Math.abs(actual - expected)).message(`${actual} is not within ${tolerance} of ${expected}`)
    .assertLessOrEqual(tolerance);
}

// Waits for `promise`, a frame at a time, and fails if it doesn't settle.
export async function settled<T>(what: string, promise: Promise<T>): Promise<T> {
  let done = false;
  promise.then(() => {
    done = true;
  }, () => {
    done = true;
  });
  await until(what, () => done);
  return promise;
}

// Sets the test map's style, and waits until it loads.
export async function setStyle(style: string | Record<string, Object>): Promise<void> {
  const loads = testMap.styleLoads;
  testMap.style = style;
  await until('the style loads', () => testMap.styleLoads > loads && testMap.controller.styleLoaded);
}

// Where `coordinate` is on the test map now, in vp, by the map's view.
export function pixelFor(coordinate: LatLng): ScreenPoint {
  const projection = MapProjectionHandle.create(mapSnapshot().view);
  try {
    return projection.pixelForLatLng(coordinate);
  } finally {
    projection.release();
  }
}

// The coordinate at `point` of the test map now, in vp, by the map's view.
export function latLngAt(point: ScreenPoint): LatLng {
  const projection = MapProjectionHandle.create(mapSnapshot().view);
  try {
    return projection.latLngForPixel(point);
  } finally {
    projection.release();
  }
}

export function vp2px(vp: number): number {
  return testMap.context?.vp2px(vp) ?? vp;
}

export function px2vp(px: number): number {
  return testMap.context?.px2vp(px) ?? px;
}

// The map's bounds on the display, in px.
export async function mapBounds(): Promise<Bounds> {
  const map = await Driver.create().findComponent(ON.type('XComponent'));
  return map.getBounds();
}

// The map's center on the display, in px.
export async function mapCenter(): Promise<Point> {
  const bounds = await mapBounds();
  return { x: Math.round((bounds.left + bounds.right) / 2), y: Math.round((bounds.top + bounds.bottom) / 2) };
}

// A point `dx`, `dy` vp from `from` on the display, in px.
export function offset(from: Point, dx: number, dy: number): Point {
  return { x: from.x + Math.round(vp2px(dx)), y: from.y + Math.round(vp2px(dy)) };
}

// A point of the display in the map's vp, given the map's bounds.
export function inMap(bounds: Bounds, point: Point): ScreenPoint {
  return { x: px2vp(point.x - bounds.left), y: px2vp(point.y - bounds.top) };
}

// Reads a pixel as [r, g, b, a] from RGBA pixels `width` wide.
export function pixelAt(pixels: Uint8Array, width: number, x: number, y: number): number[] {
  const i = (y * width + x) * 4;
  return [pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]];
}

// A PixelMap's pixels, which are RGBA.
export async function readPixels(pixelMap: image.PixelMap): Promise<Uint8Array> {
  const buffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
  await pixelMap.readPixelsToBuffer(buffer);
  return new Uint8Array(buffer);
}

// The test window's pixel at a display point in px, as red, green, and blue.
export async function screenPixel(point: Point): Promise<number[]> {
  const window = testMap.windowStage!.getMainWindowSync();
  const rect = window.getWindowProperties().windowRect;
  const pixelMap = await window.snapshot();
  try {
    const pixels = readPixelMap(pixelMap);
    const i = (point.y - rect.top) * pixels.stride + (point.x - rect.left) * 4;
    return [pixels.pixels[i], pixels.pixels[i + 1], pixels.pixels[i + 2]];
  } finally {
    pixelMap.release();
  }
}

// A color written #rrggbb, as red, green, and blue.
export function rgb(color: string): number[] {
  return [1, 3, 5].map((start: number) => parseInt(color.slice(start, start + 2), 16));
}

// Two fingers that move from `from` to `to` together, in px.
export function twoFingers(from: Point[], to: Point[], steps: number): PointerMatrix {
  const pointers = PointerMatrix.create(2, steps);
  for (let step = 0; step < steps; step++) {
    const t = steps === 1 ? 0 : step / (steps - 1);
    for (let finger = 0; finger < 2; finger++) {
      pointers.setPoint(finger, step, {
        x: Math.round(from[finger].x + (to[finger].x - from[finger].x) * t),
        y: Math.round(from[finger].y + (to[finger].y - from[finger].y) * t),
      });
    }
  }
  return pointers;
}

// Two fingers on a circle of `radius` vp about `c`, `degrees` around it. Then
// they stay at that angle for `hold` steps, which take time only if the
// fingers move, so they move 1 vp in and out.
export function twist(c: Point, radius: number, degrees: number, steps: number, hold: number = 0): PointerMatrix {
  const pointers = PointerMatrix.create(2, steps + hold);
  for (let step = 0; step < steps + hold; step++) {
    const r = degrees * Math.min(1, step / (steps - 1)) * Math.PI / 180;
    const length = vp2px(radius + (step >= steps ? (step - steps) % 2 : 0));
    const dx = Math.round(length * Math.cos(r));
    const dy = Math.round(length * Math.sin(r));
    pointers.setPoint(0, step, { x: c.x - dx, y: c.y - dy });
    pointers.setPoint(1, step, { x: c.x + dx, y: c.y + dy });
  }
  return pointers;
}

// A speed of `vp` vp a second, in the px a second that Driver takes.
export function speed(vp: number): number {
  return Math.round(vp2px(vp));
}

// Waits until the input that `act` makes has moved the camera and stopped,
// with its momentum and any animation.
export async function gesture(act: () => Promise<void>): Promise<void> {
  const starts = testMap.gestureStarts;
  await act();
  await until('a gesture starts', () => testMap.gestureStarts > starts);
  await until('the camera rests', () =>
    testMap.gestureEnds === testMap.gestureStarts && !testMap.controller.cameraMoving);
}
