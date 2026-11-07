// The style that the map showing a controller has loaded, which the style API
// acts on from onStyleLoaded until the style goes.

import { MapHandle } from '@maplibre/native-ffi';

import { ContentReconciler } from '../../content/internal/ContentReconciler';

export class LoadedStyle {
  readonly map: MapHandle;
  // The reconciler that applies the map's content to this style.
  readonly reconciler: ContentReconciler;

  constructor(map: MapHandle, reconciler: ContentReconciler) {
    this.map = map;
    this.reconciler = reconciler;
  }
}
