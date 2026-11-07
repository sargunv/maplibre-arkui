import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { BusinessError } from '@ohos.base';
import common from '@ohos.app.ability.common';
import geoLocationManager from '@ohos.geoLocationManager';
import sensor from '@ohos.sensor';

import { FollowBearing, MapController, MapError, MaplibreMap, UserLocationIndicatorOptions } from '@maplibre/arkui';

import { LIBERTY, PANEL } from './common';

// Location Kit asks for both: the user can grant only the approximate one.
const PERMISSIONS: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];

// The simulated walk: a loop around the Champ de Mars, once in two minutes.
const CENTER_LATITUDE = 48.8556;
const CENTER_LONGITUDE = 2.2986;
const RADIUS_M = 350;
const SPEED_M_S = 2 * Math.PI * RADIUS_M / 120;
const METERS_PER_DEGREE = 111320;

// The course `seconds` into the walk: clockwise around the loop, so 90° past
// the angle from the center.
function simulatedCourse(seconds: number): number {
  return (360 * seconds / 120 + 90) % 360;
}

// The heading `seconds` into the walk, as the walker looks from side to side.
function simulatedHeading(seconds: number): number {
  return (simulatedCourse(seconds) + 60 * Math.sin(2 * Math.PI * seconds / 12) + 360) % 360;
}

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
    direction: simulatedCourse(seconds),
    timeStamp: Date.now(),
    timeSinceBoot: 0,
  };
}

// The camera's bearing while it follows, by the label of its button.
const BEARINGS: (FollowBearing | undefined)[] = [undefined, FollowBearing.course, FollowBearing.heading];
const BEARING_LABELS: string[] = ['Keep the bearing', 'Turn with course', 'Turn with heading'];

// The restyled indicator: red, without a shadow, under the style's labels.
const RED_INDICATOR: UserLocationIndicatorOptions = {
  color: '#e53935',
  accuracyColor: 'rgba(229, 57, 53, 0.15)',
  accuracyBorderColor: 'rgba(229, 57, 53, 0.5)',
  shadowImage: '',
  below: 'waterway_line_label',
};

// A map that shows where the user is and where they face, from Location Kit
// and the compass or a simulated walk, and follows it until the user pans.
// Zooming and rotating keep following.
@ComponentV2
export struct LocationDemo {
  @Local location: geoLocationManager.Location | undefined = undefined;
  @Local simulating: boolean = false;
  @Local heading: number | undefined = undefined;
  @Local compass: boolean = false;
  // The index in BEARINGS of how the camera turns.
  @Local bearing: number = 0;
  @Local message: string = '';
  @Local red: boolean = false;
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
  private readonly onOrientation = (data: sensor.OrientationResponse): void => {
    this.heading = data.alpha;
  };

  aboutToDisappear(): void {
    this.stopSimulating();
    this.stopCompass();
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
        MaplibreMap({
          controller: this.map,
          style: LIBERTY,
          userLocation: this.location,
          userHeading: this.heading,
          userLocationIndicator: this.red ? RED_INDICATOR : {},
          interactions: { pan: { onStart: () => this.map.stopFollowingUserLocation() } },
          onError: (error: MapError) => {
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
            Button(BEARING_LABELS[this.bearing])
              .margin(4)
              .onClick(() => {
                this.bearing = (this.bearing + 1) % BEARINGS.length;
                if (this.map.followingUserLocation) {
                  this.map.followUserLocation({ bearing: BEARINGS[this.bearing] });
                }
              })
            // A button, as a toggle would stay on when the compass fails.
            Button(this.compass ? 'Stop the compass' : 'Use the compass')
              .margin(4)
              .onClick(() => this.compass ? this.stopCompass() : this.startCompass())
            Toggle({ type: ToggleType.Button, isOn: this.simulating }) {
              Text('Simulate a walk').fontSize(14).padding({ left: 12, right: 12 })
            }
            .margin(4)
            .onChange((isOn: boolean) => isOn ? this.startSimulating() : this.stopSimulating())
            Toggle({ type: ToggleType.Button, isOn: this.red }) {
              Text('Red, under labels').fontSize(14).padding({ left: 12, right: 12 })
            }
            .margin(4)
            .onChange((isOn: boolean) => {
              this.red = isOn;
            })
          }
        }
        .attributeModifier(PANEL)
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
    const heading = this.heading !== undefined ? `, facing ${this.heading.toFixed(0)}°` : '';
    return `${location.latitude.toFixed(5)}, ${location.longitude.toFixed(5)} ` +
      `± ${location.accuracy.toFixed(0)} m${heading}, ${following}`;
  }

  // Follows the location, and asks for Location Kit's first.
  private locate(): void {
    this.map.followUserLocation({ zoom: 16, bearing: BEARINGS[this.bearing] });
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

  // The compass needs no permission. The emulator has none, so on() throws.
  private startCompass(): void {
    this.stopSimulating();
    try {
      sensor.on(sensor.SensorId.ORIENTATION, this.onOrientation, { interval: 'ui' });
      this.compass = true;
    } catch (error) {
      this.compass = false;
      this.message = `Compass: ${(error as BusinessError).message}`;
    }
  }

  private stopCompass(): void {
    if (!this.compass) {
      return;
    }
    this.compass = false;
    this.heading = undefined;
    try {
      sensor.off(sensor.SensorId.ORIENTATION, this.onOrientation);
    } catch (error) {
      console.error(`Compass: ${(error as BusinessError).message}`);
    }
  }

  // The walk simulates the heading too, in place of the compass.
  private startSimulating(): void {
    this.stopCompass();
    this.simulating = true;
    this.message = '';
    this.simulate();
    this.timer = setInterval(() => {
      this.seconds++;
      this.simulate();
    }, 1000);
  }

  private simulate(): void {
    this.location = simulatedLocation(this.seconds);
    this.heading = simulatedHeading(this.seconds);
  }

  private stopSimulating(): void {
    if (this.simulating) {
      this.heading = undefined;
    }
    this.simulating = false;
    clearInterval(this.timer);
  }
}
