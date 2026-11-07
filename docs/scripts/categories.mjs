// The API reference's categories: one for each feature directory of
// library/src/main/ets, in the order of the guides, titled with the guide's
// sidebar label. scripts/emit-declarations.mjs puts each declaration in the
// category of its directory, and scripts/check-api-layout.sh fails for a
// feature directory that isn't listed here.

/** @type {{ directory: string, title: string }[]} */
export const categories = [
  { directory: "map", title: "The map" },
  { directory: "camera", title: "The camera" },
  { directory: "interaction", title: "Gestures" },
  { directory: "overlay", title: "Controls and ArkUI content" },
  { directory: "content", title: "Map content" },
  { directory: "style", title: "The style API" },
  { directory: "location", title: "The user's location" },
  { directory: "snapshot", title: "Snapshots" },
  { directory: "runtime", title: "Requests, offline regions, and logs" },
  { directory: "expression", title: "Expressions" },
  // No guide covers the value types on their own.
  { directory: "geometry", title: "Geometry" },
];
