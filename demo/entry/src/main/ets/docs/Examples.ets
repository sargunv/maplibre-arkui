// The examples of the documentation site, which the demo builds, so they keep
// to the API. Each `// #region <name>` is an example that a page of docs/ cuts
// out by name, and the site build fails on a region that's missing. The
// demo's "Guide examples" page shows them in tabs.

import { MapDebugFlag, MapHandle } from '@maplibre/native-ffi';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import common from '@ohos.app.ability.common';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import application from '@ohos.app.ability.application';
import { AppStorageV2 } from '@ohos.arkui.StateManagement';
import geoLocationManager from '@ohos.geoLocationManager';
import http from '@ohos.net.http';
import image from '@ohos.multimedia.image';
import sensor from '@ohos.sensor';
import util from '@ohos.util';

import {
  AttributionControls,
  AttributionText,
  CameraMoveReason,
  CameraPosition,
  CameraTransitionMode,
  cases,
  CompassButton,
  ConnectivityMode,
  ContentError,
  DefaultControls,
  eq,
  FeatureClickEvent,
  featureState,
  FollowBearing,
  fp,
  FullControls,
  GeoJsonFeature,
  GeoJsonFeatureCollection,
  GeoJsonPoint,
  GeoJsonSourceHandle,
  get,
  geometryType,
  globalState,
  has,
  interpolate,
  LatLngBounds,
  LayerHandle,
  LayerSummary,
  linear,
  literal,
  LatLng,
  MapClickEvent,
  MapContent,
  MapController,
  MapError,
  MapLogLevel,
  MapLogRecord,
  MaplibreMap,
  MapResourceError,
  MapResourceErrorReason,
  MapResourceLoadRequest,
  MapResourceProvider,
  MapResourceRequest,
  MapResourceResponse,
  MapRuntime,
  MapSnapshot,
  Marker,
  match,
  not,
  OfflineRegion,
  OfflineRegionDefinition,
  PointerPinButton,
  RenderedFeature,
  renderSnapshot,
  ResolvedStyleImage,
  ScaleBar,
  StyleImageMissingEvent,
  StyleLayer,
  toBoolean,
  WheelAction,
  zoom,
  ZoomButtons,
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

// #region content-image
// Decodes an image from the app's resources/rawfile into a PixelMap.
function decodeImage(context: UIContext, rawfile: string): image.PixelMap {
  const bytes = context.getHostContext()!.resourceManager.getRawFileContentSync(rawfile);
  const source = image.createImageSource(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  try {
    return source.createPixelMapSync();
  } finally {
    source.release();
  }
}
// #endregion content-image

@ComponentV2
struct ContentExample {
  @Local places: GeoJsonFeatureCollection = PARIS;
  @Local color: string = '#1e88e5';
  @Local selected: string = 'Tap a place';
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.858, longitude: 2.315 }, zoom: 12 },
  });
  // #region content-image-keep
  // Decoded once, since the map compares images by reference, and released
  // only once the content no longer has it.
  private pin: image.PixelMap = decodeImage(this.getUIContext(), 'pin.png');

  aboutToDisappear(): void {
    this.pin.release();
  }
  // #endregion content-image-keep

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
          below: (layer: LayerSummary) => layer.type === 'symbol',
          // #region layer-click
          // A click up to 8 vp beside a circle counts.
          hitPadding: 8,
          onClick: (event: FeatureClickEvent): boolean => {
            // The front one of the circles under the click.
            this.selected = `${event.features[0].properties?.['name']}`;
            // Consumed: the layers under this one and onUnhandledClick don't get it.
            return true;
          },
          // #endregion layer-click
        },
        {
          id: 'monuments', type: 'symbol', source: 'places', filter: eq(get('kind'), 'monument'),
          layout: { 'icon-image': 'pin', 'icon-anchor': 'bottom', 'icon-allow-overlap': true },
        },
        {
          id: 'names', type: 'symbol', source: 'places',
          // fp(): the labels follow the user's font size setting.
          layout: {
            'text-field': get('name'), 'text-font': literal(['Noto Sans Regular']), 'text-size': fp(14),
            'text-anchor': 'top', 'text-offset': literal([0, 0.8]),
          },
          paint: { 'text-halo-color': '#ffffff', 'text-halo-width': 1 },
          // Directly under the pins, wherever they go.
          below: 'monuments',
        },
      ],
      images: [{ id: 'pin', image: this.pin }],
    };
  }
  // #endregion content

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // #region map-click
      MaplibreMap({
        style: STYLE,
        controller: this.controller,
        content: this.content,
        // Before the layers: true keeps the long click from them.
        onMapLongClick: (event: MapClickEvent): boolean => {
          this.selected = `${event.coordinate.latitude.toFixed(4)}, ${event.coordinate.longitude.toFixed(4)}`;
          return true;
        },
        // Neither the map's handler nor a layer consumed the click.
        onUnhandledClick: (event: MapClickEvent) => {
          this.selected = 'Nothing here';
        },
      })
      // #endregion map-click
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
}

