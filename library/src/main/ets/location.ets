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

/**
 * How the map draws `userLocation`: the colors of its default images and of
 * its accuracy circle, images of the style's own in their place, and the layer
 * it goes under. Fields that it leaves out keep their defaults. For more, such
 * as transitions or sizes, leave `userLocation` out and draw a
 * `location-indicator` layer in the map's `content`.
 *
 * ```ets
 * MapLibreMap({
 *   controller: this.map,
 *   style: STYLE,
 *   userLocation: this.location,
 *   userLocationIndicator: { color: '#e53935', below: 'road-label' },
 * })
 * ```
 */
export interface UserLocationIndicatorOptions {
  /**
   * The color of the default dot, which has a white border, and of the
   * default arrow, as a CSS color. `#1e88e5` by default.
   */
  color?: string;
  /** The fill of the circle that shows the location's `accuracy`, as a CSS color. */
  accuracyColor?: string;
  /** The border of the circle that shows the location's `accuracy`, as a CSS color. */
  accuracyBorderColor?: string;
  /**
   * The name of the image that marks the location, in place of the default
   * dot: one of the style's, or of the map's `content.images`. `''` draws none.
   */
  topImage?: string;
  /**
   * The name of the image under `topImage` that the heading or course turns,
   * pointing north before it turns, in place of the default arrow. It shows
   * only while there is a heading or a course. `''` draws none.
   */
  bearingImage?: string;
  /**
   * The name of the image under the others, in place of the default soft
   * shadow. `''` draws none.
   */
  shadowImage?: string;
  /**
   * The ID of the layer, of the style or of `content`, that the indicator goes
   * under. Above every layer by default. A layer that the style doesn't have
   * is reported to `onMapError`, and the indicator stays out until the
   * options change or a new style loads.
   */
  below?: string;
}

// How long the indicator and a following camera take to reach a new location.
// Both ease with MapLibre's default curve, so the dot stays at the center.
export const FOLLOW_MS = 1000;

const DOT_IMAGE = 'maplibre-arkui-user-location-dot';
const ARROW_IMAGE = 'maplibre-arkui-user-location-arrow';
const SHADOW_IMAGE = 'maplibre-arkui-user-location-shadow';
// The default images, as MapLibre Compose's LocationIndicatorDefaults draws
// them: a 24 vp dot of DOT_RADIUS in a white border out to BORDER_RADIUS, a
// 36 vp arrow, and a 28 vp shadow, 1 vp below the dot. Sizes are in vp.
export const DOT_COLOR = '#1e88e5';
export const DOT_RADIUS = 8;
export const BORDER_RADIUS = 10;
const DOT_SIZE = 24;
const ARROW_SIZE = 36;
const SHADOW_SIZE = 28;
const ACCURACY_COLOR = 'rgba(30, 136, 229, 0.15)';
const ACCURACY_BORDER_COLOR = 'rgba(30, 136, 229, 0.5)';

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

// The indicator layer of one map. A new style starts without it, so the view
// adds it again as each style loads, and new options add it again.
export class UserLocationLayer {
  private readonly density: number;
  private readonly fail: (error: Error) => void;
  private options: UserLocationIndicatorOptions;
  private loaded: boolean = false;
  private added: boolean = false;
  private hasArrow: boolean = false;

  constructor(density: number, options: UserLocationIndicatorOptions, fail: (error: Error) => void) {
    this.density = density;
    this.options = options;
    this.fail = fail;
  }

  styleLoaded(map: MapHandle, location: geoLocationManager.Location | undefined, heading: number | undefined): void {
    this.loaded = true;
    this.added = false;
    this.draw(map, location, heading);
  }

  styleChanging(): void {
    this.loaded = false;
  }

