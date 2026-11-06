// The examples of the documentation site, which the demo builds, so they keep
// to the API. Each `// #region <name>` is an example that a page of docs/ cuts
// out by name, and the site build fails on a region that's missing. The
// demo's "Guide examples" page shows them in tabs.

import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import common from '@ohos.app.ability.common';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import { AppStorageV2 } from '@ohos.arkui.StateManagement';
import geoLocationManager from '@ohos.geoLocationManager';
import image from '@ohos.multimedia.image';
import sensor from '@ohos.sensor';
import util from '@ohos.util';

import {
  addRuntimeEventListener,
  CameraPosition,
  cameraToOptions,
  CameraTransitionOutcome,
  CameraUpdateMode,
  eq,
  FollowBearing,
  GeoJsonFeature,
  GeoJsonFeatureCollection,
  get,
  getDefaultRuntime,
  interpolate,
  LatLngBounds,
  linear,
  LogEvent,
  LogSeverity,
  LogSeverityFlag,
  MapCompass,
  MapContent,
  MapController,
  MapHandle,
  MapLibreMap,
  MapMarker,
  match,
  OfflineRegionDefinition,
  OfflineRegionDownloadState,
  PremultipliedRgba8Image,
  readPixelMap,
  RuntimeEvent,
  RuntimeEventFlag,
  RuntimeEventType,
  RuntimeHandle,
  setLogCallback,
  snapshot,
  StyleLayerInfo,
  UrlMatchFlag,
  zoom,
} from '@maplibre/arkui';

const STYLE = 'https://tiles.openfreemap.org/styles/liberty';
const API_KEY = 'not-a-real-key';

// Map content

// GeoJSON as an ArkTS literal: its declared type lets strict ArkTS accept it.
const PARIS: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: [
    {
      type: 'Feature', id: 1, geometry: { type: 'Point', coordinates: [2.2945, 48.8584] },
      properties: { 'name': 'Eiffel Tower', 'kind': 'monument' },
    },
    {
      type: 'Feature', id: 2, geometry: { type: 'Point', coordinates: [2.2885, 48.8622] },
      properties: { 'name': 'Palais de Chaillot', 'kind': 'museum' },
    },
  ],
};

// #region geojson
const LOUVRE: GeoJsonFeature = {
  type: 'Feature', id: 3, geometry: { type: 'Point', coordinates: [2.3376, 48.8606] },
  properties: { 'name': 'Louvre', 'kind': 'museum' },
};
// #endregion geojson

// Decodes an image from the app's resources/rawfile into the pixels a style
// takes.
function readImage(context: UIContext, rawfile: string): PremultipliedRgba8Image {
  const bytes = context.getHostContext()!.resourceManager.getRawFileContentSync(rawfile);
  const source = image.createImageSource(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  const pixelMap = source.createPixelMapSync();
  const pixels = readPixelMap(pixelMap);
  pixelMap.release();
  source.release();
  return pixels;
}

@ComponentV2
struct ContentExample {
  @Local places: GeoJsonFeatureCollection = PARIS;
  @Local color: string = '#1e88e5';
  @Local selected: string = 'Tap a place';
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.858, longitude: 2.315 }, zoom: 12 },
  });
  // #region content-image
  // Read once: the map compares images by reference.
  private pin: PremultipliedRgba8Image = readImage(this.getUIContext(), 'pin.png');
  // #endregion content-image

  // #region content
  @Computed
  get content(): MapContent {
    return {
      sources: [{ id: 'places', json: { 'type': 'geojson', 'data': this.places } }],
      layers: [
        {
          id: 'places', type: 'circle', source: 'places',
          paint: { 'circle-radius': 8, 'circle-color': match(get('kind'), [['museum', '#fb8c00']], this.color) },
          // Under the base style's labels.
          below: (layer: StyleLayerInfo) => layer.type === 'symbol',
        },
        {
          id: 'monuments', type: 'symbol', source: 'places', filter: eq(get('kind'), 'monument'),
          layout: { 'icon-image': 'pin', 'icon-anchor': 'bottom', 'icon-allow-overlap': true },
        },
      ],
      images: [{ id: 'pin', image: this.pin, options: { pixelRatio: 3 } }],
    };
  }
  // #endregion content

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // #region query-click
      MapLibreMap({ controller: this.controller, style: STYLE, content: this.content })
        .onClick((event: ClickEvent) => this.select(event.x, event.y))
      // #endregion query-click
      Column({ space: 8 }) {
        Text(this.selected)
        Row({ space: 8 }) {
          Button('Add the Louvre').onClick(() => {
            // A new value: the map doesn't see changes inside the one it has.
            // #region content-change
            this.places = { type: 'FeatureCollection', features: this.places.features.concat([LOUVRE]) };
            // #endregion content-change
          })
          Button('Color').onClick(() => {
            this.color = this.color === '#1e88e5' ? '#8e24aa' : '#1e88e5';
          })
        }
      }
      .margin({ bottom: 64 })
    }
  }

  // A click's point is in vp from the map's top-left corner, as queries take it.
  // #region query
  private async select(x: number, y: number): Promise<void> {
    const session = this.controller.renderSession;
    if (session === undefined) {
      return;
    }
    const hits = await session.queryRenderedFeatures({ kind: 'point', value: { x: x, y: y } },
      { layerIds: ['places', 'monuments'] });
    const feature = hits.length > 0 ? hits[0].feature as GeoJsonFeature : undefined;
    this.selected = feature === undefined ? 'Nothing here' : `${feature.properties?.['name']}`;
  }
  // #endregion query
}