@ComponentV2
struct QueryExample {
  @Local found: string = 'Tap the map';
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.858, longitude: 2.315 }, zoom: 15 },
  });

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // #region query-click
      MaplibreMap({
        style: STYLE,
        controller: this.controller,
        onMapClick: (event: MapClickEvent): boolean => {
          this.query(event).catch((error: Error) => console.error(error.message));
          return false;
        },
      })
      // #endregion query-click
      Text(this.found)
        .margin({ bottom: 64 })
    }
  }

  // The base style's features within 20 vp of a click, in any layer.
  // #region query
  private async query(event: MapClickEvent): Promise<void> {
    const hits = await this.controller.queryRenderedFeatures(event.point, { hitPadding: 20 });
    if (hits === undefined) {
      // The map left before it answered.
      return;
    }
    const layers = new Set<string>(hits.map((hit: RenderedFeature) => hit.layerId));
    this.found = `${hits.length} features in ${Array.from(layers).join(', ')}`;
  }
  // #endregion query
}

// Controls, placement, the camera, and gestures

const PARIS_CENTER: LatLng = { latitude: 48.8566, longitude: 2.3522 };

@ComponentV2
struct PresetExample {
  private controller: MapController = new MapController({ camera: { center: PARIS_CENTER, zoom: 11 } });

  build() {
    // #region overlay-preset
    MaplibreMap({ style: STYLE, controller: this.controller }) {
      FullControls()
    }
    // #endregion overlay-preset
  }
}

@ComponentV2
struct NoOverlayExample {
  private controller: MapController = new MapController({ camera: { center: PARIS_CENTER, zoom: 11 } });

  build() {
    // #region overlay-none
    Column() {
      Stack() {
        MaplibreMap({ style: STYLE, controller: this.controller }) {
        }
      }
      .layoutWeight(1)
      // The sources' terms require their attribution, so the app shows it.
      AttributionText({ attributions: this.controller.attributions })
    }
    // #endregion overlay-none
  }
}

@ComponentV2
struct CustomControlsExample {
  private controller: MapController = new MapController({
    camera: { center: PARIS_CENTER, zoom: 11, bearing: 30 },
  });

  build() {
    // #region overlay-custom
    MaplibreMap({ style: STYLE, controller: this.controller }) {
      AttributionControls()
      Column({ space: 8 }) {
        CompassButton()
        ZoomButtons()
        ScaleBar()
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.End)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    // #endregion overlay-custom
  }
}

@ComponentV2
struct MarkerExample {
  private controller: MapController = new MapController({ camera: { center: PARIS_CENTER, zoom: 11 } });

