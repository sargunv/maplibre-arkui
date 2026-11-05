import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { BusinessError } from '@ohos.base';
import common from '@ohos.app.ability.common';
import geoLocationManager from '@ohos.geoLocationManager';

import { MapController, MapLibreMap } from '@maplibre/arkui';

import { LIBERTY } from './TwoMaps';

// Location Kit asks for both: the user can grant only the approximate one.
const PERMISSIONS: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];

// The simulated walk: a loop around the Champ de Mars, once in two minutes.
const CENTER_LATITUDE = 48.8556;
const CENTER_LONGITUDE = 2.2986;
const RADIUS_M = 350;
const SPEED_M_S = 2 * Math.PI * RADIUS_M / 120;
const METERS_PER_DEGREE = 111320;

// The location `seconds` into the walk, as Location Kit reports one.
function simulatedLocation(seconds: number): geoLocationManager.Location {
  const angle = 2 * Math.PI * seconds / 120;
  const north = RADIUS_M * Math.cos(angle);
  const east = RADIUS_M * Math.sin(angle);
  return {
    latitude: CENTER_LATITUDE + north / METERS_PER_DEGREE,
    longitude: CENTER_LONGITUDE + east / (METERS_PER_DEGREE * Math.cos(CENTER_LATITUDE * Math.PI / 180)),
    altitude: 0,
    // Between 10 and 40 m, as a real fix varies.
    accuracy: 25 + 15 * Math.sin(seconds / 7),
    speed: SPEED_M_S,
    // Clockwise around the loop, so the course is 90° past the angle.
    direction: (angle * 180 / Math.PI + 90) % 360,
    timeStamp: Date.now(),
    timeSinceBoot: 0,
  };
}

// A map that shows where the user is, from Location Kit or a simulated walk,
// and follows it until a gesture moves the map.
@ComponentV2
export struct LocationDemo {
  @Local location: geoLocationManager.Location | undefined = undefined;
  @Local simulating: boolean = false;
  @Local course: boolean = false;
  @Local message: string = '';
  private map: MapController = new MapController({
    camera: { center: { latitude: CENTER_LATITUDE, longitude: CENTER_LONGITUDE }, zoom: 15 },
  });
  private listening: boolean = false;
  private timer: number = -1;
  private seconds: number = 0;
  private readonly onLocation = (location: geoLocationManager.Location): void => {
    if (!this.simulating) {
      this.location = location;
    }
  };

  aboutToDisappear(): void {
    this.stopSimulating();
    if (this.listening) {
      try {
        geoLocationManager.off('locationChange', this.onLocation);
      } catch (error) {
        console.error(`Location Kit: ${(error as BusinessError).message}`);
      }
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        MapLibreMap({
          controller: this.map,
          style: LIBERTY,
          userLocation: this.location,
          onMapError: (error: Error) => {
            this.message = error.message;
          },
        })
        Column({ space: 8 }) {
          Text(this.describe())
            .fontSize(14)
          if (this.message !== '') {
            Text(this.message)
              .fontSize(14)
          }
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            Button(this.map.followingUserLocation ? 'Following' : 'Locate me')
              .margin(4)
              .onClick(() => this.locate())
            Toggle({ type: ToggleType.Button, isOn: this.course }) {
              Text('Turn with course').fontSize(14).padding({ left: 12, right: 12 })
            }
            .margin(4)
            .onChange((isOn: boolean) => {
              this.course = isOn;
              if (this.map.followingUserLocation) {
                this.map.followUserLocation({ course: isOn });
              }
            })
            Toggle({ type: ToggleType.Button, isOn: this.simulating }) {
              Text('Simulate a walk').fontSize(14).padding({ left: 12, right: 12 })
            }
            .margin(4)
            .onChange((isOn: boolean) => isOn ? this.startSimulating() : this.stopSimulating())
          }
        }
        .padding(12)
        .margin({ left: 12, right: 12, bottom: 32 })
        .borderRadius(16)
        .backgroundColor('#e6ffffff')
      }
      .width('100%')
      .height('100%')
    }
    .title('Location')
  }

  private describe(): string {
    const location = this.location;
    if (location === undefined) {
      return 'No location yet';
    }
    const following = this.map.followingUserLocation ? 'following' : 'not following';
    return `${location.latitude.toFixed(5)}, ${location.longitude.toFixed(5)} ` +
      `± ${location.accuracy.toFixed(0)} m, ${following}`;
  }

  // Follows the location, and asks for Location Kit's first.
  private locate(): void {
    this.map.followUserLocation({ zoom: 16, course: this.course });
    if (!this.simulating) {
      this.listen().catch((error: BusinessError) => {
        this.map.stopFollowingUserLocation();
        this.message = `Location Kit: ${error.message} (${error.code})`;
      });
    }
  }

  // The app, not the library, asks for the permission and the updates.
  private async listen(): Promise<void> {
    if (this.listening) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, PERMISSIONS);
    if (!result.authResults.some((status: number) => status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED)) {
      this.map.stopFollowingUserLocation();
      this.message = 'Location permission denied';
      return;
    }
    const request: geoLocationManager.ContinuousLocationRequest = {
      interval: 1,
      locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION,
    };
    geoLocationManager.on('locationChange', request, this.onLocation);
    this.listening = true;
    this.message = 'Waiting for Location Kit…';
  }

  private startSimulating(): void {
    this.simulating = true;
    this.message = '';
    this.location = simulatedLocation(this.seconds);
    this.timer = setInterval(() => {
      this.seconds++;
      this.location = simulatedLocation(this.seconds);
    }, 1000);
  }

  private stopSimulating(): void {
    this.simulating = false;
    clearInterval(this.timer);
  }
}
