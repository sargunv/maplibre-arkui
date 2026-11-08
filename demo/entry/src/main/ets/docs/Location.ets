// Examples for the "Show the user's location" guide.

import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import geoLocationManager from '@ohos.geoLocationManager';
import sensor from '@ohos.sensor';

import { FollowBearing, LayerSummary, MapController, MaplibreMap } from '@maplibre/arkui';

import { STYLE } from './Common';

const PERMISSIONS: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];

@ComponentV2
export struct LocationExample {
  // #region location
  @Local location: geoLocationManager.Location | undefined = undefined;
  private onLocation = (location: geoLocationManager.Location): void => {
    this.location = location;
  };

  build() {
    MaplibreMap({ style: STYLE, userLocation: this.location })
  }
  // #endregion location

  aboutToAppear(): void {
    this.startUpdates().catch((error: Error) => console.error(error.message));
  }

  aboutToDisappear(): void {
    try {
      geoLocationManager.off('locationChange', this.onLocation);
    } catch (error) {
      console.error((error as Error).message);
    }
  }

  private async startUpdates(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, PERMISSIONS);
    if (result.authResults.some((status: number) => status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)) {
      const request: geoLocationManager.ContinuousLocationRequest = {
        interval: 1,
        locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION,
      };
      geoLocationManager.on('locationChange', request, this.onLocation);
    }
  }
}

@ComponentV2
export struct FollowExample {
  @Param location: geoLocationManager.Location | undefined = undefined;
  // #region follow
  private controller: MapController = new MapController();

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MaplibreMap({ style: STYLE, controller: this.controller, userLocation: this.location })
      if (!this.controller.followingUserLocation) {
        Button('Locate me')
          .margin(64)
          .onClick(() => this.controller.followUserLocation({ zoom: 16 }))
      }
    }
  }
  // #endregion follow
}

@ComponentV2
export struct HeadingExample {
  @Param location: geoLocationManager.Location | undefined = undefined;
  @Local heading: number | undefined = undefined;
  private controller: MapController = new MapController();
  private onOrientation = (data: sensor.OrientationResponse): void => {
    this.heading = data.alpha;
  };

  aboutToAppear(): void {
    try {
      sensor.on(sensor.SensorId.ORIENTATION, this.onOrientation, { interval: 'ui' });
    } catch (error) {
      console.error((error as Error).message);
    }
  }

  aboutToDisappear(): void {
    try {
      sensor.off(sensor.SensorId.ORIENTATION, this.onOrientation);
    } catch (error) {
      console.error((error as Error).message);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // #region heading
      MaplibreMap({
        style: STYLE,
        controller: this.controller,
        userLocation: this.location,
        userHeading: this.heading,
      })
      Button('Face my direction')
        .onClick(() => this.controller.followUserLocation({ zoom: 16, bearing: FollowBearing.HEADING }))
      // #endregion heading
    }
  }
}

@ComponentV2
export struct IndicatorExample {
  @Param location: geoLocationManager.Location | undefined = undefined;

  build() {
    // #region indicator
    MaplibreMap({
      style: STYLE,
      userLocation: this.location,
      userLocationIndicator: {
        color: '#e53935',
        below: (layer: LayerSummary) => layer.type === 'symbol',
      },
    })
    // #endregion indicator
  }
}
