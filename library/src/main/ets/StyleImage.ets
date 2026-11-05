import image from '@ohos.multimedia.image';

import { PremultipliedRgba8Image } from '@maplibre/native-ffi';

/**
 * Copies the pixels of `pixelMap` into the premultiplied RGBA image that FFI's
 * `MapHandle.setStyleImage()` and image sources take:
 *
 * ```ets
 * map.setStyleImage('pin', readPixelMap(pixelMap), { pixelRatio: 2 });
 * ```
 *
 * It reads `RGBA_8888` and `BGRA_8888` pixel maps, premultiplied or not, which
 * is what decoding an image gives by default. Convert other formats first
 * with `PixelMap.convertPixelFormat()`. The style draws the image at
 * `pixelRatio` image pixels per vp, 1 by default. Throws when the pixel map
 * can't be read, such as after its release.
 */
export function readPixelMap(pixelMap: image.PixelMap): PremultipliedRgba8Image {
  const info = pixelMap.getImageInfoSync();
  const format = info.pixelFormat;
  if (format !== image.PixelMapFormat.RGBA_8888 && format !== image.PixelMapFormat.BGRA_8888) {
    throw new Error(`readPixelMap() reads RGBA_8888 and BGRA_8888 pixel maps, not format ${format}`);
  }
  const width = info.size.width;
  const height = info.size.height;
  const buffer = new ArrayBuffer(pixelMap.getPixelBytesNumber());
  pixelMap.readPixelsToBufferSync(buffer);
  // The buffer holds `height` rows, which can be padded past `width` pixels.
  const stride = height > 0 ? buffer.byteLength / height : width * 4;
  const pixels = new Uint8Array(buffer);
  const bgra = format === image.PixelMapFormat.BGRA_8888;
  const premultiply = info.alphaType === image.AlphaType.UNPREMUL;
  if (bgra || premultiply) {
    for (let row = 0; row < height; row++) {
      for (let offset = row * stride; offset < row * stride + width * 4; offset += 4) {
        const alpha = pixels[offset + 3];
        const first = pixels[offset];
        if (bgra) {
          pixels[offset] = pixels[offset + 2];
          pixels[offset + 2] = first;
        }
        if (premultiply && alpha < 255) {
          for (let channel = offset; channel < offset + 3; channel++) {
            pixels[channel] = Math.round(pixels[channel] * alpha / 255);
          }
        }
      }
    }
  }
  return { width: width, height: height, stride: stride, pixels: pixels };
}
