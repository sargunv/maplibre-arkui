import { CameraFitOptions, CameraOptions, MapHandle, RenderSessionHandle } from '@maplibre/native-ffi';
import display from '@ohos.display';

import { CameraMoveReason } from '../camera/CameraMoveReason';
import { CameraPosition, CameraUpdate } from '../camera/CameraPosition';
import { CameraTransitionOptions, FitCameraOptions } from '../camera/CameraTransitionOptions';
import { checkCamera, checkFit, checkTransition } from '../camera/internal/FfiCamera';
import { NO_INSETS, paddingInVp } from '../camera/internal/Insets';
import { Viewport } from '../camera/Viewport';
import { Expression } from '../expression/Expressions';
import { GeoJsonFeature, GeoJsonGeometry } from '../geometry/GeoJson';
import { LatLng, LatLngBounds, ScreenPoint } from '../geometry/Geometry';
import { checkBounds, checkCoordinates, checkGeometry } from '../geometry/internal/FfiGeometry';
import { FollowBearing, FollowUserLocationOptions } from '../location/FollowUserLocationOptions';
import { StyleApi } from '../style/internal/StyleApi';
import { MapStyle } from '../style/MapStyle';
import { ControllerState, registerControllerState } from './internal/ControllerState';
import { checkHitPadding } from './internal/Queries';

/** Options for a new `MapController`. */
export interface MapControllerOptions {
  /**
   * Where the camera starts. Fields left out are 0. The constructor throws an
   * `Error` for a camera that `updateCamera()` throws for, and for padding in
   * lpx.
   */
  camera?: CameraUpdate;
}

/**
 * Reads and moves the camera of a `MaplibreMap`.
 *
 * Pass it to one map at a time. It's attached to the map that appeared last,
 * and a new map that shows it starts where the camera was.
 *
 * The camera methods throw an `Error` for an invalid argument. A move made
 * while no map is attached waits for one, and moves run in the order they're
 * made.
 */
@ObservedV2
export class MapController {
  private readonly state: ControllerState;
  private readonly mapStyle: MapStyle;

  constructor(options?: MapControllerOptions) {
    const state = new ControllerState(startCamera(options?.camera));
    this.state = state;
    this.mapStyle = new StyleApi(() => state.loadedStyle);
    registerControllerState(this, state);
  }

  /** Where the camera is, updated on every frame of a move. Observable. */
  get camera(): CameraPosition {
    return this.state.camera;
  }

  /**
   * The latest frame that the map drew, or undefined before the attached map
   * draws one. Observable.
   */
  get viewport(): Viewport | undefined {
    return this.state.viewport;
  }

  /**
   * Whether the camera is moving, from `onCameraMoveStart` until
   * `onCameraIdle`. False while the controller isn't attached to a map.
   * Observable.
   */
  get cameraMoving(): boolean {
    return this.state.cameraMoving;
  }

  /**
   * What moved the camera last. It keeps its value after the camera stops.
   * Undefined until the attached map's camera first moves. Observable.
   */
  get cameraMoveReason(): CameraMoveReason | undefined {
    return this.state.cameraMoveReason;
  }

  /**
   * Whether the map's style has loaded, with the map's `content` added to it.
   * Observable.
   */
  get styleLoaded(): boolean {
    return this.state.styleLoaded;
  }

  /**
   * Reads and changes the map's loaded style, from `onStyleLoaded` until the
   * next style loads.
   */
  get style(): MapStyle {
    return this.mapStyle;
  }

  /**
   * The attributions of the style's sources, as HTML, without duplicates.
   * Empty until the style loads. Observable.
   */
  get attributions(): string[] {
    return this.state.attributions;
  }

  /**
   * Whether the camera follows the map's `userLocation`, from
   * `followUserLocation()` until following stops. Observable.
   */
  get followingUserLocation(): boolean {
    return this.state.followingUserLocation;
  }

