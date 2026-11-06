// The user's location on a map: the indicator that a MapLibreMap draws as a
// style layer, and how the camera follows it. The app gets the location from
// Location Kit and the heading from the compass, or anywhere else, and passes
// them to the map; this library requests no permission and starts no location
// or sensor request.

import { MapHandle } from '@maplibre/native-ffi';
import { LengthMetricsUnit } from '@ohos.arkui.node';
import geoLocationManager from '@ohos.geoLocationManager';
import image from '@ohos.multimedia.image';

import { readPixelMap } from './StyleImage';

// The `location-indicator` layer that draws `userLocation`. It exists only
// while the map has a location, so it's internal.
export const USER_LOCATION_LAYER = 'maplibre-arkui-user-location';

/** Which direction `MapController.followUserLocation()` turns the map to point up. */
export enum FollowBearing {
  /** The direction of travel, while the location has one: a `speed` above 0. */
  course,
  /** The map's `userHeading`, the direction that the device faces, while it has one. */
  heading,
}

/** How `MapController.followUserLocation()` moves the camera. */
export interface FollowUserLocationOptions {
  /** The zoom that the camera eases to as it starts to follow. Keeps the zoom by default. */
  zoom?: number;
  /**
   * The direction that the map turns to point up. While there is none, and
   * by default, the camera keeps its bearing.
   */
  bearing?: FollowBearing;
}

// How long the indicator and a following camera take to reach a new location.
// Both ease with MapLibre's default curve, so the dot stays at the center.
export const FOLLOW_MS = 1000;

const DOT_IMAGE = 'maplibre-arkui-user-location-dot';
const ARROW_IMAGE = 'maplibre-arkui-user-location-arrow';
// The dot's color, and its radius and its white border's, in vp.
export const DOT_COLOR = '#1e88e5';
export const DOT_RADIUS = 7;
export const BORDER_RADIUS = 10;

// Location Kit reports a direction even at rest, so only a moving location has
// a course.
export function course(location: geoLocationManager.Location): number | undefined {
  return location.speed > 0 ? location.direction : undefined;
}

// The direction that the arrow points: where the device faces, or else where
// it moves.
function arrowBearing(location: geoLocationManager.Location, heading: number | undefined): number | undefined {
  return heading ?? course(location);
}

// `bearing` turned by whole turns to be within half a turn of `from`, so the
// layer's transition, which eases the number, turns the short way across
// north.
function nearestTurn(bearing: number, from: number): number {
  return bearing + 360 * Math.round((from - bearing) / 360);
}

// The indicator layer of one map. A new style starts without it, so the view
// adds it again as each style loads.
export class UserLocationLayer {
  private readonly density: number;
  private loaded: boolean = false;
  private added: boolean = false;
  private hasArrow: boolean = false;
  // The bearing last set on the layer.
  private bearing: number = 0;

  constructor(density: number) {
    this.density = density;
  }

  styleLoaded(map: MapHandle, location: geoLocationManager.Location | undefined, heading: number | undefined): void {
    this.loaded = true;
    this.added = false;
    this.draw(map, location, heading);
  }

  styleChanging(): void {
    this.loaded = false;
  }

  // Adds, moves, or removes the indicator. The style animates the move.
  draw(map: MapHandle, location: geoLocationManager.Location | undefined, heading: number | undefined): void {
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
    const direction = arrowBearing(location, heading);
    if (!this.added) {
      this.added = true;
      this.hasArrow = direction !== undefined;
      this.bearing = direction ?? 0;
      setImage(map, DOT_IMAGE, dotImage(this.density), this.density);
      setImage(map, ARROW_IMAGE, arrowImage(this.density), this.density);
      map.discarding.addStyleLayerJson(layerJson(location, direction));
      return;
    }
    map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'location', position(location));
    map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'accuracy-radius', location.accuracy);
    // A hidden arrow keeps its last bearing, so the next one eases from there.
    if (direction !== undefined) {
      this.bearing = nearestTurn(direction, this.bearing);
      map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'bearing', this.bearing);
    }
    if (this.hasArrow !== (direction !== undefined)) {
      this.hasArrow = direction !== undefined;
      map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'bearing-image',
        direction !== undefined ? ARROW_IMAGE : '');
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
    'bearing-image': bearing !== undefined ? ARROW_IMAGE : '',
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

// A blue dot with a white border, with 1 vp around it.
function dotImage(density: number): image.PixelMap {
  const size = 2 * BORDER_RADIUS + 2;
  const context = canvas(size, density);
  context.fillStyle = '#ffffff';
  context.beginPath();
  context.arc(size / 2, size / 2, BORDER_RADIUS, 0, 2 * Math.PI);
  context.fill();
  context.fillStyle = DOT_COLOR;
  context.beginPath();
  context.arc(size / 2, size / 2, DOT_RADIUS, 0, 2 * Math.PI);
  context.fill();
  return pixels(context, size, density);
}

// An arrow that points north from beyond the dot's border, centered on the
// dot. The layer turns it to the heading or the course.
function arrowImage(density: number): image.PixelMap {
  const context = canvas(36, density);
  context.fillStyle = DOT_COLOR;
  context.beginPath();
  context.moveTo(18, 0);
  context.lineTo(12, 8);
  context.lineTo(24, 8);
  context.closePath();
  context.fill();
  return pixels(context, 36, density);
}
