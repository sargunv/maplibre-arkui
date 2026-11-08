// Still images of a map that isn't on screen, as FFI's "Render images" guide
// renders them: a static map, an offscreen session, and a still image request.

import {
  CameraOptions as FfiCameraOptions,
  CameraUpdateMode,
  MapMode,
  RenderDriverKind,
  RuntimeEventFlag,
  RuntimeHandle,
  TextureReadbackResult,
} from '@maplibre/native-ffi';
import image from '@ohos.multimedia.image';
import display from '@ohos.display';

import { CameraUpdate } from '../camera/CameraPosition';
import { checkCamera, toFfiCamera } from '../camera/internal/FfiCamera';
import { contextScales, LengthScales, NO_INSETS, paddingInVp } from '../camera/internal/Insets';
import { ContentReconciler } from '../content/internal/ContentReconciler';
import { MapContent } from '../content/MapContent';
import { fontScaleOf } from '../expression/internal/FontScale';
import { styleAttributions } from '../map/internal/Attributions';
import { loadStyle } from '../map/internal/StyleLoading';
import { logError } from '../runtime/internal/Log';
import { runtimeState } from '../runtime/internal/RuntimeRegistry';
import { MapRuntime } from '../runtime/MapRuntime';

/** What `renderSnapshot()` renders. */
export interface MapSnapshotOptions {
  /** The style: a URL, or a style document as style-spec JSON. A string is always a URL. */
  style: string | Record<string, Object>;
  /** The image's width in vp, rounded to a whole number. At least 1 after rounding. */
  width: number;
  /** The image's height in vp, rounded to a whole number. At least 1 after rounding. */
  height: number;
  /**
   * Sources and layers to draw over the style. One that MapLibre rejects is
   * left out and logged. Images from resources and drawable descriptors need
   * `uiContext`. None by default.
   */
  content?: MapContent;
  /**
   * Where the camera looks. Fields left out default to center 0, 0, zoom 0,
   * bearing 0, pitch 0, and no padding. The values must be valid for
   * `MapController.updateCamera()`.
   */
  camera?: CameraUpdate;
  /**
   * The UI that will show the image, which sets the defaults of `pixelRatio`
   * and `fontScale`. Without it, they default to the default display's density
   * and 1.
   */
  uiContext?: UIContext;
  /**
   * The number of image pixels per vp. Finite and greater than 0. Defaults to
   * the density of `uiContext`.
   */
  pixelRatio?: number;
  /**
   * The scale of sizes given with `fp()`. Finite and greater than 0. Defaults
   * to the font scale of `uiContext`.
   */
  fontScale?: number;
  /** The runtime that loads the style and its resources. The default runtime by default. */
  runtime?: MapRuntime;
}

/** A still image of a map. Fields may be added in later releases. */
export interface MapSnapshot {
  /**
   * The image, `width × pixelRatio` by `height × pixelRatio` pixels rounded
   * up, in premultiplied `RGBA_8888`. The caller owns it and must release it.
   */
  readonly image: image.PixelMap;
  /**
   * The attributions of the style's sources, as HTML, without duplicates, in
   * the style's order.
   */
  readonly attributions: string[];
}

/**
 * Renders a still image of a map without showing it on screen. The image has
 * the style and content only, with no user location indicator or ArkUI
 * controls. Call it on the UI thread.
 *
 * Throws an `Error` for an invalid size, `pixelRatio`, or `fontScale`, for a
 * camera that `MapController.updateCamera()` would throw for, or for a camera
 * padding that can't convert to vp.
 *
 * Resolves once every resource the image needs has loaded, so it stays
 * pending while MapLibre is offline and a resource isn't cached. Rejects with
 * an `Error` if the style or a needed resource fails to load, or if the
 * runtime fails to open or is released.
 */
export function renderSnapshot(options: MapSnapshotOptions): Promise<MapSnapshot> {
  const width = checkSize(options.width, 'width');
  const height = checkSize(options.height, 'height');
  const context = options.uiContext;
  const pixelRatio = options.pixelRatio ?? context?.vp2px(1) ?? display.getDefaultDisplaySync().densityPixels;
  checkScale(pixelRatio, 'pixelRatio');
  const fontScale = options.fontScale ?? (context === undefined ? 1 : fontScaleOf(context));
  checkScale(fontScale, 'fontScale');
  const camera = checkCamera(options.camera ?? {});
  const scales: LengthScales = context === undefined ? {
    px: (px: number) => px / pixelRatio,
    fp: (fp: number) => fp * fontScale,
  } : contextScales(context);
  const padding = camera.padding === undefined ? NO_INSETS : paddingInVp(camera.padding, scales);
  const start = toFfiCamera({
    center: camera.center ?? { latitude: 0, longitude: 0 },
    zoom: camera.zoom ?? 0,
    bearing: camera.bearing ?? 0,
    pitch: camera.pitch ?? 0,
  }, padding);
  // The runtime closes only after the snapshot releases its map.
  const runtime = runtimeState(options.runtime ?? MapRuntime.getDefault());
  const rendering = render(options, runtime.open(), width, height, pixelRatio, fontScale, start);
  runtime.track(rendering.then(() => {
  }));
  return rendering;
}

// FFI takes whole vp, so a size rounds to one.
function checkSize(value: number, what: string): number {
  const rounded = Math.round(value);
  if (!(Number.isFinite(rounded) && rounded >= 1)) {
    throw new Error(`A snapshot's ${what} must be finite and at least 1 vp once rounded: ${value}`);
  }
  return rounded;
}

function checkScale(value: number, what: string): void {
  if (!(Number.isFinite(value) && value > 0)) {
    throw new Error(`A snapshot's ${what} must be finite and greater than 0: ${value}`);
  }
}

async function render(options: MapSnapshotOptions, opening: Promise<RuntimeHandle>, width: number, height: number,
  pixelRatio: number, fontScale: number, camera: FfiCameraOptions): Promise<MapSnapshot> {
  const runtime = await opening;
  const map = runtime.createMap({
    initialExtent: { width: width, height: height, scaleFactor: pixelRatio },
    mapMode: MapMode.static,
    eventMask: RuntimeEventFlag.none,
  });
  try {
    await map.ready;
    // Before the style, as a MaplibreMap's start camera, so the style's own
    // camera doesn't replace it.
    map.discarding.updateCamera({ mode: CameraUpdateMode.jump, camera: camera });
    const session = map.attachOffscreen({ logicalSize: { width: width, height: height } },
      { driver: RenderDriverKind.coreWorker });
    try {
      await session.ready;
      const reconciler = new ContentReconciler(map,
        (error: Error) => logError(`a snapshot left out content: ${error.message}`), pixelRatio, options.uiContext);
      reconciler.setContent(options.content);
      reconciler.setFontScale(fontScale);
      await loadStyle(map, options.style);
      await reconciler.styleLoaded();
      await map.requestStillImage();
      const pixelMap = await toPixelMap(await session.readTexture());
      try {
        // After the image, so the sources' TileJSON, which can bring their
        // attribution, has loaded.
        return { image: pixelMap, attributions: await styleAttributions(map) };
      } catch (error) {
        await pixelMap.release();
        throw error as Error;
      }
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
