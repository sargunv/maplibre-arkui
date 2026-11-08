// Examples for the "Control the camera" guide.

import {
  CameraIdleEvent,
  CameraMoveReason,
  CameraTransitionMode,
  FullControls,
  LatLng,
  LatLngBounds,
  MapController,
  MaplibreMap,
} from '@maplibre/arkui';

import { STYLE } from './Common';

@ComponentV2
export struct StartPositionExample {
  // #region start-position
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
  });

  build() {
    MaplibreMap({ style: STYLE, controller: this.controller })
  }
  // #endregion start-position
}

@ComponentV2
export struct MoveCameraExample {
  private controller: MapController = new MapController();

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MaplibreMap({ style: STYLE, controller: this.controller })
      Row({ space: 8 }) {
        // #region ease
        Button('Zoom in')
          .onClick(() => {
            this.controller.updateCamera({ zoom: this.controller.camera.zoom + 1 }, { mode: CameraTransitionMode.EASE })
              .catch((error: Error) => console.error(error.message));
          })
        // #endregion ease
        Button('Tokyo').onClick(() => this.flyTo({ latitude: 35.6762, longitude: 139.6503 }))
      }
      .margin(64)
    }
  }

  // #region fly
  private flyTo(city: LatLng): void {
    this.controller.updateCamera({ center: city, zoom: 12 }, { mode: CameraTransitionMode.FLY, durationMs: 3000 })
      .catch((error: Error) => console.error(error.message));
  }
  // #endregion fly
}

// #region fit
const SWITZERLAND: LatLngBounds = {
  southwest: { latitude: 45.82, longitude: 5.96 },
  northeast: { latitude: 47.81, longitude: 10.49 },
};

async function showSwitzerland(controller: MapController): Promise<void> {
  const arrived = await controller.fitCameraToBounds(SWITZERLAND, {
    mode: CameraTransitionMode.EASE,
    fitPadding: { top: 24, left: 24, bottom: 24, right: 24 },
  });
  if (!arrived) {
    console.info('The user moved the map first');
  }
}
// #endregion fit

@ComponentV2
export struct ReadCameraExample {
  @Local resting: string = '';
  private controller: MapController = new MapController();

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // #region camera-idle
      MaplibreMap({
        style: STYLE,
        controller: this.controller,
        onCameraIdle: (event: CameraIdleEvent) => {
          this.resting = `Stopped at zoom ${event.camera.zoom.toFixed(1)}`;
        },
      })
      // #endregion camera-idle
      Column() {
        // #region read-camera
        Text(`Zoom ${this.controller.camera.zoom.toFixed(1)}`)
        // #endregion read-camera
        Text(this.resting)
      }
      .margin(64)
    }
  }
}

@ComponentV2
export struct CameraMovingExample {
  private controller: MapController = new MapController();

  // #region camera-moving
  @Computed
  get userMovingMap(): boolean {
    return this.controller.cameraMoving && this.controller.cameraMoveReason === CameraMoveReason.GESTURE;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MaplibreMap({ style: STYLE, controller: this.controller })
      Text('Places nearby')
        .width('100%')
        .padding(16)
        .backgroundColor(Color.White)
        .visibility(this.userMovingMap ? Visibility.Hidden : Visibility.Visible)
    }
  }
  // #endregion camera-moving
}

@ComponentV2
export struct ViewportInsetsExample {
  // #region viewport-insets
  @Local panelHeight: number = 0;
  private controller: MapController = new MapController();

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MaplibreMap({
        style: STYLE,
        controller: this.controller,
        viewportInsets: { bottom: this.panelHeight },
      }) {
        FullControls()
      }
      Column() {
        Text('Places nearby')
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

@ComponentV2
export struct CameraBoundsExample {
  private controller: MapController = new MapController({ camera: { center: { latitude: 46.8, longitude: 8.2 } } });

  build() {
    // #region camera-bounds
    MaplibreMap({
      style: STYLE,
      controller: this.controller,
      cameraBounds: { bounds: SWITZERLAND, minZoom: 6, maxZoom: 16, maxPitch: 0 },
    })
    // #endregion camera-bounds
  }
}

export const CAMERA_FUNCTIONS: Object[] = [showSwitzerland];
