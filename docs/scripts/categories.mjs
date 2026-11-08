// The API reference's categories: one for each feature directory of
// library/src/main/ets, roughly in the order of the guides. scripts/emit-declarations.mjs puts each declaration in the
// category of its directory, and scripts/check-api-layout.sh fails for a
// feature directory that isn't listed here.

/** @type {{ directory: string, title: string }[]} */
export const categories = [
  { directory: "map", title: "Map" },
  { directory: "camera", title: "Camera" },
  { directory: "interaction", title: "Gestures and clicks" },
  { directory: "overlay", title: "Controls and markers" },
  { directory: "content", title: "Map content" },
  { directory: "style", title: "Style API" },
  { directory: "location", title: "User location" },
  { directory: "snapshot", title: "Snapshots" },
  { directory: "runtime", title: "Runtime, requests, and offline regions" },
  { directory: "expression", title: "Expressions" },
  // No guide covers the value types on their own.
  { directory: "geometry", title: "Geometry" },
];
