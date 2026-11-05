import { BoundOptions, Camera as CameraPosition, RuntimeHandle } from '@maplibre/native-ffi';

import { MapController } from './MapController';
import { MapView } from './MapView';
import { MapAttribution, MapCompass, MapScaleBar, MapZoomButtons } from './Ornaments';

@Builder
function noContent() {
}

// Where the ornaments go in the map. ets-loader rejects `layoutGravity`, so
// they align in a RelativeContainer.
const CONTAINER = '__container__';
const TOP_START: LocalizedAlignRuleOptions = {
  top: { anchor: CONTAINER, align: VerticalAlign.Top },
  start: { anchor: CONTAINER, align: HorizontalAlign.Start },
};
const TOP_END: LocalizedAlignRuleOptions = {
  top: { anchor: CONTAINER, align: VerticalAlign.Top },
  end: { anchor: CONTAINER, align: HorizontalAlign.End },
};
const CENTER_END: LocalizedAlignRuleOptions = {
  center: { anchor: CONTAINER, align: VerticalAlign.Center },
  end: { anchor: CONTAINER, align: HorizontalAlign.End },
};
const BOTTOM_END: LocalizedAlignRuleOptions = {
  bottom: { anchor: CONTAINER, align: VerticalAlign.Bottom },
  end: { anchor: CONTAINER, align: HorizontalAlign.End },
};

/**
 * A MapLibre map, which fills the size that its parent gives it.
 *
 * ```ets
 * private map: MapController = new MapController({
 *   camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 15 },
 * });
 *
 * build() {
 *   MapLibreMap({
 *     controller: this.map,
 *     style: 'https://tiles.openfreemap.org/styles/liberty',
 *     onMapError: (error: Error) => console.error(error.message),
 *   }) {
 *     MapMarker({ controller: this.map, coordinate: { latitude: 48.8584, longitude: 2.2945 } }) {
 *       Text('Eiffel Tower')
 *     }
 *   }
 * }
 * ```
 *
 * Its content, in the trailing closure, lies over the map in a `Stack` of the
 * map's size, under the map's ornaments. Pin it to coordinates with
 * `MapMarker`.
 */
@ComponentV2
export struct MapLibreMap {
  /** Reads and moves the camera. Without one, the map keeps its own. */
  @Param @Once controller: MapController = new MapController();
  /** The style's URL, or a style document as JSON. */
  @Require @Param style: string;
  /**
   * Limits on the camera: an area that its center stays within, and zoom and
   * pitch ranges. Limits it leaves out keep the map's defaults.
   */
  @Param cameraBounds: BoundOptions | undefined = undefined;
  /**
   * The FFI runtime that creates the map. Without one, maps share the
   * library's default runtime. The map sets the runtime's event handler, so
   * listen with `addRuntimeEventListener()` instead of setting one.
   */
  @Param @Once runtime: RuntimeHandle | undefined = undefined;
  /**
   * Whether the map shows a `MapCompass` at its top end, which shows while the
   * map is rotated or tilted.
   */
  @Param compassEnabled: boolean = true;
  /** Whether the map shows a `MapScaleBar` at its top start. */
  @Param scaleBarEnabled: boolean = false;
  /** Whether the map shows `MapZoomButtons` in the middle of its end edge. */
  @Param zoomButtonsEnabled: boolean = false;
  /**
   * Whether the map shows a `MapAttribution` at its bottom end. Most sources'
   * terms require their attribution, so show it elsewhere without one.
   */
  @Param attributionEnabled: boolean = true;
  /**
   * Space between the map's edges and its ornaments, so they stay clear of app
   * UI that covers the map.
   */
  @Param ornamentPadding: Padding = {};
  /** ArkUI content over the map, in a `Stack` of its size. */
  @BuilderParam content: () => void = noContent;
  /**
   * The style has loaded, so its layers and sources exist. Each style starts
   * from its own document, so add the app's sources, layers, and images
   * here, through `controller.map`, each time it loads.
   */
  @Event onStyleLoaded: () => void = () => {
  };
  /** The camera has come to rest, after a jump or once an animation ends. */
  @Event onCameraIdle: (camera: CameraPosition) => void = (camera: CameraPosition) => {
  };
  /** The style failed to load, or the map failed to render. */
  @Event onMapError: (error: Error) => void = (error: Error) => {
  };

  private view: MapView = new MapView(this.getUIContext(), {
    onStyleLoaded: () => this.onStyleLoaded(),
    onCameraIdle: (camera: CameraPosition) => this.onCameraIdle(camera),
    onMapError: (error: Error) => this.onMapError(error),
  });

  aboutToAppear(): void {
    this.view.start(this.controller, this.runtime, this.style, this.cameraBounds);
  }

  aboutToDisappear(): void {
    this.view.dispose();
  }

  @Monitor('style')
  styleChanged(): void {
    this.view.setStyle(this.style);
  }

  @Monitor('cameraBounds')
  cameraBoundsChanged(): void {
    this.view.setBounds(this.cameraBounds);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      XComponent({ type: XComponentType.SURFACE, controller: this.view })
        .width('100%')
        .height('100%')
      this.content()
      RelativeContainer() {
        if (this.scaleBarEnabled) {
          MapScaleBar({ controller: this.controller })
            .margin(8)
            .alignRules(TOP_START)
        }
        if (this.compassEnabled) {
          MapCompass({ controller: this.controller })
            .margin(8)
            .alignRules(TOP_END)
        }
        if (this.zoomButtonsEnabled) {
          MapZoomButtons({ controller: this.controller })
            .margin(8)
            .alignRules(CENTER_END)
        }
        if (this.attributionEnabled) {
          MapAttribution({ controller: this.controller })
            .margin(8)
            .alignRules(BOTTOM_END)
        }
      }
      .width('100%')
      .height('100%')
      .padding(this.ornamentPadding)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
