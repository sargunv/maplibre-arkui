// The public API of @maplibre/arkui.

export { MaplibreMap } from './src/main/ets/MaplibreMap';
export { ContentError, MapError, StyleLoadError } from './src/main/ets/MapError';
export type { CameraIdleEvent } from './src/main/ets/CameraIdleEvent';
export type { MapClickEvent } from './src/main/ets/MapClickEvent';
export type { CameraBoundsOptions } from './src/main/ets/CameraBounds';
export { MapController } from './src/main/ets/MapController';
export type { MapControllerOptions } from './src/main/ets/MapController';
export type { Viewport } from './src/main/ets/Viewport';
export type {
  RenderedFeature,
  RenderedFeatureQueryOptions,
  SourceFeature,
  SourceFeatureQueryOptions,
} from './src/main/ets/Queries';
export { CameraTransitionMode } from './src/main/ets/CameraPosition';
export type {
  CameraPosition,
  CameraTransitionOptions,
  CameraUpdate,
  FitCameraOptions,
} from './src/main/ets/CameraPosition';
export type { LatLng, LatLngBounds, ScreenPoint } from './src/main/ets/Geometry';
export type {
  GeoJsonFeature,
  GeoJsonFeatureCollection,
  GeoJsonGeometry,
  GeoJsonGeometryCollection,
  GeoJsonLineString,
  GeoJsonMultiLineString,
  GeoJsonMultiPoint,
  GeoJsonMultiPolygon,
  GeoJsonObject,
  GeoJsonPoint,
  GeoJsonPolygon,
  GeoJsonPosition,
} from './src/main/ets/GeoJson';
export { WheelAction } from './src/main/ets/gestures';
export type { InteractionOptions, MovementOptions, RotationOptions } from './src/main/ets/gestures';
export { FollowBearing } from './src/main/ets/location';
export type { FollowUserLocationOptions, UserLocationIndicatorOptions } from './src/main/ets/location';
export { addRuntimeEventListener, getDefaultRuntime, removeRuntimeEventListener } from './src/main/ets/runtime';
export type { RuntimeEventListener } from './src/main/ets/runtime';
export { ConnectivityMode, getConnectivityMode, setConnectivityMode } from './src/main/ets/connectivity';
export { renderSnapshot } from './src/main/ets/Snapshot';
export type { MapSnapshot, MapSnapshotOptions } from './src/main/ets/Snapshot';
export type {
  FeatureClickEvent,
  FeatureClickHandler,
  LayerPredicate,
  LayerSummary,
  MapContent,
  StyleImage,
  StyleLayer,
  StyleSource,
} from './src/main/ets/Content';

// The FFI runtime that a map and a snapshot take.
export { RuntimeHandle } from '@maplibre/native-ffi';

export {
  abs,
  add,
  all,
  any,
  call,
  cases,
  ceil,
  coalesce,
  concat,
  cubicBezier,
  divide,
  downcase,
  eq,
  exponential,
  Expression,
  featureState,
  floor,
  format,
  fp,
  geometryType,
  get,
  globalState,
  gt,
  gte,
  has,
  heatmapDensity,
  id,
  image,
  interpolate,
  interpolateHcl,
  interpolateLab,
  Interpolation,
  linear,
  lineProgress,
  literal,
  lt,
  lte,
  match,
  max,
  min,
  mod,
  multiply,
  neq,
  not,
  pow,
  properties,
  rgb,
  rgba,
  round,
  sqrt,
  step,
  subtract,
  toBoolean,
  toColor,
  toNumber,
  toString,
  upcase,
  zoom,
} from './src/main/ets/Expressions';
export type {
  Condition,
  ExpressionInput,
  FormatSection,
  JsonObject,
  JsonValue,
  MatchCase,
  MatchLabel,
  Stop,
} from './src/main/ets/Expressions';

// The FFI API for requests, offline regions, events, and logs, which apps call
// on a runtime. FFI's `setNetworkStatus()` isn't here: `setConnectivityMode()`
// sets the status.
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

export { AttributionControls, DefaultControls, FullControls } from './src/main/ets/Overlay';
export {
  AttributionButton,
  AttributionText,
  CompassButton,
  DisappearingCompassButton,
  DisappearingScaleBar,
  MaplibreLogo,
  ScaleBar,
  ScaleBarUnits,
  ZoomButtons,
} from './src/main/ets/Controls';
export { Marker, OffscreenMarker, PointerPinButton } from './src/main/ets/Placement';
export type { OffscreenMarkerAngleEvent } from './src/main/ets/Placement';
