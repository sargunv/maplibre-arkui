// Whether MapLibre may use the network: the app's connectivity mode, and the
// monitor of the device's default network that the automatic mode follows.

import { getNetworkStatus, NetworkStatus, setNetworkStatus } from '@maplibre/native-ffi';
import connection from '@ohos.net.connection';
import { BusinessError } from '@ohos.base';

import { logError } from './log';

/** How MapLibre decides whether it may use the network. */
export enum ConnectivityMode {
  /**
   * Follows the device's default network: online while one connects, offline
   * while none does. The library starts watching the network once the app
   * gets the default runtime, shows a map, takes a snapshot, listens to a
   * runtime's events, or sets a mode. Without
   * `ohos.permission.GET_NETWORK_INFO`, it can't watch the network, so MapLibre
   * stays online.
   */
  automatic,
  /** Online whatever the device's network. */
  forceOnline,
  /** Offline: maps use offline regions and the resources that they cached. */
  forceOffline,
}

let mode: ConnectivityMode = ConnectivityMode.automatic;
// The device's default network as the monitor last saw it: its ID while one
// connects, `undefined` while none does, and `null` until the monitor reads
// it. A `null` network is online, as FFI starts.
let defaultNet: number | undefined | null = null;
let monitor: Promise<boolean> | undefined = undefined;
// Kept so that its callbacks live as long as the app.
let watcher: connection.NetConnection | undefined = undefined;

/**
 * Sets how MapLibre decides whether it may use the network, for every runtime
 * of the app and its maps, snapshots, and offline downloads, as FFI's network
 * status does. The mode is `ConnectivityMode.automatic` until the app sets
 * another, and it applies at once.
 *
 * ```ets
 * // Save data on a metered connection: only cached tiles and offline regions.
 * setConnectivityMode(ConnectivityMode.forceOffline);
 * ```
 *
 * While MapLibre is offline, it starts no network requests, and the requests
 * that wait start once it's online again. Requests that have started may
 * finish, and a runtime's resource provider does its own networking.
 * `getNetworkStatus()` reads the status that the mode sets. Set the mode here
 * instead of calling FFI's `setNetworkStatus()`, which the automatic mode
 * would overwrite.
 */
export function setConnectivityMode(value: ConnectivityMode): void {
  mode = value;
  followConnectivity();
  applyNetworkStatus();
}

/** The connectivity mode that `setConnectivityMode()` set last. */
export function getConnectivityMode(): ConnectivityMode {
  return mode;
}

// Starts the monitor once, the first time the library uses a runtime or the
// app sets a mode, and keeps it for the app's life. It resolves with whether
// the monitor registered, which it doesn't without the permission.
export function followConnectivity(): Promise<boolean> {
  if (monitor === undefined) {
    monitor = startMonitor();
  }
  return monitor;
}

function startMonitor(): Promise<boolean> {
  if (!readDefaultNet()) {
    return Promise.resolve(false);
  }
  const created = connection.createNetConnection();
  watcher = created;
  created.on('netAvailable', (net: connection.NetHandle) => networkAvailable(net.netId));
  created.on('netLost', (net: connection.NetHandle) => networkLost(net.netId));
  return new Promise<boolean>((resolve: (registered: boolean) => void) => {
    created.register((error: BusinessError) => {
      const failed = error !== undefined && error !== null && error.code !== 0;
      if (failed) {
        logError(`can't follow the device's network: ${error.message}`);
      } else {
        // No callback reports a loss from before the registration.
        readDefaultNet();
      }
      resolve(!failed);
    });
  });
}

// Reads the device's default network, and returns whether it could. The
// permission is a normal one, which installs with the app, so a read that
// throws means the app didn't declare it.
function readDefaultNet(): boolean {
  try {
    networkChanged(connection.hasDefaultNetSync() ? connection.getDefaultNetSync().netId : undefined);
    return true;
  } catch (error) {
    return false;
  }
}

// The default network that `netId` names is connected. It replaces the one
// before, so that one's loss, which may come after, changes nothing.
export function networkAvailable(netId: number): void {
  networkChanged(netId);
}

// The network that `netId` names is lost. Only the default network's loss
// takes the device offline.
export function networkLost(netId: number): void {
  if (defaultNet === netId) {
    networkChanged(undefined);
  }
}

function networkChanged(netId: number | undefined): void {
  defaultNet = netId;
  applyNetworkStatus();
}

function applyNetworkStatus(): void {
  const offline = mode === ConnectivityMode.forceOffline ||
    (mode === ConnectivityMode.automatic && defaultNet === undefined);
  const status: NetworkStatus = offline ? NetworkStatus.offline : NetworkStatus.online;
  if (getNetworkStatus() !== status) {
    setNetworkStatus(status);
  }
}
