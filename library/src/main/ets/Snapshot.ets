// Still images of a map that isn't on screen, as FFI's "Render images" guide
// renders them: a static map, an offscreen session, and a still image request.

import {
  CameraOptions,
  CameraUpdateMode,
  MapMode,
  RenderDriverKind,
  RuntimeEventFlag,
  RuntimeHandle,
  TextureReadbackResult,
} from '@maplibre/native-ffi';
import display from '@ohos.display';
import image from '@ohos.multimedia.image';

import { loadStyle } from './MapView';
import { getDefaultRuntime } from './runtime';

/** What `snapshot()` renders. */
export interface SnapshotOptions {
  /** The style's URL, or a style document as JSON, as `MapLibreMap` takes it. */
  style: string;
  /** The image's width in vp. */
  width: number;
  /** The image's height in vp. */
  height: number;
  /**
   * Where the camera looks. Without one, the image uses the style's default
   * camera. With one, the fields it leaves out take MapLibre's defaults, not
   * the style's.
   */
  camera?: CameraOptions;
  /**
   * The image's pixels in each vp. Defaults to the default display's density,
   * so the image is as sharp as a map of the same size on screen.
   */
  scaleFactor?: number;
  /**
   * The runtime that loads the style and its resources, with that runtime's
   * cache, offline regions, and request handlers. Defaults to the default
   * runtime.
   */
  runtime?: RuntimeHandle;
}

/**
 * Renders a still image of a map without showing it, for an `Image` to show,
 * or to save or share. The image is `width` by `height` vp, at `scaleFactor`
 * pixels in each vp.
 *
 * ```ets
 * this.preview = await snapshot({ style: STYLE_URL, width: 320, height: 180,
 *   camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 } });
 * // In build(): Image(this.preview)
 * ```
 *
 * It resolves once every resource the image needs has loaded, and rejects when
 * the style or one of those resources fails to load. To capture what a
 * `MapLibreMap` shows, pass its style and its controller's camera, through
 * `cameraToOptions()`, when `getCamera()` returns one. The image holds only
 * the map: show the style's attribution with it.
 */
export async function snapshot(options: SnapshotOptions): Promise<image.PixelMap> {
  const runtime = options.runtime ?? await getDefaultRuntime();
  const scaleFactor = options.scaleFactor ?? display.getDefaultDisplaySync().densityPixels;
  const map = runtime.createMap({
    initialExtent: { width: options.width, height: options.height, scaleFactor: scaleFactor },
    mapMode: MapMode.static,
    eventMask: RuntimeEventFlag.none,
  });
  try {
    await map.ready;
    const session = map.attachOffscreen({ logicalSize: { width: options.width, height: options.height } },
      { driver: RenderDriverKind.coreWorker });
    try {
      await session.ready;
      loadStyle(map, options.style);
      if (options.camera !== undefined) {
        map.discarding.updateCamera({ mode: CameraUpdateMode.jump, camera: options.camera });
      }
      await map.requestStillImage();
      return await toPixelMap(await session.readTexture());
    } finally {
      await session.release();
    }
  } finally {
    await map.release();
  }
}

// The texture's rows can be longer than its pixels, and a PixelMap's can't.
function toPixelMap(texture: TextureReadbackResult): Promise<image.PixelMap> {
  const width = texture.info.width;
  const height = texture.info.height;
  const rowBytes = width * 4;
  const stride = texture.info.stride;
  const pixels = new Uint8Array(rowBytes * height);
  for (let row = 0; row < height; row++) {
    pixels.set(texture.data.subarray(row * stride, row * stride + rowBytes), row * rowBytes);
  }
  return image.createPixelMap(pixels.buffer, {
    size: { width: width, height: height },
    srcPixelFormat: image.PixelMapFormat.RGBA_8888,
    pixelFormat: image.PixelMapFormat.RGBA_8888,
    alphaType: image.AlphaType.PREMUL,
  });
}
