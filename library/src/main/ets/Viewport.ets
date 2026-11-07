// What a map shows in one frame, and the conversions between its screen
// points and coordinates.

import { MapProjectionHandle, MapView as FrameView } from '@maplibre/native-ffi';

import { CameraPosition } from './CameraPosition';
import { toCameraPosition, toLatLng, toScreenPoint } from './FfiValues';
import { LatLng, ScreenPoint } from './Geometry';
import { Insets } from './Insets';

/**
 * One frame that a map drew: its camera and size, and the conversions between
 * its screen points and coordinates. `MapController.viewport` holds the
 * latest. The map creates it; members may be added in later releases.
 *
 * Each member answers for the frame that it came with, also after later
 * frames replace it. Screen points are in vp from the map's top-left corner,
 * and can be outside the map.
 */
export interface Viewport {
  /**
   * The camera of the frame. Its `padding` is the app's, as
   * `MapController.camera` reports it, without the map's `viewportInsets`.
   */
  readonly camera: CameraPosition;
  /** The size of the map, in vp. */
  readonly size: Size;

  /**
   * Where `coordinate` is on the map, in the copy of the world nearest the
   * camera's center.
   */
  project(coordinate: LatLng): ScreenPoint;

  /**
   * The coordinate at `point`. Its longitude isn't wrapped to -180 to 180, so
   * it names the copy of the world that the point is in.
   */
  unproject(point: ScreenPoint): LatLng;

  /** How many meters one vp covers at `latitude`, at the frame's zoom, ignoring pitch. */
  metersPerVpAtLatitude(latitude: number): number;
}

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
