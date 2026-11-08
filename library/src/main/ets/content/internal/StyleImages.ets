// Turns a StyleImageSource into the pixels that FFI's style images take. ArkUI
// draws resources and drawable descriptors, since only it knows the density of
// the media that it picks, so they come out the size that an Image draws them.

import { PremultipliedRgba8Image } from '@maplibre/native-ffi';
import { DrawableDescriptor } from '@ohos.arkui.drawableDescriptor';
import { ComponentContent } from '@ohos.arkui.node';
import image from '@ohos.multimedia.image';

import { isPixelMap } from '../../expression/internal/StyleRefs';
import { StyleImageSource } from '../StyleImage';
import { readPixelMap } from './PixelMaps';
import { toSdf } from './Sdf';

// An image's pixels, and how many of them make one vp.
export interface StyleImagePixels {
  pixels: PremultipliedRgba8Image;
  pixelRatio: number;
}

// How far an SDF reaches outside its shape, in vp, as in MapLibre Compose.
const SDF_RADIUS_VP = 8;

class ImageParams {
  source: Resource | DrawableDescriptor;

  constructor(source: Resource | DrawableDescriptor) {
    this.source = source;
  }
}

@Builder
function drawnImage(params: ImageParams) {
  Image(params.source)
    .syncLoad(true)
    .draggable(false)
}

// Draws `source` with ArkUI, at the UI's density.
async function draw(context: UIContext, source: Resource | DrawableDescriptor): Promise<image.PixelMap> {
  const content = new ComponentContent<ImageParams>(context, wrapBuilder(drawnImage), new ImageParams(source));
  try {
    return await context.getComponentSnapshot().createFromComponent(content, 0, true,
      { waitUntilRenderFinished: true });
  } finally {
    content.dispose();
  }
}

// The pixels of `source`. A pixel map is `pixelRatio` pixels to the vp. Throws
// when ArkUI can't draw or read the image, or when it needs a UI context that
// there isn't.
export async function stylePixels(source: StyleImageSource, drawAsSdf: boolean, pixelRatio: number,
  context: UIContext | undefined): Promise<StyleImagePixels> {
  let pixels: PremultipliedRgba8Image;
  let ratio = pixelRatio;
  if (!isPixelMap(source)) {
    if (context === undefined) {
      throw new Error('Drawing a resource or a drawable descriptor needs a UI context');
    }
    const drawn = await draw(context, source as Resource | DrawableDescriptor);
    try {
      pixels = readPixelMap(drawn);
    } finally {
      drawn.release();
    }
    ratio = context.vp2px(1);
  } else {
    pixels = readPixelMap(source as image.PixelMap);
  }
  if (drawAsSdf) {
    pixels = toSdf(pixels, SDF_RADIUS_VP * ratio);
  }
  return { pixels: pixels, pixelRatio: ratio };
}
