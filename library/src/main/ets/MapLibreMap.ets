import { BoundOptions, Camera as CameraPosition, RuntimeHandle } from '@maplibre/native-ffi';

import { MapController } from './MapController';
import { MapView } from './MapView';

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
 *   })
 * }
 * ```
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
    XComponent({ type: XComponentType.SURFACE, controller: this.view })
      .width('100%')
      .height('100%')
  }
}
