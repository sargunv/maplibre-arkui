// Examples for the "Add data to the map" guide.

import {
  color,
  fp,
  GeoJsonFeature,
  GeoJsonFeatureCollection,
  get,
  image,
  interpolate,
  LayerSummary,
  linear,
  literal,
  MapContent,
  MapController,
  MaplibreMap,
  zoom,
} from '@maplibre/arkui';

import { PARIS, PLACES, STYLE } from './Common';

@ComponentV2
export struct GeoJsonExample {
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 12 } });

  // #region geojson
  @Local places: GeoJsonFeatureCollection = PLACES;

  @Computed
  get content(): MapContent {
    return {
      sources: [{ id: 'places', json: { 'type': 'geojson', 'data': this.places } }],
      layers: [
        {
          id: 'places', type: 'circle', source: 'places',
          paint: { 'circle-radius': 8, 'circle-color': color($r('app.color.place')) },
        },
      ],
    };
  }

  build() {
    MaplibreMap({ style: STYLE, controller: this.controller, content: this.content })
  }
  // #endregion geojson

  // #region update-data
  addPlace(place: GeoJsonFeature): void {
    this.places = { type: 'FeatureCollection', features: this.places.features.concat([place]) };
  }
  // #endregion update-data
}

@ComponentV2
export struct ExpressionLayerExample {
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 12 } });

  @Computed
  get content(): MapContent {
    return {
      sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PLACES } }],
      layers: [
        // #region expressions
        {
          id: 'places', type: 'circle', source: 'places',
          paint: {
            'circle-radius': interpolate(linear(), zoom(), [[10, 3], [16, 12]]),
            'circle-color': color($r('app.color.place')),
          },
        },
        // #endregion expressions
        // #region labels
        {
          id: 'names', type: 'symbol', source: 'places',
          layout: {
            'text-field': get('name'),
            'text-font': literal(['Noto Sans Regular']),
            'text-size': fp(14),
            'text-anchor': 'top',
          },
        },
        // #endregion labels
      ],
    };
  }

  build() {
    MaplibreMap({ style: STYLE, controller: this.controller, content: this.content })
  }
}

@ComponentV2
export struct BelowLabelsExample {
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 12 } });

  @Computed
  get content(): MapContent {
    return {
      sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PLACES } }],
      layers: [
        // #region below
        {
          id: 'places', type: 'circle', source: 'places',
          paint: { 'circle-radius': 40, 'circle-color': color($r('app.color.place')), 'circle-opacity': 0.5 },
          below: (layer: LayerSummary) => layer.type === 'symbol',
        },
        // #endregion below
      ],
    };
  }

  build() {
    MaplibreMap({ style: STYLE, controller: this.controller, content: this.content })
  }
}

@ComponentV2
export struct ImageExample {
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 12 } });

  @Computed
  get content(): MapContent {
    return {
      sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PLACES } }],
      layers: [
        // #region image
        {
          id: 'pins', type: 'symbol', source: 'places',
          layout: { 'icon-image': image($r('app.media.pin')), 'icon-anchor': 'bottom' },
        },
        // #endregion image
      ],
    };
  }

  build() {
    MaplibreMap({ style: STYLE, controller: this.controller, content: this.content })
  }
}

@ComponentV2
export struct SdfImageExample {
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 12 } });

  @Computed
  get content(): MapContent {
    return {
      sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PLACES } }],
      layers: [
        // #region sdf
        {
          id: 'pins', type: 'symbol', source: 'places',
          layout: { 'icon-image': image($r('app.media.pin'), { drawAsSdf: true }), 'icon-anchor': 'bottom' },
          paint: { 'icon-color': color($r('app.color.place')) },
        },
        // #endregion sdf
      ],
    };
  }

  build() {
    MaplibreMap({ style: STYLE, controller: this.controller, content: this.content })
  }
}
