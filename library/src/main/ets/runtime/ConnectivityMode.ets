/**
 * How MapLibre decides whether it may use the network; see
 * `MapRuntime.setConnectivityMode()`.
 *
 * Values may be added in later releases; give a `switch` over it a `default`
 * branch.
 */
export enum ConnectivityMode {
  /**
   * Follows the device's default network: online while one connects, offline
   * while none does. The library starts watching the network once a runtime
   * opens or the app sets a mode. Without `ohos.permission.GET_NETWORK_INFO`,
   * it can't watch the network, so MapLibre stays online.
   */
  AUTOMATIC,
  /** Online whatever the device's network. */
  FORCE_ONLINE,
  /** Offline: maps use offline regions and the resources that they cached. */
  FORCE_OFFLINE,
}
