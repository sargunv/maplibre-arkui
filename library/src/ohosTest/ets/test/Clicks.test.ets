// Clicks on the test page's map and its content's layers, from real input
// injected with UiTest's Driver, as in GestureInput.test.ets.

import { beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  FeatureClickEvent,
  GeoJsonFeature,
  GeoJsonFeatureCollection,
  MapContent,
  RenderedFeature,
  StyleLayer,
} from '@maplibre/arkui';
import { Driver, MouseButton, ON } from '@ohos.UiTest';

import { STYLE, testMap } from '../testability/TestMaps';
import {
  camera,
  eventually,
  expectNear,
  frames,
  inMap,
  mapBounds,
  mapCenter,
  near,
  offset,
  until,
  vp2px,
} from './helpers';

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

function names(event: FeatureClickEvent): string {
  return event.features.map((feature: GeoJsonFeature) => `${feature.properties?.['name']}`).join(',');
}

// Records a click on the features of layer `id` as `what`, or as 'wrong
// features' unless each is the one named `name`. A feature across tiles comes
// once from each tile that the click is in.
function record(id: string, what: string, name: string, event: FeatureClickEvent): boolean {
  const own = event.features.every((feature: GeoJsonFeature) => feature.properties?.['name'] === name);
  return testMap.click(own ? what : `wrong features: ${names(event)}`, event, consuming.has(id));
}

function fill(id: string): StyleLayer {
  return {
    id: id, type: 'fill', source: 'places', paint: { 'fill-opacity': 0.2 },
    onClick: (event: FeatureClickEvent): boolean => record(id, id, 'square', event),
    onLongClick: (event: FeatureClickEvent): boolean => record(id, `${id} long`, 'square', event),
  };
}

// A small circle at the origin, which a click within `hitPadding` vp of it
// hits.
function dot(hitPadding: number): StyleLayer {
  return {
    id: 'dot', type: 'circle', source: 'places', paint: { 'circle-radius': 3 }, hitPadding: hitPadding,
    onClick: (event: FeatureClickEvent): boolean => record('dot', 'dot', 'dot', event),
  };
}

// Shows `layers` over the places, or over `data`, and waits until a query
// finds them.
async function show(layers: StyleLayer[], data: GeoJsonFeatureCollection = PLACES): Promise<void> {
  const content: MapContent = {
    sources: [{ id: 'places', json: { 'type': 'geojson', 'data': data } }],
    layers: layers,
  };
  testMap.content = content;
  const ids = layers.map((layer: StyleLayer) => layer.id);
  await eventually('the layers draw', async () => {
    const c = testMap.controller.viewport?.project({ latitude: 0, longitude: 0 });
    const hits = c === undefined ? undefined : await testMap.controller.queryRenderedFeatures(c, { layers: ids });
    return hits !== undefined && ids.every((id: string) => hits.some((hit: RenderedFeature) => hit.layerId === id)) ?
      true : undefined;
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
        expectNear(event.point.x, at.x, 1);
        expectNear(event.point.y, at.y, 1);
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

    it('passes the click on from a layer handler that throws', 0, async () => {
      const throwing: StyleLayer = {
        id: 'top', type: 'fill', source: 'places', paint: { 'fill-opacity': 0.2 },
        onClick: (event: FeatureClickEvent): boolean => {
          testMap.click('top', event, true);
          throw new Error('the handler threw');
        },
      };
      await show([fill('bottom'), throwing]);
      const c = await mapCenter();
      await driver.click(c.x, c.y);
      await settle(4);
      expect(JSON.stringify(testMap.clicks)).assertEqual('["click","top","bottom","unhandled"]');
    });

    it('gives a layer\'s features front first', 0, async () => {
      // Two circles at the origin, where the later one draws over the first.
      const stacked: GeoJsonFeatureCollection = {
        type: 'FeatureCollection',
        features: [
          { type: 'Feature', id: 1, properties: { 'name': 'back' }, geometry: { type: 'Point', coordinates: [0, 0] } },
          { type: 'Feature', id: 2, properties: { 'name': 'front' }, geometry: { type: 'Point', coordinates: [0, 0] } },
        ],
      };
      const circles: StyleLayer = {
        id: 'circles', type: 'circle', source: 'places', paint: { 'circle-radius': 10 },
        onClick: (event: FeatureClickEvent): boolean => testMap.click(names(event), event, true),
      };
      await show([circles], stacked);
      const c = await mapCenter();
      await driver.click(c.x, c.y);
      await settle(2);
      expect(JSON.stringify(testMap.clicks)).assertEqual('["click","front,back"]');
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

    it('gives a tap on a marker to its onClick, and a tap beside it to the map', 0, async () => {
      // The marker's 20 by 10 vp box sits on the center of the map.
      testMap.clickableMarker = { latitude: 0, longitude: 0 };
      const box = await eventually('the marker shows', async () => {
        const marker = await driver.findComponent(ON.id('clickable-marker'));
        const bounds = marker === null ? undefined : await marker.getBounds();
        const c = await mapCenter();
        return bounds !== undefined && near((bounds.left + bounds.right) / 2, c.x, vp2px(1)) &&
          near((bounds.top + bounds.bottom) / 2, c.y, vp2px(1)) ? bounds : undefined;
      });
      await driver.click(Math.round((box.left + box.right) / 2), Math.round((box.top + box.bottom) / 2));
      await until('the marker gets the tap', () => testMap.markerClicks === 1);
      await frames(40);
      expect(JSON.stringify(testMap.clicks)).assertEqual('[]');

      const beside = offset(await mapCenter(), 40, 0);
      await driver.click(beside.x, beside.y);
      await settle(2);
      expect(JSON.stringify(testMap.clicks)).assertEqual('["click","unhandled"]');
      expect(testMap.markerClicks).assertEqual(1);
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
