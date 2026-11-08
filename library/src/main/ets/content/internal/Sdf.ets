// Turns an image's alpha into a signed distance field, which MapLibre recolors
// with icon-color. A port of MapLibre Compose's convertToSdf, which comes from
// Mapbox's tiny-sdf: https://github.com/mapbox/tiny-sdf.

import { PremultipliedRgba8Image } from '@maplibre/native-ffi';

const INF = 1e20;
// The share of the radius inside the shape.
const CUTOFF = 0.25;

// The field of `source`, padded so that distances up to `radius` px fit. The
// field is in the alpha channel; MapLibre reads 0.75 as the edge.
export function toSdf(source: PremultipliedRgba8Image, radius: number): PremultipliedRgba8Image {
  const buffer = Math.ceil(radius * (1 - CUTOFF));
  const width = source.width + 2 * buffer;
  const height = source.height + 2 * buffer;
  const outer = new Float64Array(width * height).fill(INF);
  const inner = new Float64Array(width * height);
  for (let y = 0; y < source.height; y++) {
    for (let x = 0; x < source.width; x++) {
      const alpha = source.pixels[y * source.stride + x * 4 + 3];
      const i = (y + buffer) * width + x + buffer;
      if (alpha === 255) {
        outer[i] = 0;
        inner[i] = INF;
      } else if (alpha > 0) {
        const d = 0.5 - alpha / 255;
        outer[i] = d > 0 ? d * d : 0;
        inner[i] = d < 0 ? d * d : 0;
      }
    }
  }
  const size = Math.max(width, height);
  const f = new Float64Array(size);
  const z = new Float64Array(size + 1);
  const v = new Int32Array(size);
  edt(outer, width, height, f, v, z);
  edt(inner, width, height, f, v, z);

  const pixels = new Uint8Array(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    const distance = Math.sqrt(outer[i]) - Math.sqrt(inner[i]);
    pixels[i * 4 + 3] = Math.min(255, Math.max(0, Math.round(255 - 255 * (distance / radius + CUTOFF))));
  }
  return { width: width, height: height, stride: width * 4, pixels: pixels };
}

// The 2D squared Euclidean distance transform by Felzenszwalb and Huttenlocher.
function edt(data: Float64Array, width: number, height: number, f: Float64Array, v: Int32Array,
  z: Float64Array): void {
  for (let x = 0; x < width; x++) {
    edt1d(data, x, width, height, f, v, z);
  }
  for (let y = 0; y < height; y++) {
    edt1d(data, y * width, 1, width, f, v, z);
  }
}

function edt1d(grid: Float64Array, offset: number, stride: number, length: number, f: Float64Array,
  v: Int32Array, z: Float64Array): void {
  v[0] = 0;
  z[0] = -INF;
  z[1] = INF;
  f[0] = grid[offset];
  let k = 0;
  for (let q = 1; q < length; q++) {
    f[q] = grid[offset + q * stride];
    const q2 = q * q;
    let s = 0;
    do {
      const r = v[k];
      s = (f[q] - f[r] + q2 - r * r) / (q - r) / 2;
    } while (s <= z[k] && --k > -1);
    k++;
    v[k] = q;
    z[k] = s;
    z[k + 1] = INF;
  }
  k = 0;
  for (let q = 0; q < length; q++) {
    while (z[k + 1] < q) {
      k++;
    }
    const r = v[k];
    const qr = q - r;
    grid[offset + q * stride] = f[r] + qr * qr;
  }
}
