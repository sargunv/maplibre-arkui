// The commands that the style API and its handles send, and the IDs that the
// library reserves.

import { CommandCompletion } from '@maplibre/native-ffi';

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

function failed(what: string, error: Error): Error {
  return new Error(`Style: ${what} failed: ${error.message}`);
}

// Sends a write, which resolves true once the map applies it. A write that
// fails once `holds` no longer does resolves false; another failure rejects
// with what failed.
export function write(holds: () => boolean, what: string, send: () => Promise<CommandCompletion>): Promise<boolean> {
  let sent: Promise<CommandCompletion>;
  try {
    sent = send();
  } catch (error) {
    return Promise.reject(failed(what, error as Error));
  }
  return sent.then((): boolean => true, (error: Error): boolean => {
    if (!holds()) {
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
