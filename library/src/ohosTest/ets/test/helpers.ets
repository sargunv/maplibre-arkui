// What the suites share: waits, the test map's camera and handles, absolute
// comparisons, and where the map is on the display.

import { expect } from '@ohos/hypium';
import { CameraPosition, LatLng, MapHandle, MapProjectionHandle, readPixelMap, ScreenPoint } from '@maplibre/arkui';
import application from '@ohos.app.ability.application';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { Driver, ON, Point, Rect as Bounds } from '@ohos.UiTest';

import { testMap, until } from '../testability/TestMaps';

export { eventually, frames, nextFrame, until, WAIT_MS } from '../testability/TestMaps';

// The test map's camera now.
export function camera(): CameraPosition {
  const current = testMap.controller.getCamera();
  if (current === undefined) {
    throw new Error('The test map has no camera');
  }
  return current;
}

// The test map's FFI map, once its style loads.
export function requireMap(): MapHandle {
  const map = testMap.controller.map;
  if (map === undefined) {
    throw new Error('The test map is not ready');
  }
  return map;
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
export async function setStyle(style: string): Promise<void> {
  const loads = testMap.styleLoads;
  testMap.style = style;
  await until('the style loads', () => testMap.styleLoads > loads && testMap.controller.styleLoaded);
}

// Where `coordinate` is on the test map now, in vp, by the map's view.
export function pixelFor(coordinate: LatLng): ScreenPoint {
  const projection = MapProjectionHandle.create(requireMap().getSnapshot().view);
  try {
    return projection.pixelForLatLng(coordinate);
  } finally {
    projection.release();
  }
}

// The coordinate at `point` of the test map now, in vp, by the map's view.
export function latLngAt(point: ScreenPoint): LatLng {
  const projection = MapProjectionHandle.create(requireMap().getSnapshot().view);
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

// The pixel of the display at `point` in px, as red, green, and blue.
export async function screenPixel(point: Point): Promise<number[]> {
  const path = `${application.getApplicationContext().cacheDir}/screen-${Date.now()}.png`;
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
export function rgb(color: string): number[] {
  return [1, 3, 5].map((start: number) => parseInt(color.slice(start, start + 2), 16));
}