  // Takes new options, which the next draw applies.
  setOptions(map: MapHandle | undefined, options: UserLocationIndicatorOptions): void {
    this.options = options;
    if (map !== undefined && this.loaded && this.added) {
      this.added = false;
      map.discarding.removeStyleLayer(USER_LOCATION_LAYER);
    }
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
      this.addImages(map);
      map.addStyleLayerJson(this.layerJson(location, direction), this.options.below ?? '')
        .catch((error: Error) => this.fail(error));
      return;
    }
    map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'location', position(location));
    map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'accuracy-radius', location.accuracy);
    // A hidden arrow keeps its last bearing, so the next one eases from there.
    if (direction !== undefined) {
      map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'bearing', direction);
    }
    if (this.hasArrow !== (direction !== undefined)) {
      this.hasArrow = direction !== undefined;
      map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'bearing-image', this.arrow(direction));
    }
  }

  // The default images that the options leave in place, in their color.
  private addImages(map: MapHandle): void {
    const options = this.options;
    const color = options.color ?? DOT_COLOR;
    if (options.topImage === undefined) {
      setImage(map, DOT_IMAGE, dotImage(this.density, color), this.density);
    }
    if (options.bearingImage === undefined) {
      setImage(map, ARROW_IMAGE, arrowImage(this.density, color), this.density);
    }
    if (options.shadowImage === undefined) {
      setImage(map, SHADOW_IMAGE, shadowImage(this.density), this.density);
    }
  }

  // The bearing image, which shows only with a direction.
  private arrow(direction: number | undefined): string {
    return direction !== undefined ? this.options.bearingImage ?? ARROW_IMAGE : '';
  }

  private layerJson(location: geoLocationManager.Location, bearing: number | undefined): Record<string, Object> {
    const options = this.options;
    const transition: Record<string, Object> = { 'duration': FOLLOW_MS, 'delay': 0 };
    const layout: Record<string, Object> = {
      'top-image': options.topImage ?? DOT_IMAGE,
      'bearing-image': this.arrow(bearing),
      'shadow-image': options.shadowImage ?? SHADOW_IMAGE,
    };
    const paint: Record<string, Object> = {
      'location': position(location),
      'location-transition': transition,
      'bearing': bearing ?? 0,
      'bearing-transition': transition,
      'accuracy-radius': location.accuracy,
      'accuracy-radius-transition': transition,
      'accuracy-radius-color': options.accuracyColor ?? ACCURACY_COLOR,
      'accuracy-radius-border-color': options.accuracyBorderColor ?? ACCURACY_BORDER_COLOR,
      'perspective-compensation': 0.85,
    };
    return { 'id': USER_LOCATION_LAYER, 'type': 'location-indicator', 'layout': layout, 'paint': paint };
  }
}

// The layer's location is latitude, longitude, and altitude, unlike GeoJSON.
// The altitude doesn't draw.
function position(location: geoLocationManager.Location): number[] {
  return [location.latitude, location.longitude, 0];
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

function circle(context: OffscreenCanvasRenderingContext2D, x: number, y: number, radius: number): void {
  context.beginPath();
  context.arc(x, y, radius, 0, 2 * Math.PI);
  context.fill();
}

// A dot of `color` in a white border.
function dotImage(density: number, color: string): image.PixelMap {
  const context = canvas(DOT_SIZE, density);
  const c = DOT_SIZE / 2;
  context.fillStyle = '#ffffff';
  circle(context, c, c, BORDER_RADIUS);
  context.fillStyle = color;
  circle(context, c, c, DOT_RADIUS);
  return pixels(context, DOT_SIZE, density);
}

// An arrow of `color` that points north from beyond the dot's border,
// centered on the dot. The layer turns it to the heading or the course.
function arrowImage(density: number, color: string): image.PixelMap {
  const context = canvas(ARROW_SIZE, density);
  context.fillStyle = color;
  context.beginPath();
  context.moveTo(18, 0);
  context.lineTo(11, 12);
  context.lineTo(25, 12);
  context.closePath();
  context.fill();
  return pixels(context, ARROW_SIZE, density);
}

// A soft shadow that fades out from 1 vp below the dot's center.
function shadowImage(density: number): image.PixelMap {
  const context = canvas(SHADOW_SIZE, density);
  const gradient = context.createRadialGradient(14, 15, 0, 14, 15, 13);
  gradient.addColorStop(0, 'rgba(0, 0, 0, 0.4)');
  gradient.addColorStop(0.55, 'rgba(0, 0, 0, 0.25)');
  gradient.addColorStop(1, 'rgba(0, 0, 0, 0)');
  context.fillStyle = gradient;
  circle(context, 14, 15, 13);
  return pixels(context, SHADOW_SIZE, density);
}
