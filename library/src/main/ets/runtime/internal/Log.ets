// The library's log, which holds its own messages and MapLibre Native's. Each
// of the library's messages goes to hilog with the prefix `MapLibre:`, so apps
// can tell it from their own, and to the app's log handler. The calls of the
// app's handlers log what they throw and go on.

import { clearLogCallback, LogEvent, LogSeverity, LogSeverityFlag, setLogCallback } from '@maplibre/native-ffi';

import { MapLogHandler, MapLogLevel, MapLogRecord } from '../Logs';

// MapLibre Native's categories, by FFI's `LogEvent` values.
const CATEGORIES: string[] = ['general', 'setup', 'shader', 'parseStyle', 'parseTile', 'render', 'style',
  'database', 'httpRequest', 'sprite', 'image', 'graphicsBackend', 'jni', 'android', 'crash', 'glyph', 'timing'];

let logHandler: MapLogHandler | undefined = undefined;

// Sends the log to `handler`, or to hilog only without one. MapLibre Native's
// errors still go to hilog with a handler, as the library's own do.
export function setLogHandler(handler: MapLogHandler | undefined): void {
  logHandler = handler;
  if (handler === undefined) {
    clearLogCallback();
    return;
  }
  setLogCallback({
    callback: (severity: LogSeverity, event: LogEvent, code: bigint, message: string) => {
      const level = severity === LogSeverity.error ? MapLogLevel.ERROR :
        severity === LogSeverity.warning ? MapLogLevel.WARN : MapLogLevel.INFO;
      const category = Number.isInteger(event) && event >= 0 && event < CATEGORIES.length ? CATEGORIES[event] :
        `${event}`;
      deliver({ level: level, message: message, category: category });
    },
    platformSeverities: LogSeverityFlag.error,
  });
}

function deliver(record: MapLogRecord): void {
  const handler = logHandler;
  if (handler === undefined) {
    return;
  }
  try {
    handler(record);
  } catch (error) {
    // Not to the handler again, which would throw again.
    console.error(`MapLibre: the log handler threw: ${(error as Error).message}`);
  }
}

export function logError(message: string): void {
  console.error(`MapLibre: ${message}`);
  deliver({ level: MapLogLevel.ERROR, message: message, category: undefined });
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
