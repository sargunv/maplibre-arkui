// The user's location on a map: the indicator that a MapLibreMap draws as a
// style layer, and how the camera follows it. The app gets the location from
// Location Kit, or anywhere else, and passes it to the map; this library
// requests no permission and starts no location request.

import { CameraOptions, MapHandle } from '@maplibre/native-ffi';
import { LengthMetricsUnit } from '@ohos.arkui.node';
import geoLocationManager from '@ohos.geoLocationManager';
import image from '@ohos.multimedia.image';

import { readPixelMap } from './StyleImage';

/**
 * The ID of the `location-indicator` layer that draws `userLocation`, for
 * apps that restyle it with `setStyleLayerProperty()`, or place their own
 * layers below it.
 */
export const USER_LOCATION_LAYER = 'maplibre-arkui-user-location';

/** How `MapController.followUserLocation()` moves the camera. */
export interface FollowLocationOptions {
  /** The zoom that the camera eases to as it starts to follow. Keeps the zoom by default. */
  zoom?: number;
  /**
   * Turns the map so the direction of travel points up, while the location
   * has one: a `speed` above 0. Keeps the bearing by default.
   */
  course?: boolean;
}

// How long the indicator and a following camera take to reach a new location.
// Both ease with MapLibre's default curve, so the dot stays at the center.
export const FOLLOW_MS = 1000;

const DOT_IMAGE = 'maplibre-arkui-user-location-dot';
const COURSE_IMAGE = 'maplibre-arkui-user-location-course';
const BLUE = '#1e88e5';

// Location Kit reports a direction even at rest, so only a moving location has
// a course.
function course(location: geoLocationManager.Location): number | undefined {
  return location.speed > 0 ? location.direction : undefined;
}

// Where a following camera moves for `location`.
export function followCamera(location: geoLocationManager.Location, options: FollowLocationOptions,
  zoom: number | undefined): CameraOptions {
  return {
    center: { latitude: location.latitude, longitude: location.longitude },
    zoom: zoom,
    bearing: options.course === true ? course(location) : undefined,
  };
}

// The indicator layer of one map. A new style starts without it, so the view
// adds it again as each style loads.
export class UserLocationLayer {
  private readonly density: number;
  private loaded: boolean = false;
  private added: boolean = false;
  private hasCourse: boolean = false;

  constructor(density: number) {
    this.density = density;
  }

  styleLoaded(map: MapHandle, location: geoLocationManager.Location | undefined): void {
    this.loaded = true;
    this.added = false;
    this.draw(map, location);
  }

  styleChanging(): void {
    this.loaded = false;
  }

  // Adds, moves, or removes the indicator. The style animates the move.
  draw(map: MapHandle, location: geoLocationManager.Location | undefined): void {
    if (!this.loaded) {
      return;
    }
    if (location === undefined) {
      if (this.added) {
        this.added = false;
        map.discarding.removeStyleLayer(USER_LOCATION_LAYER);
      }
      return;
    }
    const bearing = course(location);
    if (!this.added) {
      this.added = true;
      this.hasCourse = bearing !== undefined;
      setImage(map, DOT_IMAGE, dotImage(this.density), this.density);
      setImage(map, COURSE_IMAGE, courseImage(this.density), this.density);
      map.discarding.addStyleLayerJson(layerJson(location, bearing));
      return;
    }
    map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'location', position(location));
    map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'accuracy-radius', location.accuracy);
    map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'bearing', bearing ?? 0);
    if (this.hasCourse !== (bearing !== undefined)) {
      this.hasCourse = bearing !== undefined;
      map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'bearing-image',
        bearing !== undefined ? COURSE_IMAGE : '');
    }
  }
}

// The layer's location is latitude, longitude, and altitude, unlike GeoJSON.
// The altitude doesn't draw.
function position(location: geoLocationManager.Location): number[] {
  return [location.latitude, location.longitude, 0];
}

function layerJson(location: geoLocationManager.Location, bearing: number | undefined): Record<string, Object> {
  const transition: Record<string, Object> = { 'duration': FOLLOW_MS, 'delay': 0 };
  const layout: Record<string, Object> = {
    'top-image': DOT_IMAGE,
    'bearing-image': bearing !== undefined ? COURSE_IMAGE : '',
  };
  const paint: Record<string, Object> = {
    'location': position(location),
    'location-transition': transition,
    'bearing': bearing ?? 0,
    'bearing-transition': transition,
    'accuracy-radius': location.accuracy,
    'accuracy-radius-transition': transition,
    'accuracy-radius-color': 'rgba(30, 136, 229, 0.15)',
    'accuracy-radius-border-color': 'rgba(30, 136, 229, 0.5)',
    'perspective-compensation': 0.85,
  };
  return { 'id': USER_LOCATION_LAYER, 'type': 'location-indicator', 'layout': layout, 'paint': paint };
}

function setImage(map: MapHandle, id: string, pixelMap: image.PixelMap, density: number): void {
  try {
    map.discarding.setStyleImage(id, readPixelMap(pixelMap), { pixelRatio: density });
  } finally {
    pixelMap.release();
  }
}

// A canvas of `size` vp, at `density` pixels each, drawn in vp.
function canvas(size: number, density: number): OffscreenCanvasRenderingContext2D {
  const pixels = Math.ceil(size * density);
  const context = new OffscreenCanvas(pixels, pixels, LengthMetricsUnit.PX).getContext('2d');
  context.scale(density, density);
  return context;
}

function pixels(context: OffscreenCanvasRenderingContext2D, size: number, density: number): image.PixelMap {
  const side = Math.ceil(size * density);
  return context.getPixelMap(0, 0, side, side);
}

// A blue dot with a white border, 22 vp across.
function dotImage(density: number): image.PixelMap {
  const context = canvas(22, density);
  context.fillStyle = '#ffffff';
  context.beginPath();
  context.arc(11, 11, 10, 0, 2 * Math.PI);
  context.fill();
  context.fillStyle = BLUE;
  context.beginPath();
  context.arc(11, 11, 7, 0, 2 * Math.PI);
  context.fill();
  return pixels(context, 22, density);
}

// An arrow that points north from beyond the dot's border, centered on the
// dot. The layer turns it to the course.
function courseImage(density: number): image.PixelMap {
  const context = canvas(36, density);
  context.fillStyle = BLUE;
  context.beginPath();
  context.moveTo(18, 0);
  context.lineTo(12, 8);
  context.lineTo(24, 8);
  context.closePath();
  context.fill();
  return pixels(context, 36, density);
}
