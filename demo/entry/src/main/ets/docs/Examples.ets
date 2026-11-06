// The examples of README.md and library/README.md, which the demo builds, so
// they keep to the API. scripts/check-doc-examples.sh checks that each `ets`
// block of those files is in this file or QuickStart.ets, line for line, and
// the build checks that they compile. The demo's "README examples" page shows
// them in tabs.

import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import geoLocationManager from '@ohos.geoLocationManager';
import image from '@ohos.multimedia.image';
import util from '@ohos.util';

import {
  addRuntimeEventListener,
  cameraToOptions,
  CameraTransitionOutcome,
  CameraUpdateMode,
  eq,
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

const LOUVRE: GeoJsonFeature = {
  type: 'Feature', id: 3, geometry: { type: 'Point', coordinates: [2.3376, 48.8606] },
  properties: { 'name': 'Louvre', 'kind': 'museum' },
};

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
  // Read once: the map compares images by reference.
  private pin: PremultipliedRgba8Image = readImage(this.getUIContext(), 'pin.png');

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

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MapLibreMap({ controller: this.controller, style: STYLE, content: this.content })
        .onClick((event: ClickEvent) => this.select(event.x, event.y))
      Column({ space: 8 }) {
        Text(this.selected)
        Row({ space: 8 }) {
          Button('Add the Louvre').onClick(() => {
            // A new value: the map doesn't see changes inside the one it has.
            this.places = { type: 'FeatureCollection', features: this.places.features.concat([LOUVRE]) };
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
}

// Ornaments, markers, the camera, and gestures

@ComponentV2
struct MarkerExample {
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8566, longitude: 2.3522 }, zoom: 11 },
  });

  build() {
    MapLibreMap({ controller: this.controller, style: STYLE, scaleBarEnabled: true }) {
      MapMarker({ controller: this.controller, coordinate: { latitude: 48.8566, longitude: 2.3522 } }) {
        Text('Paris')
          .padding(6)
          .backgroundColor(Color.White)
      }
    }
  }
}

@ComponentV2
struct CompassExample {
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8566, longitude: 2.3522 }, zoom: 11, bearing: 30 },
  });

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      MapLibreMap({ controller: this.controller, style: STYLE, compassEnabled: false })
      MapCompass({ controller: this.controller, alwaysShown: true })
        .margin(16)
    }
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
      Column({ space: 8 }) {
        // `camera` is observable, so this text changes as the camera comes to rest.
        Text(this.moving ? 'Moving' : `Zoom ${this.controller.camera?.zoom.toFixed(1) ?? '…'}`)
        Text(this.message)
        Button('Fit Switzerland').onClick(() => this.fitSwitzerland())
      }
      .margin({ bottom: 64 })
    }
  }

  private fitSwitzerland(): void {
    this.controller.fitCameraToLatLngBounds(SWITZERLAND, {
      mode: CameraUpdateMode.ease,
      fit: { padding: { top: 24, left: 24, bottom: 24, right: 24 } },
      animation: { durationMs: 1000 },
    }).then((outcome: CameraTransitionOutcome) => {
      // A gesture or a later move can stop it first.
      this.message = outcome === CameraTransitionOutcome.completed ? 'Fitted' : 'Stopped';
    }).catch((error: Error) => {
      // No map is on screen, or the map rejected the move.
      this.message = error.message;
    });
  }
}

// The user's location

const PERMISSIONS: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];

@ComponentV2
struct LocationExample {
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
          this.controller.followUserLocation({ zoom: 16, course: true });
          this.startUpdates().catch((error: Error) => console.error(error.message));
        })
    }
  }

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
}

// Snapshots

@ComponentV2
struct SnapshotExample {
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

// Expressions and the style API

async function styleWithExpressions(map: MapHandle): Promise<void> {
  const radius = interpolate(linear(), zoom(), [[0, 2], [12, get('size')]]);
  const color = match(get('kind'), [['park', '#8c8'], [['lake', 'river'], '#88c']], '#ccc');
  await map.setStyleLayerProperty('places', 'circle-radius', radius);
  await map.setStyleLayerProperty('places', 'circle-color', color);
}

// Requests, offline regions, and logs

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
}

function watchMissingImages(runtime: RuntimeHandle): void {
  addRuntimeEventListener(runtime, (event: RuntimeEvent) => {
    const payload = event.payload;
    if (event.type === RuntimeEventType.mapStyleImageMissing && payload.kind === 'styleImage') {
      console.warn(`The style needs the image ${payload.value.imageId}`);
    }
  }, RuntimeEventFlag.mapStyleImageMissing);
}

function takeLogs(): void {
  setLogCallback({
    callback: (severity: LogSeverity, event: LogEvent, code: bigint, message: string) => {
      console.info(`MapLibre (${event}): ${message}`);
    },
    // Errors still go to hilog too.
    platformSeverities: LogSeverityFlag.error,
  });
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
          LocationExample()
        }.tabBar('Location')
        TabContent() {
          SnapshotExample()
        }.tabBar('Snapshot')
      }
      .barMode(BarMode.Scrollable)
    }
    .title('README examples')
  }
}

// Keeps the functions that no tab calls from being unused.
export const COMPILED_EXAMPLES: Object[] = [snapshotOf, styleWithExpressions, useApiKey, downloadParis, takeLogs];
