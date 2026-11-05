// What the maps of an app share: the default runtime, the frame pacer, and the
// event handler of each runtime.

import {
  FramePacerHandle,
  MapHandle,
  ohosFramePacerCreate,
  RuntimeEvent,
  RuntimeHandle,
} from '@maplibre/native-ffi';

type MapEventListener = (event: RuntimeEvent) => void;

let defaultRuntime: Promise<RuntimeHandle> | undefined = undefined;
let framePacer: FramePacerHandle | undefined = undefined;
// The listener of each map, by runtime ID and then by map ID.
const listeners: Map<bigint, Map<bigint, MapEventListener>> = new Map();

/**
 * The runtime that every `MapLibreMap` uses unless the app passes its own. The
 * library creates it on first use and keeps it for the app's life.
 *
 * The library sets the runtime's event handler, so don't replace it.
 */
export function getDefaultRuntime(): Promise<RuntimeHandle> {
  if (defaultRuntime === undefined) {
    const created = RuntimeHandle.create();
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

// One pacer serves every session. It follows the display's VSync, so the
// sessions need no redraw wake.
export function getFramePacer(): FramePacerHandle {
  if (framePacer === undefined) {
    framePacer = ohosFramePacerCreate();
  }
  return framePacer;
}

// A runtime has one event handler for all its maps, so the first map on a
// runtime sets a handler that passes each event to the map that raised it.
export function listenToMap(runtime: RuntimeHandle, map: MapHandle, listener: MapEventListener): void {
  let maps = listeners.get(runtime.id);
  if (maps === undefined) {
    const byMap: Map<bigint, MapEventListener> = new Map();
    maps = byMap;
    listeners.set(runtime.id, byMap);
    runtime.discarding.setEventHandler({
      callback: (events: readonly RuntimeEvent[]) => {
        for (const event of events) {
          byMap.get(event.source)?.(event);
        }
      },
    });
  }
  maps.set(map.id, listener);
}

export function stopListeningToMap(runtime: RuntimeHandle, map: MapHandle): void {
  listeners.get(runtime.id)?.delete(map.id);
}
