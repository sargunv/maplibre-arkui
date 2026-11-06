// The public API of @maplibre/arkui.

export { MapLibreMap } from './src/main/ets/MapLibreMap';
export { MapController } from './src/main/ets/MapController';
export type { MapControllerOptions } from './src/main/ets/MapController';
export type { MapGestureOptions } from './src/main/ets/gestures';
export type { FollowUserLocationOptions } from './src/main/ets/location';
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
  GesturePhase,
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
  UnitBezier,
} from '@maplibre/native-ffi';

export * from './src/main/ets/Expressions';

// The FFI API for requests, offline regions, events, and logs, which apps call
// on a runtime.
export {
  CacheDatabaseOperation,
  CameraChangeMode,
  clearLogCallback,
  getNetworkStatus,
  LogEvent,
  LogSeverity,
  LogSeverityFlag,
  MapLoadError,
  NetworkStatus,
  OfflineRegionDownloadState,
  RenderMode,
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
  TileOperation,
  UrlMatchFlag,
} from '@maplibre/native-ffi';
export type {
  LogHandler,
  OfflineGeometryRegionDefinition,
  OfflineRegionDefinition,
  OfflineRegionInfo,
  OfflineRegionStatus,
  OfflineTilePyramidRegionDefinition,
  RenderingStats,
  ResourceProvider,
  ResourceRequestInfo,
  ResourceResponse,
  ResourceRoute,
  ResourceTransform,
  ResourceTransformError,
  ResourceTransformRule,
  RuntimeEvent,
  RuntimeEventCameraChange,
  RuntimeEventGlyphs,
  RuntimeEventLoadingFailed,
  RuntimeEventOfflineRegionResponseError,
  RuntimeEventOfflineRegionStatus,
  RuntimeEventOfflineRegionTileCountLimit,
  RuntimeEventPayload,
  RuntimeEventRenderFrame,
  RuntimeEventSourceChanged,
  RuntimeEventSprite,
  RuntimeEventStyleImage,
  RuntimeEventTileAction,
  RuntimeOptions,
  TileId,
  UrlQueryParameter,
} from '@maplibre/native-ffi';

// The style and query API is FFI's, through `MapController.map` and
// `MapController.renderSession`. These are the FFI types that its methods take
// and return, such as the debug, viewport, and tile options of `MapHandle`, and
// what ArkUI apps need besides.
export {
  ConstrainMode,
  GeoJsonSourceDataHandle,
  latLngForProjectedMeters,
  MapDebugFlag,
  MaplibreError,
  MapProjectionHandle,
  NorthOrientation,
  projectedMetersForLatLng,
  Status,
  StyleExpressionHandle,
  StyleExpressionTypeKind,
  StyleImageTextFit,
  StyleLayerVisibility,
  StyleRasterDemEncoding,
  StyleSourceType,
  StyleTileScheme,
  StyleVectorTileEncoding,
  TileLodMode,
  ViewportMode,
} from '@maplibre/native-ffi';
export type {
  CameraBounds,
  CameraDelta,
  CameraQueryResult,
  CanonicalTileId,
  CommandCompletion,
  CustomGeometrySourceOptions,
  CustomVectorSourceOptions,
  FeatureId,
  FeatureStateSelector,
  FreeCamera,
  FreeCameraOptions,
  GeoJsonSourceOptions,
  ImageContent,
  ImageStretch,
  LogicalExtent,
  MapProjectionCameraResult,
  MapSnapshot,
  MapTileOptions,
  MapTileSettings,
  MapView,
  MapViewport,
  MapViewportOptions,
  PremultipliedRgba8Image,
  ProjectedMeters,
  ProjectionMode,
  ProjectionModeOptions,
  Quaternion,
  RenderedFeature,
  RenderedFeatureQueryOptions,
  RenderedQueryGeometry,
  ScreenBox,
  ScreenPoint,
  SourceFeature,
  SourceFeatureQueryOptions,
  StyleExpressionInfo,
  StyleExpressionInputs,
  StyleExpressionOptions,
  StyleExpressionType,
  StyleImageInfo,
  StyleImageOptions,
  StyleLayerInfo,
  StyleSourceInfo,
  StyleSourceTileInfo,
  StyleTransitionOptions,
  Vec3,
} from '@maplibre/native-ffi';
export type { GeoJsonFeature, GeoJsonFeatureCollection, GeoJsonGeometry, GeoJsonPosition } from './src/main/ets/GeoJson';
export { readPixelMap } from './src/main/ets/StyleImage';

export { MapMarker } from './src/main/ets/MapMarker';
export { MapAttribution, MapCompass, MapScaleBar, MapZoomButtons, ScaleBarUnits } from './src/main/ets/Ornaments';
