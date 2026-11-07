// The style that the map showing a controller has loaded, which the style API
// acts on from onStyleLoaded until the style goes.

import { MapHandle, RenderSessionHandle } from '@maplibre/native-ffi';

import { ContentReconciler } from '../../content/internal/ContentReconciler';

export class LoadedStyle {
  readonly map: MapHandle;
  // The reconciler that applies the map's content to this style.
  readonly reconciler: ContentReconciler;
  // The render session of the map while it shows a frame, which answers the
  // cluster queries.
  readonly session: () => RenderSessionHandle | undefined;

  constructor(map: MapHandle, reconciler: ContentReconciler, session: () => RenderSessionHandle | undefined) {
    this.map = map;
    this.reconciler = reconciler;
    this.session = session;
  }
}