  /**
   * The bearing that the camera turns with while it follows the map's
   * `userLocation`, or undefined while it doesn't turn. A rotation by the user,
   * or a camera move that sets a bearing, clears it. Observable.
   */
  get followedBearing(): FollowBearing | undefined {
    return this.state.followedBearing;
  }

  /**
   * Moves the camera, at once or animated, as `options` says. A `padding`
   * replaces the camera's padding; without one, the padding stays.
   *
   * Throws an `Error` for a field that isn't finite, a latitude outside -90 to
   * 90, a padding side below 0 or in percent, or a `durationMs` below 0.
   *
   * Resolves `true` when the camera arrives, and `false` when something stops
   * the move first, such as the user's input or another move. Rejects when the
   * map rejects the move.
   */
  updateCamera(update: CameraUpdate, options?: CameraTransitionOptions): Promise<boolean> {
    return this.state.updateCamera(checkCamera(update), checkTransition(options));
  }

  /**
   * Moves the camera so `bounds` fits in the area that the map's
   * `viewportInsets`, the camera's padding, and `options.fitPadding` leave.
   *
   * Throws an `Error` for bounds with a value that isn't finite, a latitude
   * outside -90 to 90, or a southwest corner north or east of the northeast
   * corner, and for invalid `options`. Resolves like `updateCamera()`, and also
   * rejects when the padding leaves no room.
   */
  fitCameraToBounds(bounds: LatLngBounds, options?: FitCameraOptions): Promise<boolean> {
    const checked = checkBounds(bounds);
    return this.state.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForLatLngBounds(checked, fit));
  }

  /**
   * Moves the camera so all of `coordinates` fit, like `fitCameraToBounds()`.
   * Throws an `Error` for an empty array, or for a coordinate that isn't a
   * valid `center`.
   */
  fitCameraToCoordinates(coordinates: LatLng[], options?: FitCameraOptions): Promise<boolean> {
    const checked = checkCoordinates(coordinates);
    return this.state.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions) => map.cameraForLatLngs(checked, fit));
  }

  /**
   * Moves the camera so `geometry` fits, like `fitCameraToBounds()`. Throws an
   * `Error` for a geometry without positions, or with a longitude that isn't
   * finite or a latitude outside -90 to 90.
   */
  fitCameraToGeometry(geometry: GeoJsonGeometry, options?: FitCameraOptions): Promise<boolean> {
    const checked = checkGeometry(geometry);
    return this.state.fit(checkFit(options),
      (map: MapHandle, fit: CameraFitOptions): Promise<CameraOptions> => map.cameraForGeometry(checked, fit));
  }

  /**
   * Stops every camera move, including waiting moves and a gesture's momentum.
   * Each stopped move resolves `false`.
   */
  cancelCameraTransitions(): void {
    this.state.cancelCameraTransitions();
  }

  /**
   * Moves the camera to the map's `userLocation`, and then with each new one,
   * keeping it at the center. Calling it again replaces the options.
   *
   * Following stops when the user pans, when a camera move sets `center`, on
   * any fit, and on `stopFollowingUserLocation()`. The user can zoom, rotate,
   * and pitch while the camera follows.
   */
  followUserLocation(options?: FollowUserLocationOptions): void {
    this.state.followUserLocation(options);
  }

  /** Stops following the map's `userLocation`. */
  stopFollowingUserLocation(): void {
    this.state.stopFollowingUserLocation();
  }

  /**
   * Finds the features that the map drew at `point`, or within
   * `options.hitPadding` of it. A feature that several layers draw comes once
   * for each.
   *
   * Throws an `Error` for a `hitPadding` below 0 or not finite. Resolves
   * undefined while no map is drawing. Rejects when the map rejects the query,
   * such as for an invalid `filter`.
   */
  queryRenderedFeatures(point: ScreenPoint,
    options?: RenderedFeatureQueryOptions): Promise<RenderedFeature[] | undefined> {
    const hitPadding = checkHitPadding(options?.hitPadding);
    return this.state.queryRenderedFeatures(point, hitPadding, options);
  }

  /**
   * Finds the features of the source with `sourceId` in the tiles it has loaded
   * for the current view. Resolves undefined while no map is drawing. Rejects
   * when the map rejects the query.
   */
  querySourceFeatures(sourceId: string, options?: SourceFeatureQueryOptions): Promise<SourceFeature[] | undefined> {
    return this.state.querySourceFeatures(sourceId, options);
  }

  /**
   * Calls `block` with the attached map's MapLibre Native FFI map, and its
   * render session while it has one. Returns what `block` returns, or undefined
   * without calling it while no map is attached.
   *
   * Use the map and session only inside `block`, before any `await`. Don't
   * change what the library manages through them: the style, the map's
   * `content`, IDs that start with `maplibre-arkui`, the camera padding and
   * bounds, the runtime's event handler, and the map's event mask. FFI's types
   * may change in any release.
   */
  withFfiMap<T>(block: (map: MapHandle, session: RenderSessionHandle | undefined) => T): T | undefined {
    return this.state.withFfiMap(block);
  }
}

