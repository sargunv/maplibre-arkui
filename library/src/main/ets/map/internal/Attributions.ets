import { MapHandle, StyleSourceInfo } from '@maplibre/native-ffi';

// The attribution of the style's sources, as HTML, without repeats, in the
// order the style lists them.
export async function styleAttributions(map: MapHandle): Promise<string[]> {
  const sources: readonly StyleSourceInfo[] = await map.listStyleSources();
  const attributions: string[] = [];
  for (const source of sources) {
    const attribution = source.attribution.trim();
    if (attribution !== '' && !attributions.includes(attribution)) {
      attributions.push(attribution);
    }
  }
  return attributions;
}