// Ornaments, markers, the camera, and gestures

@ComponentV2
struct MarkerExample {
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8566, longitude: 2.3522 }, zoom: 11 },
  });

  build() {
    // #region marker
    MapLibreMap({ controller: this.controller, style: STYLE, scaleBarEnabled: true }) {
      MapMarker({ controller: this.controller, coordinate: { latitude: 48.8566, longitude: 2.3522 } }) {
        Text('Paris')
          .padding(6)
          .backgroundColor(Color.White)
      }
    }
    // #endregion marker
  }
}

@ComponentV2
struct CompassExample {
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8566, longitude: 2.3522 }, zoom: 11, bearing: 30 },
  });

  build() {
    // #region compass
    Stack({ alignContent: Alignment.TopStart }) {
      MapLibreMap({ controller: this.controller, style: STYLE, compassEnabled: false })
      MapCompass({ controller: this.controller, alwaysShown: true })
        .margin(16)
    }
    // #endregion compass
  }
}

const SWITZERLAND: LatLngBounds = {
  southwest: { latitude: 45.82, longitude: 5.96 },
  northeast: { latitude: 47.81, longitude: 10.49 },
};

@ComponentV2
struct CameraExample {
  @Local moving: boolean = false;
  @Local message: string = '';
  private controller: MapController = new MapController({
    camera: { center: { latitude: 46.8, longitude: 8.2 }, zoom: 5 },
  });

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // #region gestures
      MapLibreMap({
        controller: this.controller,
        style: STYLE,
        gestures: { rotate: false },
        onGestureStart: () => {
          this.moving = true;
        },
        onGestureEnd: () => {
          this.moving = false;
        },
      })
      // #endregion gestures
      Column({ space: 8 }) {
        // `camera` is observable, so this text changes as the camera comes to rest.
        // #region camera-observable
        Text(this.moving ? 'Moving' : `Zoom ${this.controller.camera?.zoom.toFixed(1) ?? '…'}`)
        // #endregion camera-observable
        Text(this.message)
        Row({ space: 8 }) {
          Button('Fit Switzerland').onClick(() => this.fitSwitzerland())
          Button('Look ahead').onClick(() => this.lookAhead())
        }
      }
      .margin({ bottom: 64 })
    }
  }

  private fitSwitzerland(): void {
    // #region camera-fit
    this.controller.fitCameraToLatLngBounds(SWITZERLAND, {
      mode: CameraUpdateMode.ease,
      // Space around Switzerland for this fit only.
      fitPadding: { top: 24, left: 24, bottom: 24, right: 24 },
      animation: { durationMs: 1000 },
    }).then((outcome: CameraTransitionOutcome) => {
      // A gesture or a later move can stop it first.
      this.message = outcome === CameraTransitionOutcome.completed ? 'Fitted' : 'Stopped';
    }).catch((error: Error) => {
      // No map is on screen, or the map rejected the move.
      this.message = error.message;
    });
    // #endregion camera-fit
  }

  private lookAhead(): void {
    // #region camera-padding
    // The camera centers in the map below its top 200 vp, which shows more of
    // what lies ahead. The padding stays until a move or a fit changes it.
    this.controller.updateCamera({
      mode: CameraUpdateMode.ease,
      camera: { padding: { top: 200, left: 0, bottom: 0, right: 0 } },
      animation: { durationMs: 500 },
    }).catch((error: Error) => {
      this.message = error.message;
    });
    // #endregion camera-padding
  }
}

@ComponentV2
struct InsetsExample {
  // #region viewport-insets
  @Local panelHeight: number = 0;
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
  });

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // The ornaments stay above the panel, and the camera centers there too.
      MapLibreMap({
        controller: this.controller,
        style: STYLE,
        scaleBarEnabled: true,
        zoomButtonsEnabled: true,
        viewportInsets: { top: 0, left: 0, bottom: this.panelHeight, right: 0 },
      })
      Column() {
        Text('A panel over the map')
      }
      .width('100%')
      .height(200)
      .backgroundColor(Color.White)
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.panelHeight = newArea.height as number;
      })
    }
  }
  // #endregion viewport-insets
}

