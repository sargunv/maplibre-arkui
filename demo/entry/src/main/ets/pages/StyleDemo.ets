import { FrameCallback } from '@ohos.arkui.UIContext';
import image from '@ohos.multimedia.image';

import {
  all,
  cases,
  CommandCompletion,
  eq,
  FeatureClickHandler,
  featureState,
  FeatureStateSelector,
  GeoJsonFeature,
  GeoJsonFeatureCollection,
  geometryType,
  get,
  LatLng,
  MapClickEvent,
  MapContent,
  MapController,
  MapLayer,
  MapLibreMap,
  match,
  PremultipliedRgba8Image,
  readPixelMap,
  RenderedFeature,
  snapshot,
  StyleLayerInfo,
  toBoolean,
} from '@maplibre/arkui';

import { DEMOTILES, LIBERTY, PANEL } from './common';


// Places around the Champ de Mars in Paris, written as an ArkTS object. The
// GeoJSON source takes it as is.
const PARIS: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: [
    {
      type: 'Feature', id: 1, geometry: { type: 'Point', coordinates: [2.2945, 48.8584] },
      properties: { 'name': 'Eiffel Tower', 'kind': 'monument' },
    },
    {
      type: 'Feature', id: 2, geometry: { type: 'Point', coordinates: [2.2885, 48.8622] },
      properties: { 'name': 'Palais de Chaillot', 'kind': 'museum' },
    },
    {
      type: 'Feature', id: 3, geometry: { type: 'Point', coordinates: [2.2977, 48.8609] },
      properties: { 'name': 'Musée du quai Branly', 'kind': 'museum' },
    },
    {
      type: 'Feature', id: 4, geometry: { type: 'Point', coordinates: [2.3040, 48.8520] },
      properties: { 'name': 'École Militaire', 'kind': 'monument' },
    },
    {
      type: 'Feature', id: 10, properties: { 'name': 'Champ de Mars' },
      geometry: {
        type: 'Polygon',
        coordinates: [[[2.2965, 48.8581], [2.3045, 48.8538], [2.3026, 48.8522], [2.2946, 48.8565],
          [2.2965, 48.8581]]],
      },
    },
    {
      type: 'Feature', id: 20, properties: { 'name': 'A walk to the tower' },
      geometry: {
        type: 'LineString',
        coordinates: [[2.2885, 48.8622], [2.2915, 48.8604], [2.2945, 48.8584], [2.2995, 48.8552]],
      },
    },
  ],
};

const PARK_COLORS = ['#66bb6a', '#ffa726', '#ab47bc'];

// Paint that reads the feature's `selected` state, which a tap sets.
const SELECTED = toBoolean(featureState('selected'));
const SELECTED_STATE: Record<string, Object> = { 'selected': true };

// Under the base style's labels, so they draw over it. Each layer's features
// handle a click with `onClick`.
function parkLayer(color: string, onClick: FeatureClickHandler): MapLayer {
  return {
    id: 'paris-park', type: 'fill', source: 'paris', filter: eq(geometryType(), 'Polygon'),
    paint: { 'fill-color': cases([[SELECTED, '#2e7d32']], color), 'fill-opacity': 0.6 },
    below: (layer: StyleLayerInfo) => layer.type === 'symbol',
    onClick: onClick,
  };
}

// The line is thin, so a click 8 vp beside it counts.
function walkLayer(onClick: FeatureClickHandler): MapLayer {
  return {
    id: 'paris-walk', type: 'line', source: 'paris', filter: eq(geometryType(), 'LineString'),
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': '#5e35b1', 'line-width': cases([[SELECTED, 9]], 5) },
    onClick: onClick,
    hitPadding: 8,
  };
}

function placesLayer(onClick: FeatureClickHandler): MapLayer {
  return {
    id: 'paris-places', type: 'circle', source: 'paris', filter: eq(geometryType(), 'Point'),
    paint: {
      'circle-radius': cases([[SELECTED, 12]], 8),
      'circle-color': match(get('kind'), [['museum', '#fb8c00'], ['monument', '#1e88e5'], ['added', '#e53935']],
        '#757575'),
      'circle-stroke-width': cases([[SELECTED, 4]], 2),
      'circle-stroke-color': cases([[SELECTED, '#e53935']], '#ffffff'),
    },
    onClick: onClick,
  };
}

