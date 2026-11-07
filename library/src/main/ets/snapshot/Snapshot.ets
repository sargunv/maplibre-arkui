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
  /**
   * The style, as `MaplibreMap` takes it: a URL, or a style document as
   * style-spec JSON. A string is always a URL.
   */
  style: string | Record<string, Object>;
  /**
   * The image's width in vp, rounded to a whole vp. Finite and at least 1
   * after rounding.
   */
  width: number;
  /**
   * The image's height in vp, rounded to a whole vp. Finite and at least 1
   * after rounding.
   */
  height: number;
  /**
   * Sources, layers, and images to draw over the style, as `MaplibreMap`
   * takes them. A source, layer, or image that the map rejects is left out
   * and logged. Layers' click handlers do nothing. Images' `pixelRatio`
   * defaults to the snapshot's `pixelRatio`. None by default.
   */
  content?: MapContent;
  /**
   * Where the camera looks. Fields it leaves out take MapLibre's defaults, as
   * those of `MapControllerOptions.camera` do: center 0, 0, zoom 0, bearing 0,
   * pitch 0, and no padding. Its padding is space in the image's vp, and the
   * camera's values must be valid as `MapController.updateCamera()` takes
   * them.
   */
  camera?: CameraUpdate;
  /**
   * The UI that the image is for, such as `this.getUIContext()` of the
   * component that shows it. It sets the defaults of `pixelRatio` and
   * `fontScale`, and converts the camera padding's lengths to vp. Without
   * it, the default display's density sets `pixelRatio`, `fontScale` is 1, a
   * padding length in px is a pixel of the image, one in fp scales by
   * `fontScale`, and one in lpx throws.
   */
  uiContext?: UIContext;
  /**
   * The image's pixels in each vp. Finite and greater than 0. Defaults to
   * `vp2px(1)` of `uiContext`, so the image is as sharp as a map of the same
   * size in that UI.
   */
  pixelRatio?: number;
  /**
   * How much the sizes that `fp()` gives scale. Finite and greater than 0.
   * Defaults to `fp2px(1) / vp2px(1)` of `uiContext`, as a `MaplibreMap` in
   * that UI scales them.
   */
  fontScale?: number;
  /**
   * The runtime that loads the style and its resources, with that runtime's
   * cache, offline regions, and request handling. The default runtime by
   * default.
   */
  runtime?: MapRuntime;
}

/**
 * A still image of a map, which `renderSnapshot()` resolves with. The library
 * creates it, and later releases may add fields.
 */
export interface MapSnapshot {
  /**
   * The image: `width × pixelRatio` by `height × pixelRatio` pixels, each
   * rounded up to a whole pixel, in the premultiplied `RGBA_8888` format. The
   * caller owns it: release it once nothing shows it.
   */
  readonly image: image.PixelMap;
  /**
   * The attribution of the style's sources, as HTML, without repeats, in the
   * order the style lists them, as `MapController.attributions` gives it. Show
   * it with the image, as the sources' terms usually require, such as with
   * `AttributionText`.
   */
  readonly attributions: string[];
}

/**
 * Renders a still image of a map without showing it, for an `Image` to show,
 * or to save or share.
 *
 * ```ets
 * const preview = await renderSnapshot({ style: STYLE_URL, width: 320, height: 180,
 *   camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
 *   uiContext: this.getUIContext() });
 * // In build(): Image(preview.image), and AttributionText({ attributions: preview.attributions })
 * ```
 *
 * Call it on the UI thread. It throws an `Error` with the value for a size,
 * `pixelRatio`, or `fontScale` that isn't valid, and for a camera that
 * `MapController.updateCamera()` would throw for or whose padding can't
 * convert to vp.
 *
 * The promise resolves once every resource that the image needs has loaded,
 * so it stays pending for as long as one of them does, such as while
 * `MapRuntime.setConnectivityMode()` keeps MapLibre offline. It rejects with
 * an `Error` when the style fails to load, when a style document is one that
 * MapLibre rejects, when a resource that the image needs fails to load, and
 * when the runtime fails to open or is released.
 *
 * The image holds the style and the content only: no user location indicator
 * and no ArkUI controls. To capture what a `MaplibreMap` shows, pass its
 * style, its content, and its controller's camera. Snapshots render at the
 * same time, each with a GPU session of its own, so render many one after
 * another.
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
        (error: Error) => logError(`a snapshot left out content: ${error.message}`), pixelRatio);
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