  build() {
    // #region marker
    MaplibreMap({ style: STYLE, controller: this.controller }) {
      DefaultControls()
      Marker({ coordinate: PARIS_CENTER, alignment: Alignment.Bottom }) {
        // Attributes such as onClick go on the content, not on the marker.
        Text('Paris')
          .padding(6)
          .margin({ bottom: 4 })
          .borderRadius(6)
          .backgroundColor(Color.White)
          .onClick(() => {
            this.controller.updateCamera({ center: PARIS_CENTER, zoom: 13 }, { mode: CameraTransitionMode.EASE })
              .catch((error: Error) => console.error(error.message));
          })
      }
    }
    // #endregion marker
  }
}

@ComponentV2
struct OffscreenMarkerExample {
  private controller: MapController = new MapController({
    camera: { center: { latitude: 51.5072, longitude: -0.1276 }, zoom: 9 },
  });

  build() {
    // #region offscreen-marker
    MaplibreMap({ style: STYLE, controller: this.controller }) {
      DefaultControls()
      // The pin moves along an oval 48 vp in from the map's edges: the content
      // box of its parent, which covers the map.
      Stack() {
        PointerPinButton({
          coordinate: PARIS_CENTER,
          label: 'Paris',
          onPinClick: () => {
            this.controller.updateCamera({ center: PARIS_CENTER }, { mode: CameraTransitionMode.FLY })
              .catch((error: Error) => console.error(error.message));
          },
        }) {
          Text('P')
            .fontWeight(FontWeight.Bold)
        }
      }
      .width('100%')
      .height('100%')
      .padding(48)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    // #endregion offscreen-marker
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
      MaplibreMap({
        style: STYLE,
        controller: this.controller,
        interactions: { rotate: { enabled: false }, pitch: { enabled: false } },
        onGestureStart: () => {
          this.moving = true;
        },
        onGestureEnd: () => {
          this.moving = false;
        },
      })
      // #endregion gestures
      Column({ space: 8 }) {
        // #region camera-observable
        // `camera` changes with each frame while the camera moves.
        Text(`Zoom ${this.controller.camera.zoom.toFixed(1)}`)
        // #endregion camera-observable
        Text(this.moving ? 'Moving' : 'Still')
        Text(this.message)
        Row({ space: 8 }) {
          Button('Zoom in').onClick(() => this.zoomIn())
          Button('Fit Switzerland').onClick(() => this.fitSwitzerland())
          Button('Look ahead').onClick(() => this.lookAhead())
        }
      }
      .margin({ bottom: 64 })
    }
  }

  private zoomIn(): void {
    // #region camera-move
    this.controller.updateCamera({ zoom: 12 }, { mode: CameraTransitionMode.EASE })
      .catch((error: Error) => console.error(error.message));
    // #endregion camera-move
  }

  private fitSwitzerland(): void {
    // #region camera-fit
    this.controller.fitCameraToBounds(SWITZERLAND, {
      mode: CameraTransitionMode.EASE,
      durationMs: 1000,
      // Space around Switzerland for this fit only.
      fitPadding: { top: 24, left: 24, bottom: 24, right: 24 },
    }).then((completed: boolean) => {
      // A gesture or a later move can stop it first.
      this.message = completed ? 'Fitted' : 'Stopped';
    }).catch((error: Error) => {
      // The map rejected the move.
      this.message = error.message;
    });
    // #endregion camera-fit
  }

  private lookAhead(): void {
    // #region camera-padding
    // The camera centers in the map below its top 200 vp, which shows more of
    // what lies ahead. The padding stays until a move or a fit changes it.
    this.controller.updateCamera({ padding: { top: 200 } }, { mode: CameraTransitionMode.EASE, durationMs: 500 })
      .catch((error: Error) => {
        this.message = error.message;
      });
    // #endregion camera-padding
  }
}

@ComponentV2
struct CameraMovingExample {
  private controller: MapController = new MapController({
    camera: { center: { latitude: 46.8, longitude: 8.2 }, zoom: 5 },
  });