// Saving the camera

// #region save-camera
const SAVED_CAMERA = 'camera';

// The system saves the ability's state as it takes the app to the background,
// and hands it back if it ends the process and the user returns.
export class CameraSavingAbility extends UIAbility {
  onCreate(want: Want): void {
    this.context.setRestoreEnabled(true);
    const saved = want.parameters?.[SAVED_CAMERA];
    if (typeof saved === 'string') {
      const camera = JSON.parse(saved) as CameraPosition;
      AppStorageV2.connect(MapController, () => new MapController({ camera: cameraToOptions(camera) }));
    }
  }

  onSaveState(reason: AbilityConstant.StateType, wantParam: Record<string, Object>): AbilityConstant.OnSaveResult {
    const camera = AppStorageV2.connect(MapController)?.getCamera();
    if (camera !== undefined) {
      wantParam[SAVED_CAMERA] = JSON.stringify(camera);
    }
    return AbilityConstant.OnSaveResult.ALL_AGREE;
  }
}

// The page shows the controller in AppStorageV2, which the ability restored or
// the page creates.
@ComponentV2
struct SavedCameraExample {
  private controller: MapController = AppStorageV2.connect(MapController, () => new MapController({
    camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
  }))!;

  build() {
    MapLibreMap({ controller: this.controller, style: STYLE })
  }
}
// #endregion save-camera

// The user's location

const PERMISSIONS: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];

@ComponentV2
struct LocationExample {
  // #region location
  @Local location: geoLocationManager.Location | undefined = undefined;
  private controller: MapController = new MapController();
  private listening: boolean = false;
  private gone: boolean = false;
  private onLocation = (location: geoLocationManager.Location): void => {
    this.location = location;
  };

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MapLibreMap({ controller: this.controller, style: STYLE, userLocation: this.location })
      Button(this.controller.followingUserLocation ? 'Following' : 'Locate me')
        .margin(64)
        .onClick(() => {
          this.controller.followUserLocation({ zoom: 16, bearing: FollowBearing.course });
          this.startUpdates().catch((error: Error) => console.error(error.message));
        })
    }
  }
  // #endregion location

  // #region location-updates
  aboutToDisappear(): void {
    this.gone = true;
    if (!this.listening) {
      return;
    }
    try {
      geoLocationManager.off('locationChange', this.onLocation);
    } catch (error) {
      // Location Kit throws once the user takes the permission back.
    }
  }

  private async startUpdates(): Promise<void> {
    if (this.listening) {
      return;
    }
    this.listening = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, PERMISSIONS);
      const granted = result.authResults.some(
        (status: number) => status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
      // The page may have gone while the user answered.
      if (granted && !this.gone) {
        const request: geoLocationManager.ContinuousLocationRequest = {
          interval: 1,
          locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION,
        };
        geoLocationManager.on('locationChange', request, this.onLocation);
        return;
      }
    } catch (error) {
      console.error((error as Error).message);
    }
    // Without updates, a later tap tries again.
    this.listening = false;
    this.controller.stopFollowingUserLocation();
  }
  // #endregion location-updates
}

@ComponentV2
struct HeadingExample {
  @Param location: geoLocationManager.Location | undefined = undefined;
  // #region heading
  @Local heading: number | undefined = undefined;
  private controller: MapController = new MapController();
  private onOrientation = (data: sensor.OrientationResponse): void => {
    // Degrees clockwise from magnetic north.
    this.heading = data.alpha;
  };

  aboutToAppear(): void {
    try {
      sensor.on(sensor.SensorId.ORIENTATION, this.onOrientation, { interval: 'ui' });
    } catch (error) {
      // Without a compass, the arrow shows the course.
      console.error((error as Error).message);
    }
  }

  aboutToDisappear(): void {
    try {
      sensor.off(sensor.SensorId.ORIENTATION, this.onOrientation);
    } catch (error) {
      // It throws if on() did.
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MapLibreMap({
        controller: this.controller,
        style: STYLE,
        userLocation: this.location,
        userHeading: this.heading,
      })
      Button('Face up')
        .margin(64)
        .onClick(() => this.controller.followUserLocation({ zoom: 16, bearing: FollowBearing.heading }))
    }
  }
  // #endregion heading
}

// Snapshots

@ComponentV2
struct SnapshotExample {
  // #region snapshot
  @Local preview: image.PixelMap | undefined = undefined;
  private disappeared: boolean = false;

  aboutToAppear(): void {
    snapshot({
      style: STYLE,
      width: 320,
      height: 200,
      camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
    }).then((preview: image.PixelMap) => {
      if (this.disappeared) {
        preview.release();
      } else {
        this.preview = preview;
      }
    }).catch((error: Error) => console.error(error.message));
  }

