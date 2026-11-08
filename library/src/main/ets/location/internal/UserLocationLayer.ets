// The user's location on a map: the indicator that a MaplibreMap draws as a
// style layer, and how the camera follows it. The app gets the location from
// Location Kit and the heading from the compass, or anywhere else, and passes
// them to the map; this library requests no permission and starts no location
// or sensor request.

import { MapHandle } from '@maplibre/native-ffi';
import image from '@ohos.multimedia.image';
import geoLocationManager from '@ohos.geoLocationManager';
import { LengthMetricsUnit } from '@ohos.arkui.node';

import { readPixelMap } from '../../content/internal/PixelMaps';
import { LayerPredicate } from '../../content/StyleLayer';
import { UserLocationIndicatorOptions } from '../UserLocationIndicatorOptions';
import { resolveColor, StyleColor } from '../../expression/internal/Colors';

// The `location-indicator` layer that draws `userLocation`. It exists only
// while the map has a location, so it's internal.
export const USER_LOCATION_LAYER = 'maplibre-arkui-user-location';

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
// The accuracy circle's default fill and border, as fractions of the color's
// alpha.
const ACCURACY_OPACITY = 0.15;
const ACCURACY_BORDER_OPACITY = 0.5;

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

// The indicator's colors, as the style takes them.
interface IndicatorColors {
  color: string;
  accuracy: string;
  accuracyBorder: string;
}

// The indicator layer of one map. A new style starts without it, so the view
// adds it again as each style loads, and new options add it again. It goes in
// after the content that the map is applying, so it can go under a layer of
// that content.
export class UserLocationLayer {
  private readonly density: number;
  private readonly fail: (error: Error) => void;
  private readonly contentApplied: () => Promise<void>;
  // The ID of the layer that a `below` picks now, or '' for none.
  private readonly layerBelow: (below: string | LayerPredicate) => string;
  private options: UserLocationIndicatorOptions;
  // The options as JSON, which a change draws again, and their colors.
  private optionsJson: string;
  private colors: IndicatorColors;
  private location: geoLocationManager.Location | undefined = undefined;
  private heading: number | undefined = undefined;
  private loaded: boolean = false;
  private state: LayerState = LayerState.none;
  // Counts the adds and removals, so an add that waits stops once it's stale.
  private changes: number = 0;
  private hasArrow: boolean = false;
  // The layer that the indicator went under, or '' for the top.
  private before: string = '';

  constructor(density: number, options: UserLocationIndicatorOptions, contentApplied: () => Promise<void>,
    layerBelow: (below: string | LayerPredicate) => string, fail: (error: Error) => void) {
    this.density = density;
    this.contentApplied = contentApplied;
    this.layerBelow = layerBelow;
    this.fail = fail;
    this.options = options;
    this.optionsJson = optionsJson(options);
    this.colors = this.resolveColors();
  }

  styleLoaded(map: MapHandle, location: geoLocationManager.Location | undefined, heading: number | undefined): void {
    this.loaded = true;
    this.state = LayerState.none;
    this.changes++;
    this.draw(map, location, heading);
  }

  // The style is going, or the map is.
  styleChanging(): void {
    this.loaded = false;
    this.state = LayerState.none;
    this.changes++;
  }

  // Takes new options. Options that differ, or a predicate `below` that picks
  // another layer, draw the indicator again.
  setOptions(map: MapHandle | undefined, options: UserLocationIndicatorOptions): void {
    const json = optionsJson(options);
    const changed = json !== this.optionsJson;
    this.options = options;
    if (changed) {
      this.optionsJson = json;
      this.colors = this.resolveColors();
    }
    if (map === undefined || !this.loaded) {
      return;
    }
    if (changed || (this.state === LayerState.added && this.below() !== this.before)) {
      this.remove(map);
      this.draw(map, this.location, this.heading);
    }
  }