  // #region camera-moving
  // The panel steps aside while the user moves the map, and stays while the
  // app moves it.
  @Computed
  get panelHidden(): boolean {
    return this.controller.cameraMoving && this.controller.cameraMoveReason === CameraMoveReason.GESTURE;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MaplibreMap({ style: STYLE, controller: this.controller })
      Text('Places nearby')
        .width('100%')
        .padding(16)
        .backgroundColor(Color.White)
        .visibility(this.panelHidden ? Visibility.Hidden : Visibility.Visible)
    }
  }
  // #endregion camera-moving
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
      // The controls stay above the panel, and the camera centers there too.
      MaplibreMap({
        style: STYLE,
        controller: this.controller,
        viewportInsets: { bottom: this.panelHeight },
      }) {
        FullControls()
      }
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
      AppStorageV2.connect(MapController, () => new MapController({ camera: camera }));
    }
  }

  onSaveState(reason: AbilityConstant.StateType, wantParam: Record<string, Object>): AbilityConstant.OnSaveResult {
    const camera = AppStorageV2.connect(MapController)?.camera;
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
    MaplibreMap({ style: STYLE, controller: this.controller })
  }
}
// #endregion save-camera

@ComponentV2
struct InteractionExample {
  @Local following: boolean = true;
  private controller: MapController = new MapController();

  build() {
    // #region interactions
    MaplibreMap({
      style: STYLE,
      controller: this.controller,
      interactions: {
        // The user takes over from the app's camera as they start to pan.
        pan: {
          onStart: () => {
            this.following = false;
          },
        },
        // The wheel pans, and zooms with Ctrl.
        wheel: WheelAction.PAN,
        // A rotation settles on, and ticks at, north, east, south, and west.
        rotate: { snap: { interval: 90 }, haptics: { interval: 90 } },
      },
    })
    // #endregion interactions
  }
}

@ComponentV2
struct MomentumExample {
  private controller: MapController = new MapController();

  build() {
    // #region momentum
    MaplibreMap({
      style: STYLE,
      controller: this.controller,
      interactions: {
        // A drag glides for a shorter time than a list's fling.
        pan: { momentum: { halfLifeMs: 120 } },
        // A pinch doesn't glide, and settles on the nearest whole level.
        zoom: { momentum: { enabled: false }, snap: { interval: 1 } },
        // A tilt that ends within 10° of flat lies flat.
        pitch: { snap: { interval: 90, tolerance: 10 } },
      },
    })
    // #endregion momentum
  }
}

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
      MaplibreMap({
        style: STYLE,
        controller: this.controller,
        userLocation: this.location,
      })
      // A pan stops following, and the button shows it.
      Button(this.controller.followingUserLocation ? 'Following' : 'Locate me')
        .margin(64)
        .onClick(() => {
          this.controller.followUserLocation({ zoom: 16, bearing: FollowBearing.COURSE });
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
      MaplibreMap({
        style: STYLE,
        controller: this.controller,
        userLocation: this.location,
        userHeading: this.heading,
      })
      // A twist keeps following but stops turning, and a tap turns again.
      Button(this.controller.followedBearing === FollowBearing.HEADING ? 'Facing up' : 'Face up')
        .margin(64)
        .onClick(() => this.controller.followUserLocation({ zoom: 16, bearing: FollowBearing.HEADING }))
    }
  }
  // #endregion heading
}

@ComponentV2
struct IndicatorExample {
  @Param location: geoLocationManager.Location | undefined = undefined;
  private controller: MapController = new MapController();

  build() {
    // #region location-indicator
    MaplibreMap({
      style: STYLE,
      controller: this.controller,
      userLocation: this.location,
      // The accuracy circle takes the color too. Without a shadow, and under
      // the style's labels.
      userLocationIndicator: {
        color: '#e53935',
        shadowImage: '',
        below: (layer: LayerSummary) => layer.type === 'symbol',
      },
    })
    // #endregion location-indicator
  }
}

// Snapshots

@ComponentV2
struct SnapshotExample {
  // #region snapshot
  @Local preview: MapSnapshot | undefined = undefined;
  private disappeared: boolean = false;

