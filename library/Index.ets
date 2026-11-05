// The public API of @maplibre/arkui.

export { MapLibreMap } from './src/main/ets/MapLibreMap';
export { MapController } from './src/main/ets/MapController';
export type { MapControllerOptions } from './src/main/ets/MapController';
export { getDefaultRuntime } from './src/main/ets/runtime';

// The FFI types that the API takes and returns, so apps needn't depend on FFI
// themselves for them.
export {
  cameraToOptions,
  CameraTransitionOutcome,
  CameraUpdateMode,
  MapHandle,
  RenderSessionHandle,
  RuntimeHandle,
} from '@maplibre/native-ffi';
export type {
  AnimationOptions,
  BoundOptions,
  Camera as CameraPosition,
  CameraFitOptions,
  CameraFitUpdate,
  CameraOptions,
  CameraTransitionEnd,
  CameraUpdate,
  EdgeInsets,
  LatLng,
  LatLngBounds,
} from '@maplibre/native-ffi';

export * from './src/main/ets/Expressions';
