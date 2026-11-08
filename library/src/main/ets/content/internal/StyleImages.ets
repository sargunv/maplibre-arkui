// Turns a StyleImageSource and its options into the pixels and options that
// FFI's style images take. ArkUI draws resources and drawable descriptors,
// since only it knows the density of the media that it picks, so they come out
// the size that an Image draws them.

import {
  ImageContent,
  ImageStretch as FfiImageStretch,
  PremultipliedRgba8Image,
  StyleImageOptions as FfiStyleImageOptions,
  StyleImageTextFit as FfiTextFit,
} from '@maplibre/native-ffi';
import { DrawableDescriptor } from '@ohos.arkui.drawableDescriptor';
import { ComponentContent } from '@ohos.arkui.node';
import image from '@ohos.multimedia.image';

import { checkPadding, Insets, LengthScales, PaddingMetrics, paddingInVp } from '../../camera/internal/Insets';
import { isPixelMap } from '../../expression/internal/StyleRefs';
import { StretchRange, StyleImageOptions, StyleImageSource, StyleImageTextFit } from '../StyleImage';
import { readPixelMap } from './PixelMaps';
import { toSdf } from './Sdf';

// An image's pixels, and the options that FFI sets it with.
export interface StyleImagePixels {
  pixels: PremultipliedRgba8Image;
  options: FfiStyleImageOptions;
}

// Options that `checkImageOptions()` checked, and text that's the same for the
// same options.
export interface CheckedImageOptions {
  key: string;
  size: Size | undefined;
  sdf: boolean;
  drawAsSdf: boolean;
  slice: PaddingMetrics | undefined;
  x: StretchRange[];
  y: StretchRange[];
  content: PaddingMetrics | undefined;
  textFitWidth: StyleImageTextFit | undefined;
  textFitHeight: StyleImageTextFit | undefined;
}

// How far a made SDF reaches outside its shape, in vp, as in MapLibre Compose.
const SDF_RADIUS_VP = 8;

// Checks `options`, and throws an Error for the first invalid one.
export function checkImageOptions(options: StyleImageOptions | undefined): CheckedImageOptions {
  const size = options?.size;
  if (size !== undefined && !(Number.isFinite(size.width) && size.width > 0 && Number.isFinite(size.height) &&
    size.height > 0)) {
    throw new Error(`An image's size must be finite and greater than 0: ${size.width} by ${size.height}`);
  }
  const sdf = options?.sdf ?? false;
  const drawAsSdf = options?.drawAsSdf ?? false;
  if (sdf && drawAsSdf) {
    throw new Error('An image is either an SDF already (sdf) or made into one (drawAsSdf), not both');
  }
  const stretch = options?.stretch;
  const x = checkRanges(stretch?.x ?? [], 'x');
  const y = checkRanges(stretch?.y ?? [], 'y');
  const edges = stretch?.slice;
  if (edges !== undefined && (x.length > 0 || y.length > 0)) {
    throw new Error('An image stretches by its slice or by its x and y ranges, not both');
  }
  const slice: Padding | undefined = edges === undefined ? undefined :
    { top: edges.top, right: edges.right, bottom: edges.bottom, left: edges.left };
  return {
    key: JSON.stringify([size?.width, size?.height, sdf, drawAsSdf, stretch ?? null]),
    size: size,
    sdf: sdf,
    drawAsSdf: drawAsSdf,
    slice: slice === undefined ? undefined : checkPadding(slice, 'an image\'s slice'),
    x: x,
    y: y,
    content: stretch?.content === undefined ? undefined : checkPadding(stretch.content, 'an image\'s content'),
    textFitWidth: stretch?.textFitWidth,
    textFitHeight: stretch?.textFitHeight,
  };
}

function checkRanges(ranges: StretchRange[], axis: string): StretchRange[] {
  let end = 0;
  for (const range of ranges) {
    if (!(Number.isFinite(range.from) && Number.isFinite(range.to) && range.from >= end && range.to >= range.from)) {
      throw new Error(`An image's ${axis} stretch ranges must be finite, at least 0, and in increasing order ` +
        `without overlap: ${JSON.stringify(ranges)}`);
    }
    end = range.to;
  }
  return ranges;
}

class ImageParams {
  source: Resource | DrawableDescriptor;
  size: Size | undefined;

  constructor(source: Resource | DrawableDescriptor, size: Size | undefined) {
    this.source = source;
    this.size = size;
  }
}

