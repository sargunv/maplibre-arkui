// Examples for the "Capture a map image" guide.

import { AttributionText, color, MapContent, MapController, MaplibreMap, MapSnapshot, renderSnapshot } from '@maplibre/arkui';

import { PARIS, PLACES, STYLE } from './Common';

@ComponentV2
export struct SnapshotExample {
  // #region snapshot
  @Local snapshot: MapSnapshot | undefined = undefined;

  aboutToAppear(): void {
    renderSnapshot({
      style: STYLE,
      width: 320,
      height: 200,
      camera: { center: { latitude: 48.8584, longitude: 2.2945 }, zoom: 14 },
      uiContext: this.getUIContext(),
    }).then((snapshot: MapSnapshot) => {
      this.snapshot = snapshot;
    }).catch((error: Error) => console.error(error.message));
  }

  aboutToDisappear(): void {
    this.snapshot?.image.release();
  }

  build() {
    Column() {
      if (this.snapshot !== undefined) {
        Image(this.snapshot.image)
          .width(320)
          .height(200)
        AttributionText({ attributions: this.snapshot.attributions })
      }
    }
  }
  // #endregion snapshot
}

@ComponentV2
export struct SnapshotOfMapExample {
  @Local snapshot: MapSnapshot | undefined = undefined;
  private controller: MapController = new MapController({ camera: { center: PARIS, zoom: 13 } });
  private content: MapContent = {
    sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PLACES } }],
    layers: [{ id: 'places', type: 'circle', source: 'places', paint: { 'circle-color': color('#e53935') } }],
  };

  aboutToDisappear(): void {
    this.snapshot?.image.release();
  }

  // #region snapshot-of-map
  async captureMap(): Promise<MapSnapshot> {
    const camera = this.controller.camera;
    return renderSnapshot({
      style: STYLE,
      content: this.content,
      width: 320,
      height: 200,
      camera: { center: camera.center, zoom: camera.zoom, bearing: camera.bearing, pitch: camera.pitch },
      uiContext: this.getUIContext(),
    });
  }
  // #endregion snapshot-of-map

  build() {
    Column({ space: 8 }) {
      MaplibreMap({ style: STYLE, controller: this.controller, content: this.content })
        .layoutWeight(1)
      Button('Capture')
        .onClick(() => {
          this.captureMap().then((snapshot: MapSnapshot) => {
            this.snapshot?.image.release();
            this.snapshot = snapshot;
          }).catch((error: Error) => console.error(error.message));
        })
      if (this.snapshot !== undefined) {
        Image(this.snapshot.image)
          .width(320)
          .height(200)
      }
    }
  }
}
