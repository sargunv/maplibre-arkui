// The commands that the style API and its handles send, and the IDs that the
// library reserves.

import { CommandCompletion, MaplibreError, Status } from '@maplibre/native-ffi';

// The library's IDs start with this, and its global state names with it and a
// colon.
export const RESERVED = 'maplibre-arkui';

export function reservedId(id: string): boolean {
  return id.startsWith(RESERVED);
}

export function reservedName(name: string): boolean {
  return name.startsWith(`${RESERVED}:`);
}

export function checkId(kind: string, id: string): void {
  if (reservedId(id)) {
    throw new Error(`The library owns the ${kind}s whose IDs start with ${RESERVED}: ${id}`);
  }
}

export function checkOwned(owned: boolean, kind: string, id: string): void {
  if (owned) {
    throw new Error(`The map's content has the ${kind} ${id}, so change it in the content instead`);
  }
}

// The value that a write of a property sends: MapLibre Native takes no null
// for a transition, but an empty one is its default.
export function propertyValue(name: string, value: Object | null): Object | null {
  const empty: Record<string, Object> = {};
  return value === null && name.endsWith('-transition') ? empty : value;
}

function failed(what: string, error: Error): Error {
  return new Error(`Style: ${what} failed: ${error.message}`);
}

// Whether the map failed a command with `status`.
export function failedWith(error: Error, status: Status): boolean {
  return error instanceof MaplibreError && (error as MaplibreError).status === status;
}

// Whether the map cancelled a command because a newer one replaced it, as
// newer GeoJSON data does.
export function replaced(error: Error): boolean {
  return failedWith(error, Status.cancelled);
}

// Sends a write, which resolves true once the map applies it. A write that
// fails once `holds` no longer does, or with a failure that `declined` takes,
// resolves false; another failure rejects with what failed.
export function write(holds: () => boolean, what: string, send: () => Promise<CommandCompletion>,
  declined: (error: Error) => boolean = (): boolean => false): Promise<boolean> {
  let sent: Promise<CommandCompletion>;
  try {
    sent = send();
  } catch (error) {
    return Promise.reject(failed(what, error as Error));
  }
  return sent.then((): boolean => true, (error: Error): boolean => {
    if (!holds() || declined(error)) {
      return false;
    }
    throw failed(what, error);
  });
}

// Sends a read, which resolves what `then` makes of the answer, or undefined
// once `holds` no longer does. A failure rejects as a write's does.
export function read<T, R>(holds: () => boolean, what: string, send: () => Promise<T>,
  then: (value: T) => R | undefined): Promise<R | undefined> {
  let sent: Promise<T>;
  try {
    sent = send();
  } catch (error) {
    return Promise.reject(failed(what, error as Error));
  }
  return sent.then((value: T): R | undefined => holds() ? then(value) : undefined,
    (error: Error): R | undefined => {
      if (!holds()) {
        return undefined;
      }
      throw failed(what, error);
    });
}
