// What the maps of an app share: the default runtime, the frame pacer, and the
// event handler of each runtime.

import {
  FramePacerHandle,
  MapHandle,
  ohosFramePacerCreate,
  RuntimeEvent,
  RuntimeHandle,
} from '@maplibre/native-ffi';
import application from '@ohos.app.ability.application';

/** Takes one event of a runtime or of one of its maps. */
export type RuntimeEventListener = (event: RuntimeEvent) => void;

// The listeners of one runtime: the app's, which take every event, and each
// map's, which take that map's events.
class RuntimeListeners {
  readonly all: RuntimeEventListener[] = [];
  readonly byMap: Map<bigint, RuntimeEventListener> = new Map();
}

let defaultRuntime: Promise<RuntimeHandle> | undefined = undefined;
let framePacer: FramePacerHandle | undefined = undefined;
const listeners: Map<bigint, RuntimeListeners> = new Map();

/**
 * The runtime that every `MapLibreMap` and `snapshot()` uses unless the app
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
 * Calls `listener` with each event of `runtime` and its maps, such as the
 * download progress of an offline region.
 *
 * A runtime has one FFI event handler, which the library sets once a map or a
 * listener uses the runtime, so listen here instead of calling
 * `RuntimeHandle.setEventHandler()`. A map reports only the events that its
 * component needs.
 */
export function addRuntimeEventListener(runtime: RuntimeHandle, listener: RuntimeEventListener): void {
  listenersOf(runtime).all.push(listener);
}

/** Stops calling a listener that `addRuntimeEventListener()` added. */
export function removeRuntimeEventListener(runtime: RuntimeHandle, listener: RuntimeEventListener): void {
  const all = listeners.get(runtime.id)?.all;
  const index = all?.indexOf(listener) ?? -1;
  if (all !== undefined && index >= 0) {
    all.splice(index, 1);
  }
}

// One pacer serves every session. It follows the display's VSync, so the
// sessions need no redraw wake.
export function getFramePacer(): FramePacerHandle {
  if (framePacer === undefined) {
    framePacer = ohosFramePacerCreate();
  }
  return framePacer;
}

export function listenToMap(runtime: RuntimeHandle, map: MapHandle, listener: RuntimeEventListener): void {
  listenersOf(runtime).byMap.set(map.id, listener);
}

export function stopListeningToMap(runtime: RuntimeHandle, map: MapHandle): void {
  listeners.get(runtime.id)?.byMap.delete(map.id);
}

// The first use of a runtime sets a handler that passes each event to the map
// that raised it and to the app's listeners.
function listenersOf(runtime: RuntimeHandle): RuntimeListeners {
  let found = listeners.get(runtime.id);
  if (found === undefined) {
    const created = new RuntimeListeners();
    found = created;
    listeners.set(runtime.id, created);
    runtime.discarding.setEventHandler({
      callback: (events: readonly RuntimeEvent[]) => {
        for (const event of events) {
          created.byMap.get(event.source)?.(event);
          // A listener can remove itself as it runs, and one that throws
          // doesn't keep the event from the others.
          for (const listener of created.all.slice()) {
            try {
              listener(event);
            } catch (error) {
              console.error(`MapLibre: a runtime event listener threw: ${(error as Error).message}`);
            }
          }
        }
      },
    });
  }
  return found;
}