@Builder
function drawnImage(params: ImageParams) {
  if (params.size === undefined) {
    Image(params.source)
      .syncLoad(true)
      .draggable(false)
  } else {
    Image(params.source)
      .syncLoad(true)
      .draggable(false)
      .objectFit(ImageFit.Fill)
      .width(params.size.width)
      .height(params.size.height)
  }
}

// Draws `source` with ArkUI, at the UI's density.
async function draw(context: UIContext, source: Resource | DrawableDescriptor,
  size: Size | undefined): Promise<image.PixelMap> {
  const content = new ComponentContent<ImageParams>(context, wrapBuilder(drawnImage), new ImageParams(source, size));
  try {
    return await context.getComponentSnapshot().createFromComponent(content, 0, true,
      { waitUntilRenderFinished: true });
  } finally {
    content.dispose();
  }
}

// The pixels of a pixel map, scaled to `size` at `pixelRatio` pixels per vp.
function readScaled(pixelMap: image.PixelMap, size: Size | undefined, pixelRatio: number): PremultipliedRgba8Image {
  if (size === undefined) {
    return readPixelMap(pixelMap);
  }
  const info = pixelMap.getImageInfoSync().size;
  const scaled = pixelMap.createScaledPixelMapSync(size.width * pixelRatio / info.width,
    size.height * pixelRatio / info.height);
  try {
    return readPixelMap(scaled);
  } finally {
    scaled.release();
  }
}

// The pixels of `source`, as `options` say. A pixel map is `pixelRatio` pixels
// to the vp, and is read before this returns. Throws when ArkUI can't draw or
// read the image, when a length can't convert with `scales`, or when the image
// needs a UI context that there isn't.
export async function stylePixels(source: StyleImageSource, options: CheckedImageOptions, pixelRatio: number,
  context: UIContext | undefined, scales: LengthScales): Promise<StyleImagePixels> {
  let pixels: PremultipliedRgba8Image;
  let ratio = pixelRatio;
  if (isPixelMap(source)) {
    pixels = readScaled(source as image.PixelMap, options.size, pixelRatio);
  } else {
    if (context === undefined) {
      throw new Error('Drawing a resource or a drawable descriptor needs a UI context');
    }
    const drawn = await draw(context, source as Resource | DrawableDescriptor, options.size);
    try {
      pixels = readPixelMap(drawn);
    } finally {
      drawn.release();
    }
    ratio = context.vp2px(1);
  }
  const width = pixels.width;
  const height = pixels.height;
  // A made SDF has a margin, which moves the stretch and the content.
  let margin = 0;
  if (options.drawAsSdf) {
    const field = toSdf(pixels, SDF_RADIUS_VP * ratio);
    margin = (field.width - width) / 2;
    pixels = field;
  }
  const result: FfiStyleImageOptions = {
    pixelRatio: ratio,
    sdf: options.sdf || options.drawAsSdf,
    keepUnused: true,
  };
  const toPx = (vp: number): number => margin + vp * ratio;
  const range = (from: number, to: number): FfiImageStretch => ({ from: from, to: to });
  if (options.slice !== undefined) {
    const slice: Insets = paddingInVp(options.slice, scales);
    result.stretchX = [range(toPx(slice.left), margin + width - slice.right * ratio)];
    result.stretchY = [range(toPx(slice.top), margin + height - slice.bottom * ratio)];
  } else {
    if (options.x.length > 0) {
      result.stretchX = options.x.map((r: StretchRange) => range(toPx(r.from), toPx(r.to)));
    }
    if (options.y.length > 0) {
      result.stretchY = options.y.map((r: StretchRange) => range(toPx(r.from), toPx(r.to)));
    }
  }
  if (options.content !== undefined) {
    const inset: Insets = paddingInVp(options.content, scales);
    const box: ImageContent = {
      left: toPx(inset.left),
      top: toPx(inset.top),
      right: margin + width - inset.right * ratio,
      bottom: margin + height - inset.bottom * ratio,
    };
    result.content = box;
  }
  if (options.textFitWidth !== undefined) {
    result.textFitWidth = textFit(options.textFitWidth);
  }
  if (options.textFitHeight !== undefined) {
    result.textFitHeight = textFit(options.textFitHeight);
  }
  return { pixels: pixels, options: result };
}

function textFit(fit: StyleImageTextFit): FfiTextFit {
  switch (fit) {
    case StyleImageTextFit.STRETCH_ONLY:
      return FfiTextFit.stretchOnly;
    case StyleImageTextFit.PROPORTIONAL:
      return FfiTextFit.proportional;
    default:
      return FfiTextFit.stretchOrShrink;
  }
}
