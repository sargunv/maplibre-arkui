import { CommandCompletion, MapHandle } from '@maplibre/native-ffi';

// A string is the style's URL, and a record its document. The command
// completes once the style is loaded.
export function loadStyle(map: MapHandle, style: string | Record<string, Object>): Promise<CommandCompletion> {
  return typeof style === 'string' ? map.setStyleUrl(style) : map.setStyleJson(style);
}
