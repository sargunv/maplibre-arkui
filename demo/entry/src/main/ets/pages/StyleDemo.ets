import { FrameCallback } from '@ohos.arkui.UIContext';
import image from '@ohos.multimedia.image';

import {
  all,
  cases,
  CommandCompletion,
  eq,
  featureState,
  FeatureStateSelector,
  GeoJsonFeature,
  GeoJsonFeatureCollection,
  geometryType,
  get,
  MapController,
  MapLibreMap,
  match,
  readPixelMap,
  RenderedFeature,
  toBoolean,
} from '@maplibre/arkui';

const LIBERTY = 'https://tiles.openfreemap.org/styles/liberty';
const DEMOTILES = 'https://demotiles.maplibre.org/style.json';

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

const QUERIED = ['paris-pins', 'paris-places', 'paris-walk', 'paris-park'];

// Paint that reads the feature's `selected` state, which a tap sets.
const SELECTED = toBoolean(featureState('selected'));
const SELECTED_STATE: Record<string, Object> = { 'selected': true };

function parkLayer(): Record<string, Object> {
  const paint: Record<string, Object> = {
    'fill-color': cases([[SELECTED, '#2e7d32']], '#66bb6a'),
    'fill-opacity': 0.6,
  };
  return { 'id': 'paris-park', 'type': 'fill', 'source': 'paris', 'filter': eq(geometryType(), 'Polygon'),
    'paint': paint };
}

function walkLayer(): Record<string, Object> {
  const layout: Record<string, Object> = { 'line-cap': 'round', 'line-join': 'round' };
  const paint: Record<string, Object> = {
    'line-color': '#5e35b1',
    'line-width': cases([[SELECTED, 9]], 5),
  };
  return { 'id': 'paris-walk', 'type': 'line', 'source': 'paris', 'filter': eq(geometryType(), 'LineString'),
    'layout': layout, 'paint': paint };
}

function placesLayer(visible: boolean): Record<string, Object> {
  const layout: Record<string, Object> = { 'visibility': visible ? 'visible' : 'none' };
  const paint: Record<string, Object> = {
    'circle-radius': cases([[SELECTED, 12]], 8),
    'circle-color': match(get('kind'), [['museum', '#fb8c00'], ['monument', '#1e88e5']], '#757575'),
    'circle-stroke-width': cases([[SELECTED, 4]], 2),
    'circle-stroke-color': cases([[SELECTED, '#e53935']], '#ffffff'),
  };
  return { 'id': 'paris-places', 'type': 'circle', 'source': 'paris', 'filter': eq(geometryType(), 'Point'),
    'layout': layout, 'paint': paint };
}

// A pin from the app's resources over each monument.
function pinsLayer(): Record<string, Object> {
  const layout: Record<string, Object> = {
    'icon-image': 'pin',
    'icon-anchor': 'bottom',
    'icon-allow-overlap': true,
  };
  return { 'id': 'paris-pins', 'type': 'symbol', 'source': 'paris',
    'filter': all(eq(geometryType(), 'Point'), eq(get('kind'), 'monument')), 'layout': layout };
}

