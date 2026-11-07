// Clicks on the test page's map and its content's layers, from real input
// injected with UiTest's Driver, as in GestureInput.test.ets.

import { beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  GeoJsonFeatureCollection,
  MapClickEvent,
  MapContent,
  MapLayer,
  RenderedFeature,
} from '@maplibre/arkui';
import { Driver, MouseButton } from '@ohos.UiTest';

import { STYLE, testMap } from '../testability/TestMaps';
import { camera, expectNear, frames, inMap, mapBounds, mapCenter, offset, until } from './helpers';

const ZOOM = 3;

// A square around the origin, larger than the map shows at ZOOM, and a point
// at the origin.
const PLACES: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: [
    {
      type: 'Feature', id: 1, properties: { 'name': 'square' },
      geometry: { type: 'Polygon', coordinates: [[[-90, -60], [90, -60], [90, 60], [-90, 60], [-90, -60]]] },
    },
    { type: 'Feature', id: 2, properties: { 'name': 'dot' }, geometry: { type: 'Point', coordinates: [0, 0] } },
  ],
};

// Whether each layer's handlers consume the clicks they get, by layer ID.
let consuming: Set<string> = new Set<string>();

// Records a click on the features of layer `id` as `what`, or as 'wrong
// features' unless they're the layer's.
function record(id: string, what: string, features: RenderedFeature[], event: MapClickEvent): boolean {
  const own = features.length > 0 && features.every((feature: RenderedFeature) => feature.layerId === id);
  return testMap.click(own ? what : 'wrong features', event, consuming.has(id));
}

function fill(id: string): MapLayer {
  return {
    id: id, type: 'fill', source: 'places', paint: { 'fill-opacity': 0.2 },
    onClick: (features: RenderedFeature[], event: MapClickEvent): boolean => record(id, id, features, event),
    onLongClick: (features: RenderedFeature[], event: MapClickEvent): boolean =>
      record(id, `${id} long`, features, event),
  };
}

// A small circle at the origin, which a click within `hitPadding` vp of it
// hits.
function dot(hitPadding: number): MapLayer {
  return {
    id: 'dot', type: 'circle', source: 'places', paint: { 'circle-radius': 3 }, hitPadding: hitPadding,
    onClick: (features: RenderedFeature[], event: MapClickEvent): boolean => record('dot', 'dot', features, event),
  };
}

// Shows `layers` over the places, and waits until a query finds them.
async function show(layers: MapLayer[]): Promise<void> {
  const content: MapContent = {
    sources: [{ id: 'places', json: { 'type': 'geojson', 'data': PLACES } }],
    layers: layers,
  };
  testMap.content = content;
  const ids = layers.map((layer: MapLayer) => layer.id);
  let found = false;
  await until('the layers draw', () => {
    const session = testMap.controller.renderSession;
    const c = testMap.controller.pixelForLatLng({ latitude: 0, longitude: 0 });
    if (session !== undefined && c !== undefined) {
      session.queryRenderedFeatures({ kind: 'point', value: c }, { layerIds: ids })
        .then((hits: readonly RenderedFeature[]) => {
          found = ids.every((id: string) => hits.some((hit: RenderedFeature) => hit.layerId === id));
        });
    }
    return found;
  });
}

// Waits for `n` clicks, then a while longer than the wait for a second tap,
// so a click that was to come has come.
async function settle(n: number): Promise<void> {
  await until(`${n} clicks arrive`, () => testMap.clicks.length >= n);
  await frames(40);
}

export default function clicksTest(): void {
  describe('Clicks', () => {
    const driver = Driver.create();

    beforeEach(async () => {
      consuming = new Set<string>();
      await testMap.reset(STYLE);
      await testMap.controller.updateCamera({ zoom: ZOOM });
    });

    it('gives a click to the map, then its layers from the top down, until one consumes it', 0, async () => {
      await show([fill('bottom'), fill('top')]);
      const c = await mapCenter();
      await driver.click(c.x, c.y);
      await settle(4);
      expect(JSON.stringify(testMap.clicks)).assertEqual('["click","top","bottom","unhandled"]');
      // Each got the click's point, to within the input's rounding to px, and
      // the coordinate under it.
      const at = inMap(await mapBounds(), c);
      for (const event of testMap.clickEvents) {
        expectNear(event.x, at.x, 1);
        expectNear(event.y, at.y, 1);
        expectNear(event.coordinate.longitude, 0, 0.2);
        expectNear(event.coordinate.latitude, 0, 0.2);
      }

      testMap.clicks = [];
      consuming.add('top');
      await driver.click(c.x, c.y);
      await settle(2);
      expect(JSON.stringify(testMap.clicks)).assertEqual('["click","top"]');

      testMap.clicks = [];
      testMap.consumeClicks = true;
      await driver.click(c.x, c.y);
      await settle(1);
      expect(JSON.stringify(testMap.clicks)).assertEqual('["click"]');
    });

    it('hits features within a layer\'s hitPadding', 0, async () => {
      const beside = offset(await mapCenter(), 20, 0);
      await show([dot(0)]);
      await driver.click(beside.x, beside.y);
      await settle(2);
      expect(JSON.stringify(testMap.clicks)).assertEqual('["click","unhandled"]');

      testMap.clicks = [];
      await show([dot(25)]);
      await driver.click(beside.x, beside.y);
      await settle(3);
      expect(JSON.stringify(testMap.clicks)).assertEqual('["click","dot","unhandled"]');
    });

    it('zooms at a double tap without a click', 0, async () => {
      await show([fill('top')]);
      const c = await mapCenter();
      await driver.doubleClick(c.x, c.y);
      await until('the map zooms', () => camera().zoom > ZOOM + 0.99);
      await frames(40);
      expect(JSON.stringify(testMap.clicks)).assertEqual('[]');
    });

    it('gives a long press and a right click to the long click handlers', 0, async () => {
      await show([fill('top')]);
      const c = await mapCenter();
      await driver.longClick(c.x, c.y);
      await settle(2);
      expect(JSON.stringify(testMap.clicks)).assertEqual('["long click","top long"]');

      testMap.clicks = [];
      await driver.mouseClick(c, MouseButton.MOUSE_BUTTON_RIGHT);
      await settle(2);
      expect(JSON.stringify(testMap.clicks)).assertEqual('["long click","top long"]');
    });
  });
}
