import {
  all,
  AttributionText,
  cases,
  color,
  eq,
  FeatureClickEvent,
  FeatureClickHandler,
  featureState,
  GeoJsonFeature,
  GeoJsonFeatureCollection,
  GeoJsonSourceHandle,
  geometryType,
  get,
  image,
  LatLng,
  LayerHandle,
  LayerSummary,
  MapClickEvent,
  MapContent,
  MapController,
  MapError,
  MaplibreMap,
  MapSnapshot,
  match,
  renderSnapshot,
  StyleLayer,
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
function parkLayer(fill: string, onClick: FeatureClickHandler): StyleLayer {
  return {
    id: 'paris-park', type: 'fill', source: 'paris', filter: eq(geometryType(), 'Polygon'),
    paint: { 'fill-color': cases([[SELECTED, color('#2e7d32')]], color(fill)), 'fill-opacity': 0.6 },
    below: (layer: LayerSummary) => layer.type === 'symbol',
    onClick: onClick,
  };
}

// The line is thin, so a click 8 vp beside it counts.
function walkLayer(onClick: FeatureClickHandler): StyleLayer {
  return {
    id: 'paris-walk', type: 'line', source: 'paris', filter: eq(geometryType(), 'LineString'),
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': color('#5e35b1'), 'line-width': cases([[SELECTED, 9]], 5) },
    onClick: onClick,
    hitPadding: 8,
  };
}

function placesLayer(onClick: FeatureClickHandler): StyleLayer {
  return {
    id: 'paris-places', type: 'circle', source: 'paris', filter: eq(geometryType(), 'Point'),
    paint: {
      'circle-radius': cases([[SELECTED, 12]], 8),
      'circle-color': match(get('kind'),
        [['museum', color('#fb8c00')], ['monument', color('#1e88e5')], ['added', color('#e53935')]], color('#757575')),
      'circle-stroke-width': cases([[SELECTED, 4]], 2),
      'circle-stroke-color': cases([[SELECTED, color('#e53935')]], color('#ffffff')),
    },
    onClick: onClick,
  };
}

// A pin from the app's resources over each monument.
function pinsLayer(onClick: FeatureClickHandler): StyleLayer {
  return {
    id: 'paris-pins', type: 'symbol', source: 'paris',
    filter: all(eq(geometryType(), 'Point'), eq(get('kind'), 'monument')),
    layout: { 'icon-image': image($r('app.media.pin')), 'icon-anchor': 'bottom', 'icon-allow-overlap': true },
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

// A map whose content comes from the page's state: a GeoJSON source, layers
// styled with expressions, and an icon from the app's resources. The buttons
// change the state, and the map applies the change, in each base style. The
// style API hides the base style's 3D buildings, and a tap on a feature
// selects it with feature state. A long press adds a point.
@ComponentV2
export struct StyleDemo {
  @Local style: string = LIBERTY;
  @Local placesShown: boolean = true;
  @Local buildingsShown: boolean = true;
  @Local parkColor: number = 0;
  @Local added: GeoJsonFeature[] = [];
  @Local preview: MapSnapshot | undefined = undefined;
  @Local message: string = 'Tap a place, the walk, or the park; long press to add a point';
  private controller: MapController = new MapController({
    camera: { center: { latitude: 48.8570, longitude: 2.2965 }, zoom: 13.6 },
  });
  // The content's source in the current style, and the ID of the feature
  // that a tap selected in it.
  private places: GeoJsonSourceHandle | undefined = undefined;
  private selected: number | string | undefined = undefined;
  private gone: boolean = false;
  // The layers are on top of each other, so the topmost feature under a click
  // takes it, and the layers under it don't get it.
  private onFeatureClick = (layer: string): FeatureClickHandler => (event: FeatureClickEvent): boolean => {
    this.select(event, event.features[0], layer);
    return true;
  };

  // What the map draws over its style. It changes when the state it reads
  // does, and the map changes only what differs.
  @Computed
  get content(): MapContent {
    const places: GeoJsonFeatureCollection = { type: 'FeatureCollection', features: PARIS.features.concat(this.added) };
    const layers: StyleLayer[] = [parkLayer(PARK_COLORS[this.parkColor], this.onFeatureClick('paris-park')),
      walkLayer(this.onFeatureClick('paris-walk'))];
    if (this.placesShown) {
      layers.push(placesLayer(this.onFeatureClick('paris-places')));
    }
    layers.push(pinsLayer(this.onFeatureClick('paris-pins')));
    return {
      sources: [{ id: 'paris', json: { 'type': 'geojson', 'data': places } }],
      layers: layers,
    };
  }

  aboutToDisappear(): void {
    this.gone = true;
    this.preview?.image.release();
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        MaplibreMap({
          style: this.style,
          controller: this.controller,
          content: this.content,
          onError: (error: MapError) => {
            this.message = error.message;
          },
          // Each style starts with its buildings as its document has them,
          // and the page selects the feature again in it.
          onStyleLoaded: () => {
            this.showBuildings();
            this.findPlaces();
          },
          // A click that no feature took clears the selection.
          onUnhandledClick: (event: MapClickEvent) => {
            this.select(event);
          },
          onMapLongClick: (event: MapClickEvent): boolean => {
            this.added = this.added.concat([addedPoint(this.added.length, event.coordinate)]);
            return true;
          },
        })
        if (this.preview !== undefined) {
          Column() {
            Image(this.preview.image)
              .width(160)
              .height(120)
              .borderRadius(8)
              .borderWidth(2)
              .borderColor('#ffffff')
            AttributionText({ attributions: this.preview.attributions })
              .width(160)
              .backgroundColor('#ccffffff')
          }
          .position({ top: 12, right: 12 })
          .onClick(() => {
            this.preview?.image.release();
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
            Button(this.buildingsShown ? 'Hide buildings' : 'Show buildings').margin(4).onClick(() => {
              this.buildingsShown = !this.buildingsShown;
              this.showBuildings();
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

  // Shows or hides each of the base style's 3D building layers, as the page's
  // state says. The content's layers take their properties from the content.
  private async showBuildings(): Promise<void> {
    try {
      const layers: LayerHandle[] = await this.controller.style.getLayers() ?? [];
      const visibility = this.buildingsShown ? 'visible' : 'none';
      await Promise.all(layers.filter((layer: LayerHandle) => !layer.fromContent && layer.type === 'fill-extrusion')
        .map((layer: LayerHandle) => layer.setProperty('visibility', visibility)));
    } catch (error) {
      this.message = (error as Error).message;
    }
  }

  // Takes the new style's source, and selects the feature again in it.
  private async findPlaces(): Promise<void> {
    this.places = undefined;
    try {
      const places = await this.controller.style.getGeoJsonSource('paris');
      this.places = places;
      if (places !== undefined && this.selected !== undefined) {
        await places.setFeatureState(this.selected, SELECTED_STATE);
      }
    } catch (error) {
      this.message = (error as Error).message;
    }
  }

  // A still image of the same style, content, and camera, without the camera
  // padding.
  private async takeSnapshot(): Promise<void> {
    try {
      const camera = this.controller.camera;
      const preview = await renderSnapshot({
        style: this.style,
        content: this.content,
        camera: { center: camera.center, zoom: camera.zoom, bearing: camera.bearing, pitch: camera.pitch },
        width: 160,
        height: 120,
        uiContext: this.getUIContext(),
      });
      if (this.gone) {
        preview.image.release();
        return;
      }
      this.preview?.image.release();
      this.preview = preview;
    } catch (error) {
      this.message = (error as Error).message;
    }
  }

  // Selects the feature that a click hit, or nothing.
  private async select(event: MapClickEvent, feature?: GeoJsonFeature, layer?: string): Promise<void> {
    try {
      const where = `at ${event.point.x.toFixed(0)}, ${event.point.y.toFixed(0)} vp`;
      this.message = feature === undefined ? `Nothing here ${where}` :
        `${feature.properties?.['name']} in ${layer} ${where}`;

      // Every layer draws the paris source. Swap the selection before
      // awaiting, so a later tap's swap follows this one: the map applies the
      // changes in order.
      const places = this.places;
      if (places === undefined) {
        return;
      }
      const previous = this.selected;
      const next = feature?.id;
      this.selected = next;
      const changes: Promise<boolean>[] = [];
      if (previous !== undefined) {
        changes.push(places.removeFeatureState(previous));
      }
      if (next !== undefined) {
        changes.push(places.setFeatureState(next, SELECTED_STATE));
      }
      await Promise.all(changes);
    } catch (error) {
      this.message = (error as Error).message;
    }
  }
}
