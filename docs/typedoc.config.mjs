// TypeDoc renders the API reference into public/api from the declarations that
// scripts/emit-declarations.mjs writes into ../build/docs. `mise run docs:api`
// runs the whole pipeline.
import { OptionDefaults } from "typedoc";

import { categories } from "./scripts/categories.mjs";

const build = new URL("../build/docs/", import.meta.url).pathname;
const FFI_REFERENCE =
  "https://maplibre.org/maplibre-native-ffi/reference/typescript/";

// The ArkUI decorators that the declarations carry as modifier tags.
const decorators = [
  "Builder",
  "BuilderParam",
  "ComponentV2",
  "Event",
  "Local",
  "Monitor",
  "ObservedV2",
  "Once",
  "Param",
  "Require",
];

/** @type {Partial<import("typedoc").TypeDocOptions>} */
export default {
  name: "MapLibre ArkUI",
  entryPoints: [`${build}declarations/Index.d.ts`],
  tsconfig: "./tsconfig.api.json",
  out: "./public/api",
  readme: "./reference.md",
  // The declarations are generated, so they link to no source.
  disableSources: true,
  // One category for each feature, which emit-declarations.mjs gives each
  // declaration, in the order of the guides. The struct components come first
  // in each (scripts/structs-first.mjs).
  plugin: ["./scripts/structs-first.mjs"],
  categorizeByGroup: false,
  categoryOrder: [...categories.map((category) => category.title), "*"],
  navigation: { includeCategories: true, includeGroups: false },
  excludeInternal: true,
  excludePrivate: true,
  // FFI's types are FFI's to document. Only the escape hatch,
  // `MapController.withFfiMap()`, names any: link those to its reference.
  excludeExternals: true,
  externalPattern: [`${build}ffi/**`],
  externalSymbolLinkMappings: {
    "@maplibre/native-ffi": {
      MapHandle: `${FFI_REFERENCE}classes/index.MapHandle.html`,
      RenderSessionHandle: `${FFI_REFERENCE}classes/index.RenderSessionHandle.html`,
    },
  },
  // The SDK's ArkUI types, such as `Padding`, aren't in the program.
  skipErrorChecking: true,
  modifierTags: [
    ...OptionDefaults.modifierTags,
    ...decorators.map((name) => `@arkui${name}`),
  ],
  // Each badge shows its decorator as the source spells it.
  locales: {
    en: Object.fromEntries(
      decorators.map((name) => [`tag_arkui${name}`, `@${name}`]),
    ),
  },
  navigationLinks: {
    Guide: "../",
    GitHub: "https://github.com/sargunv/maplibre-arkui",
  },
  treatWarningsAsErrors: true,
};