  aboutToAppear(): void {
    renderSnapshot({
      style: STYLE,
      width: 320,
      height: 200,
      camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
      uiContext: this.getUIContext(),
    }).then((preview: MapSnapshot) => {
      if (this.disappeared) {
        preview.image.release();
      } else {
        this.preview = preview;
      }
    }).catch((error: Error) => console.error(error.message));
  }

  aboutToDisappear(): void {
    this.disappeared = true;
    this.preview?.image.release();
  }
  // #endregion snapshot

  build() {
    Column() {
      if (this.preview !== undefined) {
        Image(this.preview.image)
          .width(320)
          .height(200)
        AttributionText({ attributions: this.preview.attributions })
      }
    }
    .width('100%')
  }
}

// An image of what a MaplibreMap shows: its style, its content, and its camera.
@ComponentV2
struct SnapshotOfExample {
  @Local preview: MapSnapshot | undefined = undefined;
  private disappeared: boolean = false;
  private controller: MapController = new MapController({ camera: { center: PARIS_CENTER, zoom: 13 } });
  private content: MapContent = {
    sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PARIS } }],
    layers: [{ id: 'places', type: 'circle', source: 'places', paint: { 'circle-color': '#e53935' } }],
  };

  aboutToDisappear(): void {
    this.disappeared = true;
    this.preview?.image.release();
  }

  // #region snapshot-of
  async takeSnapshot(): Promise<void> {
    // Where the camera is now, also during a move. The padding that makes
    // room for the map's own UI is left out.
    const camera = this.controller.camera;
    const preview = await renderSnapshot({
      style: STYLE,
      content: this.content,
      width: 320,
      height: 200,
      camera: { center: camera.center, zoom: camera.zoom, bearing: camera.bearing, pitch: camera.pitch },
      uiContext: this.getUIContext(),
    });
    if (this.disappeared) {
      preview.image.release();
      return;
    }
    this.preview?.image.release();
    this.preview = preview;
  }

  build() {
    Column({ space: 8 }) {
      MaplibreMap({ style: STYLE, controller: this.controller, content: this.content })
        .layoutWeight(1)
      Button('Snapshot')
        .onClick(() => this.takeSnapshot().catch((error: Error) => console.error(error.message)))
      if (this.preview !== undefined) {
        Image(this.preview.image)
          .width(320)
          .height(200)
        // The sources' terms usually require their attribution with the image.
        AttributionText({ attributions: this.preview.attributions })
      }
    }
  }
  // #endregion snapshot-of
}

// Expressions and the style API

// #region expressions
const PLACE_CIRCLES: StyleLayer = {
  id: 'place-circles', type: 'circle', source: 'places', filter: eq(geometryType(), 'Point'),
  paint: {
    'circle-radius': interpolate(linear(), zoom(), [[0, 2], [12, get('size')]]),
    'circle-color': match(get('kind'), [['park', '#8c8'], [['lake', 'river'], '#88c']], '#ccc'),
  },
};
// #endregion expressions

// #region ffi-map
// Tile borders, which the library doesn't cover. The command goes to the map
// in the block, and runs after it.
async function showTileBorders(controller: MapController): Promise<void> {
  await controller.withFfiMap((map: MapHandle) => map.setDebugFlags(MapDebugFlag.tileBorders));
}
// #endregion ffi-map

// #region style-source-data
// The base style's own `incidents` source, which the style's layers draw,
// loads today's file instead of the one that the style names.
async function showTodaysIncidents(controller: MapController): Promise<void> {
  const incidents: GeoJsonSourceHandle | undefined = await controller.style.getGeoJsonSource('incidents');
  await incidents?.setData('https://example.com/incidents/today.geojson');
}
// #endregion style-source-data

