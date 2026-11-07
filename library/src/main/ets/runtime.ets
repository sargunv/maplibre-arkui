// What the maps of an app share: the default runtime, the frame pacer, and the
// event listeners of each runtime. The first use of a runtime starts following
// the device's connectivity.

import {
  FramePacerHandle,
  MapHandle,
  ohosFramePacerCreate,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeEventSourceType,
  RuntimeHandle,
} from '@maplibre/native-ffi';
import application from '@ohos.app.ability.application';

import { followConnectivity } from './connectivity';
import { logError } from './log';

/** Takes one event of a runtime or of one of its maps. */
export type RuntimeEventListener = (event: RuntimeEvent) => void;

// A listener, and the map events it asked for.
interface Registration {
  listener: RuntimeEventListener;
  mapEvents: RuntimeEventFlag;
}

// A live map of a runtime, and where the failure of its commands goes.
interface LiveMap {
  map: MapHandle;
  fail: (error: Error) => void;
}

let defaultRuntime: Promise<RuntimeHandle> | undefined = undefined;
let framePacer: FramePacerHandle | undefined = undefined;
const listeners: Map<bigint, Registration[]> = new Map();
const liveMaps: Map<bigint, LiveMap[]> = new Map();

/**
 * The runtime that every `MaplibreMap` and `snapshot()` uses unless the app
 * passes its own. The library creates it on first use and keeps it for the
 * app's life.
 *
 * Its cache database, which holds the ambient cache and offline regions, is
 * `maplibre-cache.db` in the app's files directory, so offline regions last
 * until the app deletes them. For another cache, create a runtime with
 * `RuntimeHandle.create()` and pass it to each map.
 *
 * The library sets the runtime's event handler, so don't replace it; listen
 * with `addRuntimeEventListener()` instead.
 */
export function getDefaultRuntime(): Promise<RuntimeHandle> {
  followConnectivity();
  if (defaultRuntime === undefined) {
    const created = createDefaultRuntime();
    defaultRuntime = created;
    // Try again on the next call after a failure.
    created.catch(() => {
      if (defaultRuntime === created) {
        defaultRuntime = undefined;
      }
    });
  }
  return defaultRuntime;
}

async function createDefaultRuntime(): Promise<RuntimeHandle> {
  const files = application.getApplicationContext().filesDir;
  return RuntimeHandle.create({ cachePath: `${files}/maplibre-cache.db` });
}

/**
 * Calls `listener` with each event of `runtime`, such as the download progress
 * of an offline region, and the events of its maps that `mapEvents` asks for,
 * as `RuntimeEventFlag` bits.
 *
 * ```ets
 * addRuntimeEventListener(runtime, (event: RuntimeEvent) => {
 *   if (event.type === RuntimeEventType.mapIdle) {
 *     console.info(`Map ${event.source} is idle`);
 *   }
 * }, RuntimeEventFlag.mapIdle);
 * ```
 *
 * The maps of `MaplibreMap` components on the runtime report the events that
 * some listener asks for, so the library sets their FFI maps' event masks:
 * don't call `MapHandle.setEventMask()`. The listener gets only the map events
 * it asks for, and every event that comes from the runtime itself, which no
 * mask selects. Without `mapEvents`, it gets no map events. Maps that
 * `snapshot()` renders report none.
 *
 * A runtime has one FFI event handler, which the library sets once a map or a
 * listener uses the runtime, so listen here instead of calling
 * `RuntimeHandle.setEventHandler()`.
 */
export function addRuntimeEventListener(runtime: RuntimeHandle, listener: RuntimeEventListener,
  mapEvents: RuntimeEventFlag = RuntimeEventFlag.none): void {
  registrationsOf(runtime).push({ listener: listener, mapEvents: mapEvents });
  applyEventMask(runtime);
}

/**
 * Stops calling a listener that `addRuntimeEventListener()` added, and stops
 * the map events that only it asked for.
 */
export function removeRuntimeEventListener(runtime: RuntimeHandle, listener: RuntimeEventListener): void {
  const all = listeners.get(runtime.id);
  const index = all?.findIndex((registration: Registration) => registration.listener === listener) ?? -1;
  if (all !== undefined && index >= 0) {
    all.splice(index, 1);
    applyEventMask(runtime);
  }
}

// The map events that the runtime's listeners ask for, which its maps report.
export function runtimeEventMask(runtime: RuntimeHandle): RuntimeEventFlag {
  let mask: RuntimeEventFlag = RuntimeEventFlag.none;
  for (const registration of listeners.get(runtime.id) ?? []) {
    mask = mask | registration.mapEvents;
  }
  return mask;
}

// A map that keeps the runtime's event mask from when it's ready until it's
// released. A listener may have changed the mask while the map got ready, so
// it takes the mask again.
export function addRuntimeMap(runtime: RuntimeHandle, map: MapHandle, fail: (error: Error) => void): void {
  let all = liveMaps.get(runtime.id);
  if (all === undefined) {
    all = [];
    liveMaps.set(runtime.id, all);
  }
  const live: LiveMap = { map: map, fail: fail };
  all.push(live);
  setEventMask(live, runtimeEventMask(runtime));
}

export function removeRuntimeMap(runtime: RuntimeHandle, map: MapHandle): void {
  const all = liveMaps.get(runtime.id);
  const index = all?.findIndex((live: LiveMap) => live.map === map) ?? -1;
  if (all !== undefined && index >= 0) {
    all.splice(index, 1);
  }
}

// The maps run commands in order, so the last mask set is the one they keep.
function applyEventMask(runtime: RuntimeHandle): void {
  const mask = runtimeEventMask(runtime);
  for (const live of liveMaps.get(runtime.id) ?? []) {
    setEventMask(live, mask);
  }
}

function setEventMask(live: LiveMap, mask: RuntimeEventFlag): void {
  live.map.setEventMask(mask).catch((error: Error) => live.fail(error));
}

// Whether a listener that asked for `mapEvents` takes `event`. A flag is the
// bit of its event type, and events of the runtime itself take no mask.
function wants(mapEvents: RuntimeEventFlag, event: RuntimeEvent): boolean {
  return event.sourceType !== RuntimeEventSourceType.map ||
    (mapEvents & (BigInt(1) << BigInt(event.type))) !== RuntimeEventFlag.none;
}

// One pacer serves every session. It follows the display's VSync, so the
// sessions need no redraw wake.
export function getFramePacer(): FramePacerHandle {
  if (framePacer === undefined) {
    framePacer = ohosFramePacerCreate();
  }
  return framePacer;
}

// The first use of a runtime sets a handler that passes each event to the
// runtime's listeners that want it, the maps' and the app's.
function registrationsOf(runtime: RuntimeHandle): Registration[] {
  let found = listeners.get(runtime.id);
  if (found === undefined) {
    followConnectivity();
    const created: Registration[] = [];
    found = created;
    listeners.set(runtime.id, created);
    runtime.discarding.setEventHandler({
      callback: (events: readonly RuntimeEvent[]) => {
        for (const event of events) {
          // A listener can remove itself as it runs, and one that throws
          // doesn't keep the event from the others.
          for (const registration of created.slice()) {
            if (!wants(registration.mapEvents, event)) {
              continue;
            }
            try {
              registration.listener(event);
            } catch (error) {
              logError(`a runtime event listener threw: ${(error as Error).message}`);
            }
          }
        }
      },
    });
  }
  return found;
}
