// The library's log, where each message starts with `MapLibre:` so apps can
// tell it from their own, and the calls of the app's handlers, which log what
// they throw and go on.

export function logError(message: string): void {
  console.error(`MapLibre: ${message}`);
}

// Calls the app's handler, which `what` names in the log if it throws.
export function callHandler(what: string, handler: () => void): void {
  try {
    handler();
  } catch (error) {
    logError(`${what} threw: ${(error as Error).message}`);
  }
}

// Calls the app's click handler, and returns whether it consumed the click.
// One that throws didn't.
export function consumes(what: string, handler: () => boolean): boolean {
  try {
    return handler();
  } catch (error) {
    logError(`${what} threw: ${(error as Error).message}`);
    return false;
  }
}