// Decodes an image from the app's rawfile resources into a pixel map. (This
// repository's build can't compile `$r()` yet; see AGENTS.md.)
function loadPin(context: UIContext): image.PixelMap {
  const bytes = context.getHostContext()!.resourceManager.getRawFileContentSync('pin.png');
  const source = image.createImageSource(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  try {
    return source.createPixelMapSync();
  } finally {
    source.release();
  }
}

// A map whose style the app adds to: a GeoJSON source, layers styled with
// expressions, an icon from the app's resources, a layer that hides, and
// feature state that a tap sets on the feature it finds.
@ComponentV2
export struct StyleDemo {
  @Local style: string = LIBERTY;
  @Local placesShown: boolean = true;
  @Local message: string = 'Tap a place, the walk, or the park';
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8570, longitude: 2.2965 }, zoom: 13.6 },
  });
  private pin: image.PixelMap | undefined = undefined;
  private selected: FeatureStateSelector | undefined = undefined;

  aboutToAppear(): void {
    this.pin = loadPin(this.getUIContext());
  }

  aboutToDisappear(): void {
    this.pin?.release();
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        MapLibreMap({
          controller: this.controller,
          style: this.style,
          onStyleLoaded: () => this.addToStyle(),
          onMapError: (error: Error) => {
            this.message = error.message;
          },
        })
          .onClick((event: ClickEvent) => {
            this.select(event.x, event.y);
          })
        Column({ space: 8 }) {
          Text(this.message)
            .fontSize(14)
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            Button(this.placesShown ? 'Hide circles' : 'Show circles').margin(4).onClick(() => this.togglePlaces())
            Button(this.style === LIBERTY ? 'Demo tiles' : 'Liberty').margin(4).onClick(() => {
              this.style = this.style === LIBERTY ? DEMOTILES : LIBERTY;
            })
          }
        }
        .padding(12)
        .margin({ left: 12, right: 12, bottom: 32 })
        .borderRadius(16)
        .backgroundColor('#e6ffffff')
      }
      .width('100%')
      .height('100%')
    }
    .title('Style')
  }

  // Each style starts from its own document, so the app adds its image,
  // source, and layers each time one loads. The map runs the commands in
  // order.
  private addToStyle(): void {
    const map = this.controller.map;
    if (map === undefined) {
      return;
    }
    const added: Promise<CommandCompletion>[] = [];
    if (this.pin !== undefined) {
      added.push(map.setStyleImage('pin', readPixelMap(this.pin), { pixelRatio: 3 }));
    }
    const source: Record<string, Object> = { 'type': 'geojson', 'data': PARIS };
    added.push(map.addStyleSourceJson('paris', source));
    added.push(map.addStyleLayerJson(parkLayer()));
    added.push(map.addStyleLayerJson(walkLayer()));
    added.push(map.addStyleLayerJson(placesLayer(this.placesShown)));
    added.push(map.addStyleLayerJson(pinsLayer()));
    Promise.all(added).catch((error: Error) => {
      this.message = error.message;
    });
  }

  private togglePlaces(): void {
    this.placesShown = !this.placesShown;
    this.controller.map?.setStyleLayerProperty('paris-places', 'visibility', this.placesShown ? 'visible' : 'none')
      .catch((error: Error) => {
        this.message = error.message;
      });
  }

  // A click's point is in vp from the map's top-left corner, as the render
  // session's queries take it.
  private async select(x: number, y: number): Promise<void> {
    const map = this.controller.map;
    const session = this.controller.renderSession;
    if (map === undefined || session === undefined) {
      return;
    }
    try {
      const hits = await session.queryRenderedFeatures({ kind: 'point', value: { x: x, y: y } },
        { layerIds: QUERIED });
      const where = `at ${x.toFixed(0)}, ${y.toFixed(0)} vp`;
      const hit: RenderedFeature | undefined = hits.length > 0 ? hits[0] : undefined;
      const feature = hit?.feature as GeoJsonFeature | undefined;
      this.message = hit === undefined ? `Nothing here ${where}` :
        `${feature?.properties?.['name']} in ${hit.layerId} ${where}` +
          (hits.length > 1 ? `, over ${hits.length - 1} more` : '');

      if (this.selected !== undefined) {
        await map.removeFeatureState(this.selected);
        this.selected = undefined;
      }
      if (hit !== undefined && feature?.id !== undefined) {
        // The map compares feature IDs as text.
        this.selected = { sourceId: hit.sourceId, featureId: { kind: 'stringValue', value: `${feature.id}` } };
        await map.setFeatureState(this.selected, SELECTED_STATE);
      }
      // FFI draws a feature state change only from the frame after the one
      // that applies it, so ask for that frame. See docs/ffi-feedback.md.
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