  // The color mode changed, so the colors resolve again, and an indicator in
  // the style takes them.
  colorModeChanged(map: MapHandle | undefined): void {
    this.colors = this.resolveColors();
    if (map === undefined || this.state !== LayerState.added) {
      return;
    }
    this.addImages(map);
    map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'accuracy-radius-color', this.colors.accuracy);
    map.discarding.setStyleLayerProperty(USER_LOCATION_LAYER, 'accuracy-radius-border-color',
      this.colors.accuracyBorder);
  }

  // Adds, moves, or removes the indicator. The style animates the move.
  draw(map: MapHandle, location: geoLocationManager.Location | undefined, heading: number | undefined): void {
    this.location = location;
    this.heading = heading;
    if (!this.loaded) {
      return;
    }
    if (location === undefined || this.options.visible === false) {
      this.remove(map);
      return;
    }
    if (this.state === LayerState.none) {
      this.add(map);
      return;
    }
    // An add that waits takes the latest location as it goes in.
    if (this.state === LayerState.adding) {
      return;
    }
    const direction = arrowBearing(location, heading);
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

  private remove(map: MapHandle): void {
    if (this.state === LayerState.added) {
      map.discarding.removeStyleLayer(USER_LOCATION_LAYER);
    }
    this.state = LayerState.none;
    this.changes++;
  }

  // Adds the layer once the content in progress is in, under the layer that
  // `below` picks then, and above every layer without one.
  private add(map: MapHandle): void {
    this.state = LayerState.adding;
    const change = ++this.changes;
    const current = (): boolean => this.changes === change && this.loaded;
    this.contentApplied().then(() => {
      const location = this.location;
      if (!current() || location === undefined) {
        return;
      }
      const direction = arrowBearing(location, this.heading);
      this.before = this.below();
      this.state = LayerState.added;
      this.hasArrow = direction !== undefined;
      this.addImages(map);
      map.discarding.addStyleLayerJson(this.layerJson(location, direction), this.before);
    }).catch((error: Error) => {
      if (current()) {
        this.fail(error);
      }
    });
  }

  // The layer that the options' `below` picks now, or '' for the top.
  private below(): string {
    const below = this.options.below;
    return below === undefined ? '' : this.layerBelow(below);
  }

  // The options' colors, with the default in place of each that ArkUI can't
  // resolve.
  private resolveColors(): IndicatorColors {
    const options = this.options;
    const color = this.resolve(options.color, 'color') ?? resolveColor(DOT_COLOR);
    return {
      color: color.rgba(),
      accuracy: this.resolve(options.accuracyColor, 'accuracyColor')?.rgba() ?? color.rgba(ACCURACY_OPACITY),
      accuracyBorder: this.resolve(options.accuracyBorderColor, 'accuracyBorderColor')?.rgba() ??
      color.rgba(ACCURACY_BORDER_OPACITY),
    };
  }

  // Undefined without a color, or for one that fails, which the map reports.
  private resolve(color: ResourceColor | undefined, name: string): StyleColor | undefined {
    if (color === undefined) {
      return undefined;
    }
    try {
      return resolveColor(color);
    } catch (error) {
      this.fail(new Error(`userLocationIndicator.${name}: ${(error as Error).message}, so it takes its default`));
      return undefined;
    }
  }

  // The default images that the options leave in place, in their color.
  private addImages(map: MapHandle): void {
    const options = this.options;
    const color = this.colors.color;
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
      'accuracy-radius-color': this.colors.accuracy,
      'accuracy-radius-border-color': this.colors.accuracyBorder,
      'perspective-compensation': 0.85,
    };
    return { 'id': USER_LOCATION_LAYER, 'type': 'location-indicator', 'layout': layout, 'paint': paint };
  }
}

enum LayerState {
  none,
  // Waiting for the content to go in first.
  adding,
  added,
}

// The options as JSON, with a `below` that names a layer, which can be one
// that the content in progress adds. A predicate picks a base layer, which the
// indicator compares by the layer it picks.
function optionsJson(options: UserLocationIndicatorOptions): string {
  const below = options.below;
  const fields: (Object | undefined)[] = [options.visible, options.color, options.accuracyColor,
    options.accuracyBorderColor, options.topImage, options.bearingImage, options.shadowImage,
    typeof below === 'string' ? below : undefined];
  return JSON.stringify(fields);
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
