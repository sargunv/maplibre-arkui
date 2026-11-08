// Examples for the "Query and highlight features" guide.

import {
  color,
  CameraTransitionMode,
  cases,
  eq,
  FeatureClickEvent,
  featureState,
  GeoJsonFeature,
  GeoJsonPoint,
  GeoJsonSourceHandle,
  get,
  has,
  MapClickEvent,
  MapContent,
  MapController,
  MaplibreMap,
  not,
  RenderedFeature,
  SourceFeature,
  toBoolean,
} from '@maplibre/arkui';

import { PARIS, PLACES, STYLE } from './Common';

@ComponentV2
export struct QueryRenderedExample {
  @Local names: string[] = [];
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 16 } });

  build() {
    MaplibreMap({
      style: STYLE,
      controller: this.controller,
      onMapClick: (event: MapClickEvent): boolean => {
        this.findPlaces(event).catch((error: Error) => console.error(error.message));
        return false;
      },
    })
  }

  // #region query-rendered
  private async findPlaces(event: MapClickEvent): Promise<void> {
    const hits: RenderedFeature[] | undefined = await this.controller.queryRenderedFeatures(event.point, {
      hitPadding: 20,
      layers: ['poi_r1', 'poi_r7', 'poi_r20'],
    });
    this.names = (hits ?? []).map((hit: RenderedFeature) => `${hit.feature.properties?.['name']}`);
  }
  // #endregion query-rendered
}

// #region query-source
async function findCafes(controller: MapController): Promise<string[]> {
  const cafes: SourceFeature[] | undefined = await controller.querySourceFeatures('openmaptiles', {
    sourceLayers: ['poi'],
    filter: eq(get('class'), 'cafe'),
  });
  return (cafes ?? []).map((cafe: SourceFeature) => `${cafe.feature.properties?.['name']}`);
}
// #endregion query-source

@ComponentV2
export struct HighlightExample {
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 12 } });
  private places: GeoJsonSourceHandle | undefined = undefined;
  private selected: number | string | undefined = undefined;

  // #region highlight-paint
  @Computed
  get content(): MapContent {
    return {
      sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PLACES } }],
      layers: [
        {
          id: 'places', type: 'circle', source: 'places',
          paint: {
            'circle-radius': 8,
            'circle-color': cases([[toBoolean(featureState('selected')), color('#e53935')]], color('#1e88e5')),
          },
          onClick: (event: FeatureClickEvent): boolean => {
            this.select(event.features[0]).catch((error: Error) => console.error(error.message));
            return true;
          },
        },
      ],
    };
  }
  // #endregion highlight-paint

  build() {
    // #region highlight-handle
    MaplibreMap({
      style: STYLE,
      controller: this.controller,
      content: this.content,
      onStyleLoaded: () => {
        this.controller.style.getGeoJsonSource('places').then((places: GeoJsonSourceHandle | undefined) => {
          this.places = places;
        });
      },
    })
    // #endregion highlight-handle
  }

  // #region highlight-select
  private async select(place: GeoJsonFeature): Promise<void> {
    if (this.places === undefined || place.id === undefined) {
      return;
    }
    if (this.selected !== undefined) {
      this.places.removeFeatureState(this.selected).catch((error: Error) => console.error(error.message));
    }
    this.selected = place.id;
    await this.places.setFeatureState(place.id, { 'selected': true });
  }
  // #endregion highlight-select
}

@ComponentV2
export struct ClusterExample {
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 11 } });

  // #region clusters
  @Computed
  get content(): MapContent {
    return {
      sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PLACES, 'cluster': true } }],
      layers: [
        {
          id: 'clusters', type: 'circle', source: 'places', filter: has('point_count'),
          paint: { 'circle-radius': 16, 'circle-color': color('#1e88e5') },
          onClick: (event: FeatureClickEvent): boolean => {
            this.expand(event.features[0]).catch((error: Error) => console.error(error.message));
            return true;
          },
        },
        {
          id: 'places', type: 'circle', source: 'places', filter: not(has('point_count')),
          paint: { 'circle-radius': 8, 'circle-color': color('#e53935') },
        },
      ],
    };
  }

  private async expand(cluster: GeoJsonFeature): Promise<void> {
    const places = await this.controller.style.getGeoJsonSource('places');
    const zoom = await places?.getClusterExpansionZoom(cluster);
    if (zoom !== undefined && cluster.geometry?.type === 'Point') {
      const position = (cluster.geometry as GeoJsonPoint).coordinates;
      await this.controller.updateCamera(
        { center: { latitude: position[1], longitude: position[0] }, zoom: zoom },
        { mode: CameraTransitionMode.EASE });
    }
  }
  // #endregion clusters

  build() {
    MaplibreMap({ style: STYLE, controller: this.controller, content: this.content })
  }
}

export const FEATURE_FUNCTIONS: Object[] = [findCafes];