// A pin from the app's resources over each monument.
function pinsLayer(onClick: FeatureClickHandler): MapLayer {
  return {
    id: 'paris-pins', type: 'symbol', source: 'paris',
    filter: all(eq(geometryType(), 'Point'), eq(get('kind'), 'monument')),
    layout: { 'icon-image': 'pin', 'icon-anchor': 'bottom', 'icon-allow-overlap': true },
    onClick: onClick,
  };
}

// The n-th point that the app adds: at `coordinate`, or on a spiral around
// the park.
function addedPoint(n: number, coordinate?: LatLng): GeoJsonFeature {
  const angle = n * 2.4;
  const distance = 0.003 + 0.0006 * n;
  const position = coordinate === undefined ?
    [2.2995 + distance * 1.5 * Math.cos(angle), 48.8551 + distance * Math.sin(angle)] :
    [coordinate.longitude, coordinate.latitude];
  return {
    type: 'Feature', id: 100 + n, properties: { 'name': `Point ${n + 1}`, 'kind': 'added' },
    geometry: { type: 'Point', coordinates: position },
  };
}

// Decodes an image from the app's rawfile resources into the pixels the style
// takes. (This repository's build can't compile `$r()` yet; see AGENTS.md.)
function loadPin(context: UIContext): PremultipliedRgba8Image {
  const bytes = context.getHostContext()!.resourceManager.getRawFileContentSync('pin.png');
  const source = image.createImageSource(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  try {
    const pixelMap = source.createPixelMapSync();
    try {
      return readPixelMap(pixelMap);
    } finally {
      pixelMap.release();
    }
  } finally {
    source.release();
  }
}

// A map whose content comes from the page's state: a GeoJSON source, layers
// styled with expressions, and an icon from the app's resources. The buttons
// change the state, and the map applies the change, in each base style. A tap
// on a feature selects it with feature state, through FFI, and a long press
// adds a point.
@ComponentV2
export struct StyleDemo {
  @Local style: string = LIBERTY;
  @Local placesShown: boolean = true;
  @Local parkColor: number = 0;
  @Local added: GeoJsonFeature[] = [];
  @Local preview: image.PixelMap | undefined = undefined;
  @Local message: string = 'Tap a place, the walk, or the park; long press to add a point';
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8570, longitude: 2.2965 }, zoom: 13.6 },
  });
  private pin: PremultipliedRgba8Image = loadPin(this.getUIContext());
  private selected: FeatureStateSelector | undefined = undefined;
  // The layers are on top of each other, so the topmost feature under a click
  // takes it, and the layers under it don't get it.
  private onFeatureClick: FeatureClickHandler = (features: RenderedFeature[], event: MapClickEvent): boolean => {
    this.select(features[0], event);
    return true;
  };

  // What the map draws over its style. It changes when the state it reads
  // does, and the map changes only what differs.
  @Computed
  get content(): MapContent {
    const places: GeoJsonFeatureCollection = { type: 'FeatureCollection', features: PARIS.features.concat(this.added) };
    const layers: MapLayer[] = [parkLayer(PARK_COLORS[this.parkColor], this.onFeatureClick),
      walkLayer(this.onFeatureClick)];
    if (this.placesShown) {
      layers.push(placesLayer(this.onFeatureClick));
    }
    layers.push(pinsLayer(this.onFeatureClick));
    return {
      sources: [{ id: 'paris', json: { 'type': 'geojson', 'data': places } }],
      layers: layers,
      images: [{ id: 'pin', image: this.pin, options: { pixelRatio: 3 } }],
    };
  }

  aboutToDisappear(): void {
    this.preview?.release();
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        MapLibreMap({
          controller: this.controller,
          style: this.style,
          content: this.content,
          onMapError: (error: Error) => {
            this.message = error.message;
          },
          // A click that no feature took clears the selection.
          onUnhandledClick: (event: MapClickEvent) => {
            this.select(undefined, event);
          },
          onMapLongClick: (event: MapClickEvent): boolean => {
            this.added = this.added.concat([addedPoint(this.added.length, event.coordinate)]);
            return true;
          },
        })
        if (this.preview !== undefined) {
          Image(this.preview)
            .width(160)
            .height(120)
            .borderRadius(8)
            .borderWidth(2)
            .borderColor('#ffffff')
            .position({ top: 12, right: 12 })
            .onClick(() => {
              this.preview?.release();
              this.preview = undefined;
            })
        }
        Column({ space: 8 }) {
          Text(this.message)
            .fontSize(14)
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            Button(this.placesShown ? 'Hide circles' : 'Show circles').margin(4).onClick(() => {
              this.placesShown = !this.placesShown;
            })
            Button('Park color').margin(4).onClick(() => {
              this.parkColor = (this.parkColor + 1) % PARK_COLORS.length;
            })
            Button('Add point').margin(4).onClick(() => {
              this.added = this.added.concat([addedPoint(this.added.length)]);
            })
            Button('Remove point').margin(4).enabled(this.added.length > 0).onClick(() => {
              this.added = this.added.slice(0, this.added.length - 1);
            })
            Button(this.style === LIBERTY ? 'Demo tiles' : 'Liberty').margin(4).onClick(() => {
              this.style = this.style === LIBERTY ? DEMOTILES : LIBERTY;
            })
            Button('Snapshot').margin(4).onClick(() => this.takeSnapshot())
          }
        }
        .attributeModifier(PANEL)
      }
      .width('100%')
      .height('100%')
    }
    .title('Style')
  }

  // A still image of the same style, content, and camera.
  private async takeSnapshot(): Promise<void> {
    try {
      const preview = await snapshot({
        style: this.style,
        content: this.content,
        camera: this.controller.getCamera(),
        width: 160,
        height: 120,
      });
      this.preview?.release();
      this.preview = preview;
    } catch (error) {
      this.message = (error as Error).message;
    }
  }

  // Selects the feature that a click hit, or nothing.
  private async select(hit: RenderedFeature | undefined, event: MapClickEvent): Promise<void> {
    const map = this.controller.map;
    if (map === undefined) {
      return;
    }
    try {
      const where = `at ${event.x.toFixed(0)}, ${event.y.toFixed(0)} vp`;
      const feature = hit?.feature as GeoJsonFeature | undefined;
      this.message = hit === undefined ? `Nothing here ${where}` :
        `${feature?.properties?.['name']} in ${hit.layerId} ${where}`;

      // The map compares feature IDs as text.
      const next: FeatureStateSelector | undefined = hit === undefined || feature?.id === undefined ? undefined :
        { sourceId: hit.sourceId, featureId: { kind: 'stringValue', value: `${feature.id}` } };
      // Swap the selection before awaiting, so a later tap's swap follows this
      // one. The map runs the commands in order.
      const previous = this.selected;
      this.selected = next;
      const changes: Promise<CommandCompletion>[] = [];
      if (previous !== undefined) {
        changes.push(map.removeFeatureState(previous));
      }
      if (next !== undefined) {
        changes.push(map.setFeatureState(next, SELECTED_STATE));
      }
      await Promise.all(changes);
      // FFI draws a feature state change only from the frame after the one
      // that applies it, so ask for that frame (maplibre-native-ffi#1706).
      this.getUIContext().postDelayedFrameCallback(new Repaint(this.controller), 100);
    } catch (error) {
      this.message = (error as Error).message;
    }
  }
}

// Asks the map on screen for one more frame.
class Repaint extends FrameCallback {
  private readonly controller: MapController;

  constructor(controller: MapController) {
    super();
    this.controller = controller;
  }

  onFrame(frameTimeInNano: number): void {
    this.controller.map?.discarding.requestRepaint();
  }
}
