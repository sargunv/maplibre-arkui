// Examples for the "Overlay ArkUI content" guide.

import {
  AttributionControls,
  AttributionText,
  CameraTransitionMode,
  CompassButton,
  DefaultControls,
  FullControls,
  MapController,
  MaplibreMap,
  Marker,
  PointerPinButton,
  ScaleBar,
  ZoomButtons,
} from '@maplibre/arkui';

import { PARIS, STYLE } from './Common';

@ComponentV2
export struct PresetExample {
  build() {
    // #region preset
    MaplibreMap({ style: STYLE }) {
      FullControls()
    }
    // #endregion preset
  }
}

@ComponentV2
export struct NoControlsExample {
  // #region no-controls
  private controller: MapController = new MapController();

  build() {
    Column() {
      Stack() {
        MaplibreMap({ style: STYLE, controller: this.controller }) {
        }
      }
      .layoutWeight(1)
      AttributionText({ attributions: this.controller.attributions })
    }
  }
  // #endregion no-controls
}

@ComponentV2
export struct CustomControlsExample {
  build() {
    // #region custom-controls
    MaplibreMap({ style: STYLE }) {
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
    // #endregion custom-controls
  }
}

@ComponentV2
export struct MarkerExample {
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 11 } });

  build() {
    // #region marker
    MaplibreMap({ style: STYLE, controller: this.controller }) {
      DefaultControls()
      Marker({ coordinate: PARIS, alignment: Alignment.Bottom }) {
        Text('Paris')
          .padding(6)
          .borderRadius(6)
          .backgroundColor(Color.White)
          .onClick(() => {
            this.controller.updateCamera({ center: PARIS, zoom: 13 }, { mode: CameraTransitionMode.EASE })
              .catch((error: Error) => console.error(error.message));
          })
      }
    }
    // #endregion marker
  }
}

@ComponentV2
export struct PointerPinExample {
  private controller: MapController = new MapController({
    camera: { center: { latitude: 51.5072, longitude: -0.1276 }, zoom: 9 },
  });

  build() {
    // #region pointer-pin
    MaplibreMap({ style: STYLE, controller: this.controller }) {
      DefaultControls()
      Stack() {
        PointerPinButton({
          coordinate: PARIS,
          label: 'Paris',
          onPinClick: () => {
            this.controller.updateCamera({ center: PARIS }, { mode: CameraTransitionMode.FLY })
              .catch((error: Error) => console.error(error.message));
          },
        }) {
          Text('P')
        }
      }
      .width('100%')
      .height('100%')
      .padding(48)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    // #endregion pointer-pin
  }
}