@ComponentV2
struct StyleExample {
  @Local kind: string = 'museum';
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.858, longitude: 2.315 }, zoom: 12 },
  });
  private places: GeoJsonSourceHandle | undefined = undefined;
  private selected: number | string | undefined = undefined;

  // A layer that the content declares shows the places of the kind that the
  // global state names.
  @Computed
  get content(): MapContent {
    return {
      sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PARIS } }],
      layers: [
        {
          id: 'places', type: 'circle', source: 'places', filter: eq(get('kind'), globalState('kind')),
          paint: {
            'circle-radius': 8,
            'circle-color': cases([[toBoolean(featureState('selected')), '#e53935']], '#fb8c00'),
          },
          onClick: (event: FeatureClickEvent): boolean => {
            this.select(event.features[0]).catch((error: Error) => console.error(error.message));
            return true;
          },
        },
      ],
    };
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MaplibreMap({
        style: STYLE,
        controller: this.controller,
        content: this.content,
        // Each style starts without what the app changed in the last.
        onStyleLoaded: () => {
          this.styleLoaded().catch((error: Error) => console.error(error.message));
        },
      })
      Row({ space: 8 }) {
        Button('Museums').onClick(() => this.showKind('museum'))
        Button('Monuments').onClick(() => this.showKind('monument'))
      }
      .margin({ bottom: 64 })
    }
  }

  private async styleLoaded(): Promise<void> {
    // #region style-layer
    // The base style's water, in another color.
    const water: LayerHandle | undefined = await this.controller.style.getLayer('water');
    await water?.setProperty('fill-color', '#1565c0');
    // #endregion style-layer
    await this.showKind(this.kind);
    await this.findPlaces();
  }

  // #region style-global-state
  // The places layer's filter reads the global state `kind`.
  private async showKind(kind: string): Promise<void> {
    this.kind = kind;
    await this.controller.style.setGlobalStateProperty('kind', kind);
  }
  // #endregion style-global-state

  // #region feature-state
  // Highlights the place under a click: the layer's paint reads its
  // `selected` state. Each style gives a handle of its own, which selects the
  // place again.
  private async findPlaces(): Promise<void> {
    this.places = await this.controller.style.getGeoJsonSource('places');
    if (this.selected !== undefined) {
      await this.places?.setFeatureState(this.selected, { 'selected': true });
    }
  }

  // Swaps the selection, then sends both changes without awaiting between
  // them, so that a later click's changes follow these: the map applies them
  // in order.
  private async select(place: GeoJsonFeature): Promise<void> {
    const places = this.places;
    if (places === undefined || place.id === undefined) {
      return;
    }
    const previous = this.selected;
    this.selected = place.id;
    const changes: Promise<boolean>[] = [];
    if (previous !== undefined) {
      changes.push(places.removeFeatureState(previous));
    }
    changes.push(places.setFeatureState(place.id, { 'selected': true }));
    await Promise.all(changes);
  }
  // #endregion feature-state
}

@ComponentV2
struct MissingImageExample {
  // #region missing-image
  // One pin, decoded once, for each image whose ID starts with `pin-` that
  // the style names but lacks.
  private pin: image.PixelMap = decodeImage(this.getUIContext(), 'pin.png');

  aboutToDisappear(): void {
    this.pin.release();
  }

  build() {
    MaplibreMap({
      style: STYLE,
      onStyleImageMissing: async (event: StyleImageMissingEvent): Promise<ResolvedStyleImage | undefined> => {
        if (!event.id.startsWith('pin-')) {
          return undefined;
        }
        const pin: ResolvedStyleImage = { image: this.pin };
        return pin;
      },
    })
  }
  // #endregion missing-image
}

