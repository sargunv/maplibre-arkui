// The library's log, where each message starts with `MapLibre:` so apps can
// tell it from their own.

export function logError(message: string): void {
  console.error(`MapLibre: ${message}`);
}
