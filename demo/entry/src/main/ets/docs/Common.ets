// Data that several guide examples share. The guides don't show this file.

import { GeoJsonFeatureCollection, LatLng } from '@maplibre/arkui';

export const STYLE = 'https://tiles.openfreemap.org/styles/liberty';

export const PARIS: LatLng = { latitude: 48.8566, longitude: 2.3522 };

export const PLACES: GeoJsonFeatureCollection = {
  type: 'FeatureCollection',
  features: [
    {
      type: 'Feature', id: 1, geometry: { type: 'Point', coordinates: [2.2945, 48.8584] },
      properties: { 'name': 'Eiffel Tower', 'kind': 'monument' },
    },
    {
      type: 'Feature', id: 2, geometry: { type: 'Point', coordinates: [2.3376, 48.8606] },
      properties: { 'name': 'Louvre', 'kind': 'museum' },
    },
    {
      type: 'Feature', id: 3, geometry: { type: 'Point', coordinates: [2.3266, 48.8600] },
      properties: { 'name': 'Musée d\'Orsay', 'kind': 'museum' },
    },
  ],
};
