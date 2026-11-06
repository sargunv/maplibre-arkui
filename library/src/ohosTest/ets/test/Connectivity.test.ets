// The connectivity mode, and the automatic mode's following of the device's
// default network. The cases tell the monitor of made-up networks rather than
// change the device's, and give it back the device's network after.

import { afterEach, describe, expect, it } from '@ohos/hypium';
import { ConnectivityMode, getConnectivityMode, getNetworkStatus, NetworkStatus, setConnectivityMode } from '@maplibre/arkui';
import { followConnectivity, networkAvailable, networkLost } from '@maplibre/arkui/src/main/ets/connectivity';

import connection from '@ohos.net.connection';

import { settled } from './helpers';

// Networks that the device doesn't have.
const WIFI = 1000001;
const CELLULAR = 1000002;

export default function connectivityTest(): void {
  describe('Connectivity', () => {
    afterEach(() => {
      setConnectivityMode(ConnectivityMode.automatic);
      networkAvailable(connection.getDefaultNetSync().netId);
    });

    it('follows the device with the permission', 0, async () => {
      expect(await settled('the monitor registers', followConnectivity())).assertTrue();
      expect(getConnectivityMode()).assertEqual(ConnectivityMode.automatic);
      expect(connection.hasDefaultNetSync()).assertTrue();
      expect(getNetworkStatus()).assertEqual(NetworkStatus.online);
    });

    it('goes offline when the default network is lost', 0, async () => {
      networkAvailable(WIFI);
      expect(getNetworkStatus()).assertEqual(NetworkStatus.online);
      networkLost(WIFI);
      expect(getNetworkStatus()).assertEqual(NetworkStatus.offline);
      networkAvailable(CELLULAR);
      expect(getNetworkStatus()).assertEqual(NetworkStatus.online);
    });

    it('stays online when the network before the default one is lost', 0, async () => {
      networkAvailable(WIFI);
      networkAvailable(CELLULAR);
      networkLost(WIFI);
      expect(getNetworkStatus()).assertEqual(NetworkStatus.online);
      networkLost(CELLULAR);
      expect(getNetworkStatus()).assertEqual(NetworkStatus.offline);
    });

    it('forces a status whatever the network does', 0, async () => {
      networkAvailable(WIFI);
      setConnectivityMode(ConnectivityMode.forceOffline);
      expect(getConnectivityMode()).assertEqual(ConnectivityMode.forceOffline);
      expect(getNetworkStatus()).assertEqual(NetworkStatus.offline);
      networkAvailable(CELLULAR);
      expect(getNetworkStatus()).assertEqual(NetworkStatus.offline);

      networkLost(CELLULAR);
      setConnectivityMode(ConnectivityMode.forceOnline);
      expect(getNetworkStatus()).assertEqual(NetworkStatus.online);
      networkAvailable(WIFI);
      networkLost(WIFI);
      expect(getNetworkStatus()).assertEqual(NetworkStatus.online);
    });

    it('follows the network again once automatic', 0, async () => {
      setConnectivityMode(ConnectivityMode.forceOnline);
      networkAvailable(WIFI);
      networkLost(WIFI);
      setConnectivityMode(ConnectivityMode.automatic);
      expect(getNetworkStatus()).assertEqual(NetworkStatus.offline);

      setConnectivityMode(ConnectivityMode.forceOffline);
      networkAvailable(WIFI);
      setConnectivityMode(ConnectivityMode.automatic);
      expect(getNetworkStatus()).assertEqual(NetworkStatus.online);
    });
  });
}
