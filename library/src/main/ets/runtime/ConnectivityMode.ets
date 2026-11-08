/**
 * When MapLibre may use the network.
 *
 * Values may be added in later releases; give a `switch` over it a `default`
 * branch.
 */
export enum ConnectivityMode {
  /**
   * Online while the device has a default network, and offline while it has
   * none. Without `ohos.permission.GET_NETWORK_INFO`, MapLibre is always
   * online.
   */
  AUTOMATIC,
  /** Always online, whatever the device's network. */
  FORCE_ONLINE,
  /**
   * Always offline: maps show what the cache, offline regions, and resource
   * providers hold.
   */
  FORCE_OFFLINE,
}
