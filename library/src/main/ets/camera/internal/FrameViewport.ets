import { MapProjectionHandle, MapView as FrameView } from '@maplibre/native-ffi';

import { LatLng, ScreenPoint } from '../../geometry/Geometry';
import { toLatLng, toScreenPoint } from '../../geometry/internal/FfiGeometry';
import { CameraPosition } from '../CameraPosition';
import { Viewport } from '../Viewport';
import { toCameraPosition } from './FfiCamera';
import { Insets } from './Insets';

// The viewport of a frame that the map drew, from FFI's view of it. The
// latest keeps one projection for its calls, which is released once a later
// viewport replaces it; an older one makes a projection for each call.
export class FrameViewport implements Viewport {
  readonly camera: CameraPosition;
  readonly size: Size;
  private readonly view: FrameView;
  private projection: MapProjectionHandle | undefined = undefined;
  private latest: boolean = true;

  // `padding` is the app's camera padding as the frame shows.
  constructor(view: FrameView, padding: Insets) {
    this.view = view;
    this.camera = toCameraPosition(view.camera, padding);
    this.size = { width: view.extent.width, height: view.extent.height };
  }

  project(coordinate: LatLng): ScreenPoint {
    return this.withProjection((projection: MapProjectionHandle) =>
      toScreenPoint(projection.pixelForLatLng(coordinate)));
  }

  unproject(point: ScreenPoint): LatLng {
    return this.withProjection((projection: MapProjectionHandle) =>
      toLatLng(projection.latLngForPixelUnwrapped(point)));
  }

  metersPerVpAtLatitude(latitude: number): number {
    return this.withProjection((projection: MapProjectionHandle) => projection.metersPerPixelAtLatitude(latitude));
  }

  // A later viewport replaced this one.
  retire(): void {
    this.latest = false;
    this.projection?.release();
    this.projection = undefined;
  }

  private withProjection<T>(call: (projection: MapProjectionHandle) => T): T {
    if (this.latest) {
      if (this.projection === undefined) {
        this.projection = MapProjectionHandle.create(this.view);
      }
      return call(this.projection);
    }
    const projection = MapProjectionHandle.create(this.view);
    try {
      return call(projection);
    } finally {
      projection.release();
    }
  }
}