/** Which features `MapController.queryRenderedFeatures()` finds. */
export interface RenderedFeatureQueryOptions {
  /**
   * How far from the point, in vp, a feature still counts. Must be finite and
   * at least 0. 0 by default.
   */
  hitPadding?: number;
  /** The IDs of the layers to query. Every layer by default. */
  layers?: string[];
  /** Keeps only the features for which this is true. Every feature by default. */
  filter?: Expression;
}

/**
 * A feature that `MapController.queryRenderedFeatures()` found. Fields may be
 * added in later releases.
 */
export interface RenderedFeature {
  /** The feature, with its geometry as the layer drew it. */
  readonly feature: GeoJsonFeature;
  /** The ID of the layer that drew the feature. */
  readonly layerId: string;
  /** The ID of the feature's source. */
  readonly sourceId: string;
  /**
   * The source layer of a vector source that holds the feature, or undefined
   * for other sources.
   */
  readonly sourceLayer: string | undefined;
  /** The feature's state. Empty for a feature without state. */
  readonly state: Record<string, Object>;
}

/** Which features `MapController.querySourceFeatures()` finds. */
export interface SourceFeatureQueryOptions {
  /** The source layers of a vector source to query. It finds features only in these. */
  sourceLayers?: string[];
  /** Keeps only the features for which this is true. Every feature by default. */
  filter?: Expression;
}

/**
 * A feature that `MapController.querySourceFeatures()` found. Fields may be
 * added in later releases.
 */
export interface SourceFeature {
  /** The feature, with its geometry as its tiles hold it. */
  readonly feature: GeoJsonFeature;
  /**
   * The source layer of a vector source that holds the feature, or undefined
   * for other sources.
   */
  readonly sourceLayer: string | undefined;
}

// The start camera, with MapLibre's defaults for the fields that `update`
// leaves out, and its padding in vp. Without a UI context, the default
// display converts it.
function startCamera(update: CameraUpdate | undefined): CameraPosition {
  const camera = checkCamera(update ?? {});
  const padding = camera.padding === undefined ? NO_INSETS : paddingInVp(camera.padding, {
    px: (px: number) => px / display.getDefaultDisplaySync().densityPixels,
    fp: (fp: number) => {
      const screen = display.getDefaultDisplaySync();
      return fp * screen.scaledDensity / screen.densityPixels;
    },
  });
  return {
    center: camera.center ?? { latitude: 0, longitude: 0 },
    zoom: camera.zoom ?? 0,
    bearing: camera.bearing ?? 0,
    pitch: camera.pitch ?? 0,
    padding: { top: padding.top, left: padding.left, bottom: padding.bottom, right: padding.right },
  };
}
