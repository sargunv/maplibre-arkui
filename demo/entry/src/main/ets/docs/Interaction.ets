// Examples for the "Handle gestures and clicks" guide.

import {
  color,
  FeatureClickEvent,
  MapClickEvent,
  MapContent,
  MapController,
  MaplibreMap,
} from '@maplibre/arkui';

import { PARIS, PLACES, STYLE } from './Common';

@ComponentV2
export struct RestrictExample {
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 12 } });

  build() {
    // #region restrict
    MaplibreMap({
      style: STYLE,
      controller: this.controller,
      interactions: { rotate: { enabled: false }, pitch: { enabled: false } },
    })
    // #endregion restrict
  }
}

@ComponentV2
export struct PanStartExample {
  // #region pan-start
  @Local followingVehicle: boolean = true;

  build() {
    MaplibreMap({
      style: STYLE,
      interactions: {
        pan: {
          onStart: () => {
            this.followingVehicle = false;
          },
        },
      },
    })
  }
  // #endregion pan-start
}

@ComponentV2
export struct MapClickExample {
  @Local dropped: string = '';

  build() {
    // #region map-click
    MaplibreMap({
      style: STYLE,
      onMapLongClick: (event: MapClickEvent): boolean => {
        this.dropped = `${event.coordinate.latitude.toFixed(4)}, ${event.coordinate.longitude.toFixed(4)}`;
        return true;
      },
    })
    // #endregion map-click
  }
}

@ComponentV2
export struct LayerClickExample {
  @Local selected: string | undefined = undefined;
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 12 } });

  // #region layer-click
  @Computed
  get content(): MapContent {
    return {
      sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PLACES } }],
      layers: [
        {
          id: 'places', type: 'circle', source: 'places',
          paint: { 'circle-radius': 6, 'circle-color': color('#e53935') },
          hitPadding: 8,
          onClick: (event: FeatureClickEvent): boolean => {
            this.selected = `${event.features[0].properties?.['name']}`;
            return true;
          },
        },
      ],
    };
  }

  build() {
    MaplibreMap({
      style: STYLE,
      controller: this.controller,
      content: this.content,
      onUnhandledClick: () => {
        this.selected = undefined;
      },
    })
  }
  // #endregion layer-click
}

@ComponentV2
export struct CooperativeExample {
  build() {
    // #region cooperative
    Scroll() {
      Column({ space: 16 }) {
        Text('Getting here')
        MaplibreMap({ style: STYLE, interactions: { cooperative: true } })
          .height(300)
        Text('Opening hours')
      }
    }
    // #endregion cooperative
  }
}