@ComponentV2
struct ClusterExample {
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.858, longitude: 2.315 }, zoom: 11 },
  });

  build() {
    MaplibreMap({ style: STYLE, controller: this.controller, content: this.content })
  }

  // #region cluster-zoom
  // The places in clusters, and a click on a cluster zooms in until it splits.
  @Computed
  get content(): MapContent {
    return {
      sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PARIS, 'cluster': true } }],
      layers: [{
        id: 'clusters', type: 'circle', source: 'places', filter: has('point_count'),
        paint: { 'circle-radius': 16, 'circle-color': '#1e88e5' },
        onClick: (event: FeatureClickEvent): boolean => {
          this.zoomInto(event.features[0]).catch((error: Error) => console.error(error.message));
          return true;
        },
      }, {
        id: 'places', type: 'circle', source: 'places', filter: not(has('point_count')),
        paint: { 'circle-radius': 8, 'circle-color': '#fb8c00' },
      }],
    };
  }

  private async zoomInto(cluster: GeoJsonFeature): Promise<void> {
    const places = await this.controller.style.getGeoJsonSource('places');
    const zoom = await places?.getClusterExpansionZoom(cluster);
    if (zoom !== undefined && cluster.geometry?.type === 'Point') {
      const position = (cluster.geometry as GeoJsonPoint).coordinates;
      await this.controller.updateCamera({ center: { latitude: position[1], longitude: position[0] }, zoom: zoom },
        { mode: CameraTransitionMode.EASE });
    }
  }
  // #endregion cluster-zoom
}

// Errors

// #region map-errors
// For a map's onError.
function reportMapError(error: MapError): void {
  if (error instanceof ContentError) {
    console.error(`The map left out ${error.id}: ${error.message}`);
  } else {
    console.error(error.message);
  }
}
// #endregion map-errors

// Requests, offline regions, and logs

// #region resource-transform
// In the ability's onCreate(), before the first map: every map and snapshot on
// the default runtime adds the key to the URLs of tiles.example.com.
function configureMaps(): void {
  MapRuntime.configureDefault({
    rewriteUrl: (request: MapResourceRequest) => request.url.startsWith('https://tiles.example.com/') ?
      `${request.url}${request.url.includes('?') ? '&' : '?'}key=${API_KEY}` : undefined,
  });
}
// #endregion resource-transform

// #region resource-provider
// Serves app://styles/<name> from the app's rawfile/styles directory.
const APP_STYLES: MapResourceProvider = {
  urlPatterns: ['app://styles/*'],
  load: async (request: MapResourceLoadRequest): Promise<MapResourceResponse | undefined> => {
    const name = request.url.substring('app://styles/'.length);
    try {
      return { data: await application.getApplicationContext().resourceManager.getRawFileContent(`styles/${name}`) };
    } catch (error) {
      throw new MapResourceError(MapResourceErrorReason.NOT_FOUND, `The app has no style ${name}`);
    }
  },
};

@ComponentV2
struct AppStyleMap {
  // A runtime of the page's own, which it releases as it goes.
  private readonly runtime: MapRuntime = new MapRuntime({ resourceProvider: APP_STYLES });

  aboutToDisappear(): void {
    this.runtime.release().catch((error: Error) => console.error(error.message));
  }

  build() {
    MaplibreMap({ style: 'app://styles/outdoors.json', runtime: this.runtime })
  }
}
// #endregion resource-provider

// #region headers
// Loads the tiles of tiles.example.com with a token in a header.
const TOKEN_TILES: MapResourceProvider = {
  urlPatterns: ['https://tiles.example.com/**'],
  load: async (request: MapResourceLoadRequest): Promise<MapResourceResponse | undefined> => {
    const client = http.createHttp();
    request.onCancel(() => client.destroy());
    const header: Record<string, string> = { 'Authorization': `Bearer ${API_KEY}` };
    try {
      const response = await client.request(request.url,
        { header: header, expectDataType: http.HttpDataType.ARRAY_BUFFER });
      if (response.responseCode === 404) {
        throw new MapResourceError(MapResourceErrorReason.NOT_FOUND, `No tile at ${request.url}`);
      } else if (response.responseCode >= 500) {
        throw new MapResourceError(MapResourceErrorReason.SERVER, `HTTP ${response.responseCode}`);
      } else if (response.responseCode !== 200) {
        throw new MapResourceError(MapResourceErrorReason.OTHER, `HTTP ${response.responseCode}`);
      }
      return { data: response.result as ArrayBuffer };
    } finally {
      client.destroy();
    }
  },
};
// #endregion headers

