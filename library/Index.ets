// The public API of @maplibre/arkui, by feature, in the order of the guides.
// scripts/check-api-layout.sh checks that each top-level file under
// src/main/ets exports only what this file lists.

// Map
export type { CameraBoundsOptions } from './src/main/ets/map/CameraBoundsOptions';
export type { MapClickEvent } from './src/main/ets/map/MapClickEvent';
export { MapController } from './src/main/ets/map/MapController';
export type {
  MapControllerOptions,
  RenderedFeature,
  RenderedFeatureQueryOptions,
  SourceFeature,
  SourceFeatureQueryOptions,
} from './src/main/ets/map/MapController';
export { ContentError, MapError, StyleLoadError } from './src/main/ets/map/MapError';
export { MaplibreMap } from './src/main/ets/map/MaplibreMap';

// Camera
export type { CameraIdleEvent } from './src/main/ets/camera/CameraIdleEvent';
export type { CameraPosition, CameraUpdate } from './src/main/ets/camera/CameraPosition';
export { CameraTransitionMode } from './src/main/ets/camera/CameraTransitionOptions';
export type { CameraTransitionOptions, FitCameraOptions } from './src/main/ets/camera/CameraTransitionOptions';
export type { Viewport } from './src/main/ets/camera/Viewport';

// Gestures
export { WheelAction } from './src/main/ets/interaction/InteractionOptions';
export type { InteractionOptions, MovementOptions, RotationOptions } from './src/main/ets/interaction/InteractionOptions';

// Controls
export { AttributionButton } from './src/main/ets/overlay/AttributionButton';
export { AttributionText } from './src/main/ets/overlay/AttributionText';
export { CompassButton, DisappearingCompassButton } from './src/main/ets/overlay/CompassButton';
export { AttributionControls, DefaultControls, FullControls } from './src/main/ets/overlay/DefaultControls';
export { MaplibreLogo } from './src/main/ets/overlay/MaplibreLogo';
export { Marker } from './src/main/ets/overlay/Marker';
export { OffscreenMarker } from './src/main/ets/overlay/OffscreenMarker';
export type { OffscreenMarkerAngleEvent } from './src/main/ets/overlay/OffscreenMarker';
export { PointerPinButton } from './src/main/ets/overlay/PointerPinButton';
export { DisappearingScaleBar, ScaleBar, ScaleBarUnits } from './src/main/ets/overlay/ScaleBar';
export { ZoomButtons } from './src/main/ets/overlay/ZoomButtons';

// Map content
export type { MapContent } from './src/main/ets/content/MapContent';
export type { StyleImage } from './src/main/ets/content/StyleImage';
export type {
  FeatureClickEvent,
  FeatureClickHandler,
  LayerPredicate,
  LayerSummary,
  StyleLayer,
} from './src/main/ets/content/StyleLayer';
export type { StyleSource } from './src/main/ets/content/StyleSource';

// Style API
export type { LayerHandle } from './src/main/ets/style/LayerHandle';
export type { MapStyle, StyleTransitionOptions } from './src/main/ets/style/MapStyle';
export type { GeoJsonSourceHandle, ImageSourceHandle, SourceHandle } from './src/main/ets/style/SourceHandle';

// User location
export { FollowBearing } from './src/main/ets/location/FollowUserLocationOptions';
export type { FollowUserLocationOptions } from './src/main/ets/location/FollowUserLocationOptions';
export type { UserLocationIndicatorOptions } from './src/main/ets/location/UserLocationIndicatorOptions';

// Snapshots
export { renderSnapshot } from './src/main/ets/snapshot/Snapshot';
export type { MapSnapshot, MapSnapshotOptions } from './src/main/ets/snapshot/Snapshot';

// Runtime
export { ConnectivityMode } from './src/main/ets/runtime/ConnectivityMode';
export { MapLogLevel } from './src/main/ets/runtime/Logs';
export type { MapLogHandler, MapLogRecord } from './src/main/ets/runtime/Logs';
export { MapRuntime } from './src/main/ets/runtime/MapRuntime';
export type { MapRuntimeOptions } from './src/main/ets/runtime/MapRuntime';
export type { OfflineRegion, OfflineRegionDefinition, OfflineRegionStatus } from './src/main/ets/runtime/OfflineRegion';
export { MapResourceError, MapResourceErrorReason } from './src/main/ets/runtime/Requests';
export type {
  MapResourceLoadRequest,
  MapResourceProvider,
  MapResourceRange,
  MapResourceRequest,
  MapResourceResponse,
} from './src/main/ets/runtime/Requests';

// Expressions
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
} from './src/main/ets/expression/Expressions';
export type {
  Condition,
  ExpressionInput,
  FormatSection,
  JsonObject,
  JsonValue,
  MatchCase,
  MatchLabel,
  Stop,
} from './src/main/ets/expression/Expressions';

// Geometry
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
} from './src/main/ets/geometry/GeoJson';
export type { LatLng, LatLngBounds, ScreenPoint } from './src/main/ets/geometry/Geometry';
