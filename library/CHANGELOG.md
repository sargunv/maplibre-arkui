# Changelog

## 0.1.0-preview.1

The first preview. It builds against MapLibre Native FFI main, whose facade and
backend packages aren't on ohpm yet.

- `MapLibreMap`, a map that shows a style URL or document, resizes, and survives
  navigation, hidden pages, and the background.
- `MapController`: an observable camera, style state, and attribution;
  `updateCamera()` and `fitCameraToLatLngBounds()`, `fitCameraToLatLngs()`, and
  `fitCameraToGeometry()`, which resolve with how the move ended; the frame's
  camera and projection, for content that follows the map; and FFI's runtime,
  map, and render session.
- Gestures: pan, pinch, twist, two-finger pitch, double tap, double tap and
  drag, and two-finger tap, with momentum and snapping to north; the mouse
  wheel, touchpad pinch, and keys; per-gesture switches and cooperative mode for
  maps in scrolling parents; `onGestureStart` and `onGestureEnd`.
- Ornaments that follow dark mode: `MapCompass`, `MapScaleBar`,
  `MapAttribution`, and `MapZoomButtons`, on the map or placed by the app.
  `MapMarker` pins ArkUI content to a coordinate.
- The user's location from Location Kit, drawn with an accuracy circle and an
  arrow for the heading that the app reads from the compass, or for the course;
  and `followUserLocation()`, which can turn the map with either.
- `MapContent`: sources, layers, and images as data, which the map applies to
  each style it loads, changing only what differs.
- Style expressions as functions, GeoJSON types for ArkTS literals, and
  `readPixelMap()` for style images.
- `snapshot()`, a still image of a style, camera, and content.
- The default runtime's cache lasts between launches, and
  `addRuntimeEventListener()` reports offline download progress and the map
  events a listener asks for, which set the maps' event masks. FFI's style API,
  request handlers, offline regions, and logs are re-exported, with the enums
  and types that `MapHandle`'s methods take.