  aboutToDisappear(): void {
    this.disappeared = true;
    this.preview?.release();
  }
  // #endregion snapshot

  build() {
    Column() {
      if (this.preview !== undefined) {
        Image(this.preview)
          .width(320)
          .height(200)
      }
    }
    .width('100%')
  }
}

// An image of what a MapLibreMap shows: its style, its content, and its camera.
// #region snapshot-of
function snapshotOf(controller: MapController, content: MapContent): Promise<image.PixelMap> {
  const camera = controller.getCamera();
  return snapshot({
    style: STYLE,
    content: content,
    width: 320,
    height: 200,
    camera: camera === undefined ? undefined : cameraToOptions(camera),
  });
}
// #endregion snapshot-of

// Expressions and the style API

// #region expressions
async function styleWithExpressions(map: MapHandle): Promise<void> {
  const radius = interpolate(linear(), zoom(), [[0, 2], [12, get('size')]]);
  const color = match(get('kind'), [['park', '#8c8'], [['lake', 'river'], '#88c']], '#ccc');
  await map.setStyleLayerProperty('places', 'circle-radius', radius);
  await map.setStyleLayerProperty('places', 'circle-color', color);
}
// #endregion expressions

// Requests, offline regions, and logs

// #region resource-transform
async function useApiKey(): Promise<void> {
  const runtime = await getDefaultRuntime();
  await runtime.setResourceTransform({
    rules: [{
      flags: UrlMatchFlag.glob,
      url: 'https://tiles.example.com/**',
      parameters: [{ name: 'key', value: API_KEY }],
    }],
  });
}
// #endregion resource-transform

const PARIS_REGION: OfflineRegionDefinition = {
  kind: 'tilePyramid',
  value: {
    styleUrl: STYLE,
    bounds: { southwest: { latitude: 48.81, longitude: 2.22 }, northeast: { latitude: 48.91, longitude: 2.42 } },
    minZoom: 10,
    maxZoom: 14,
    pixelRatio: 2,
    includeIdeographs: false,
  },
};

async function downloadParis(runtime: RuntimeHandle): Promise<void> {
  // #region offline
  const region = await runtime.createOfflineRegion(PARIS_REGION, new util.TextEncoder().encodeInto('Paris'));
  addRuntimeEventListener(runtime, (event: RuntimeEvent) => {
    const payload = event.payload;
    if (payload.kind === 'offlineRegionStatus' && payload.value.regionId === region.id) {
      const status = payload.value.status;
      console.info(`Paris: ${status.completedResourceCount} of ${status.requiredResourceCount} resources`);
    }
  });
  await runtime.setOfflineRegionObserved(region.id, RuntimeEventFlag.offlineRegionStatusChanged);
  await runtime.setOfflineRegionDownloadState(region.id, OfflineRegionDownloadState.active);
  // #endregion offline
}

function watchMissingImages(runtime: RuntimeHandle): void {
  // #region map-events
  addRuntimeEventListener(runtime, (event: RuntimeEvent) => {
    const payload = event.payload;
    if (event.type === RuntimeEventType.mapStyleImageMissing && payload.kind === 'styleImage') {
      console.warn(`The style needs the image ${payload.value.imageId}`);
    }
  }, RuntimeEventFlag.mapStyleImageMissing);
  // #endregion map-events
}

function takeLogs(): void {
  // #region logs
  setLogCallback({
    callback: (severity: LogSeverity, event: LogEvent, code: bigint, message: string) => {
      console.info(`MapLibre (${event}): ${message}`);
    },
    // Errors still go to hilog too.
    platformSeverities: LogSeverityFlag.error,
  });
  // #endregion logs
}

// Each example in a tab. The functions only need to compile.
@ComponentV2
export struct DocExamples {
  build() {
    NavDestination() {
      Tabs() {
        TabContent() {
          ContentExample()
        }.tabBar('Content')
        TabContent() {
          MarkerExample()
        }.tabBar('Marker')
        TabContent() {
          CompassExample()
        }.tabBar('Compass')
        TabContent() {
          CameraExample()
        }.tabBar('Camera')
        TabContent() {
          InsetsExample()
        }.tabBar('Insets')
        TabContent() {
          SavedCameraExample()
        }.tabBar('Saved camera')
        TabContent() {
          LocationExample()
        }.tabBar('Location')
        TabContent() {
          HeadingExample()
        }.tabBar('Heading')
        TabContent() {
          SnapshotExample()
        }.tabBar('Snapshot')
      }
      .barMode(BarMode.Scrollable)
    }
    .title('Guide examples')
  }
}

// Keeps the functions that no tab calls from being unused.
export const COMPILED_EXAMPLES: Object[] = [snapshotOf, styleWithExpressions, useApiKey, downloadParis, watchMissingImages,
  takeLogs];
