// The public API of @maplibre/arkui.

export { MapLibreMap } from './src/main/ets/MapLibreMap';
export { MapController } from './src/main/ets/MapController';
export type { MapControllerOptions } from './src/main/ets/MapController';
export type { MapGestureOptions } from './src/main/ets/gestures';
export { USER_LOCATION_LAYER } from './src/main/ets/location';
export type { FollowLocationOptions } from './src/main/ets/location';
export { addRuntimeEventListener, getDefaultRuntime, removeRuntimeEventListener } from './src/main/ets/runtime';
export type { RuntimeEventListener } from './src/main/ets/runtime';
export { snapshot } from './src/main/ets/Snapshot';
export type { LayerPredicate, MapContent, MapImage, MapLayer, MapSource } from './src/main/ets/Content';
export type { SnapshotOptions } from './src/main/ets/Snapshot';

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

// The FFI API for requests, offline regions, events, and logs, which apps call
// on a runtime.
export {
  CacheDatabaseOperation,
  clearLogCallback,
  getNetworkStatus,
  LogEvent,
  LogSeverity,
  LogSeverityFlag,
  NetworkStatus,
  OfflineRegionDownloadState,
  ResourceErrorReason,
  ResourceKind,
  ResourceKindFlag,
  ResourceRequestHandle,
  ResourceResponseStatus,
  ResourceTransformRequestHandle,
  RuntimeEventFlag,
  RuntimeEventSourceType,
  RuntimeEventType,
  setLogAsyncSeverityMask,
  setLogCallback,
  setNetworkStatus,
  UrlMatchFlag,
} from '@maplibre/native-ffi';
export type {
  LogHandler,
  OfflineGeometryRegionDefinition,
  OfflineRegionDefinition,
  OfflineRegionInfo,
  OfflineRegionStatus,
  OfflineTilePyramidRegionDefinition,
  ResourceProvider,
  ResourceRequestInfo,
  ResourceResponse,
  ResourceRoute,
  ResourceTransform,
  ResourceTransformError,
  ResourceTransformRule,
  RuntimeEvent,
  RuntimeEventPayload,
  RuntimeOptions,
  UrlQueryParameter,
} from '@maplibre/native-ffi';

// The style and query API is FFI's, through `MapController.map` and
// `MapController.renderSession`. These are the FFI types it takes and
// returns, and what ArkUI apps need besides.
export {
  GeoJsonSourceDataHandle,
  MaplibreError,
  MapProjectionHandle,
  Status,
  StyleLayerVisibility,
  StyleSourceType,
} from '@maplibre/native-ffi';
export type {
  CommandCompletion,
  FeatureId,
  FeatureStateSelector,
  GeoJsonSourceOptions,
  PremultipliedRgba8Image,
  RenderedFeature,
  RenderedFeatureQueryOptions,
  RenderedQueryGeometry,
  ScreenBox,
  ScreenPoint,
  SourceFeature,
  SourceFeatureQueryOptions,
  StyleImageInfo,
  StyleImageOptions,
  StyleLayerInfo,
  StyleSourceInfo,
} from '@maplibre/native-ffi';
export type { GeoJsonFeature, GeoJsonFeatureCollection, GeoJsonGeometry, GeoJsonPosition } from './src/main/ets/GeoJson';
export { readPixelMap } from './src/main/ets/StyleImage';

export { MapMarker } from './src/main/ets/MapMarker';
export { MapAttribution, MapCompass, MapScaleBar, MapZoomButtons, ScaleBarUnits } from './src/main/ets/Ornaments';