const PARIS_REGION: OfflineRegionDefinition = {
  styleUrl: STYLE,
  bounds: { southwest: { latitude: 48.81, longitude: 2.22 }, northeast: { latitude: 48.91, longitude: 2.42 } },
  minZoom: 10,
  maxZoom: 14,
};

// #region offline
@ComponentV2
struct OfflineParis {
  @Local region: OfflineRegion | undefined = undefined;

  async download(): Promise<void> {
    const name = new util.TextEncoder().encodeInto('Paris');
    this.region = await MapRuntime.getDefault().createOfflineRegion(PARIS_REGION, name);
    await this.region.startDownload();
  }

  build() {
    Column({ space: 8 }) {
      if (this.region === undefined) {
        Button('Download Paris').onClick(() => this.download().catch((error: Error) => console.error(error.message)))
      } else {
        // The status is observable, so the progress follows the download.
        Progress({
          value: this.region.status.completedResourceCount,
          total: Math.max(1, this.region.status.requiredResourceCount),
        })
        Text(this.region.status.complete ? 'Paris is offline' : 'Downloading Paris…')
      }
    }
  }
}
// #endregion offline

// #region connectivity
// An app setting that keeps maps to the cache and offline regions.
function setMapsUseNetwork(allowed: boolean): void {
  MapRuntime.setConnectivityMode(allowed ? ConnectivityMode.AUTOMATIC : ConnectivityMode.FORCE_OFFLINE);
}
// #endregion connectivity

function takeLogs(): void {
  // #region logs
  MapRuntime.setLogHandler((record: MapLogRecord) => {
    if (record.level === MapLogLevel.ERROR) {
      console.warn(`MapLibre (${record.category ?? 'library'}): ${record.message}`);
    }
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
          QueryExample()
        }.tabBar('Query')
        TabContent() {
          StyleExample()
        }.tabBar('Style API')
        TabContent() {
          MissingImageExample()
        }.tabBar('Missing images')
        TabContent() {
          ClusterExample()
        }.tabBar('Clusters')
        TabContent() {
          PresetExample()
        }.tabBar('Preset')
        TabContent() {
          NoOverlayExample()
        }.tabBar('No overlay')
        TabContent() {
          CustomControlsExample()
        }.tabBar('Controls')
        TabContent() {
          MarkerExample()
        }.tabBar('Marker')
        TabContent() {
          OffscreenMarkerExample()
        }.tabBar('Offscreen marker')
        TabContent() {
          CameraExample()
        }.tabBar('Camera')
        TabContent() {
          CameraMovingExample()
        }.tabBar('Camera moving')
        TabContent() {
          InsetsExample()
        }.tabBar('Insets')
        TabContent() {
          SavedCameraExample()
        }.tabBar('Saved camera')
        TabContent() {
          InteractionExample()
        }.tabBar('Interactions')
        TabContent() {
          MomentumExample()
        }.tabBar('Momentum')
        TabContent() {
          LocationExample()
        }.tabBar('Location')
        TabContent() {
          HeadingExample()
        }.tabBar('Heading')
        TabContent() {
          SnapshotExample()
        }.tabBar('Snapshot')
        TabContent() {
          SnapshotOfExample()
        }.tabBar('Snapshot of a map')
        TabContent() {
          AppStyleMap()
        }.tabBar('App style')
        TabContent() {
          OfflineParis()
        }.tabBar('Offline')
      }
      .barMode(BarMode.Scrollable)
    }
    .title('Guide examples')
  }
}

// Keeps the functions that no tab calls from being unused.
export const COMPILED_EXAMPLES: Object[] = [showTileBorders, showTodaysIncidents, reportMapError, configureMaps,
  TOKEN_TILES, setMapsUseNetwork, takeLogs];
