// The public API of @maplibre/arkui.

export { MapLibreMap } from './src/main/ets/MapLibreMap';
export { MapController } from './src/main/ets/MapController';
export type { MapControllerOptions } from './src/main/ets/MapController';
export { addRuntimeEventListener, getDefaultRuntime, removeRuntimeEventListener } from './src/main/ets/runtime';
export type { RuntimeEventListener } from './src/main/ets/runtime';
export { snapshot } from './src/main/ets/Snapshot';
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
