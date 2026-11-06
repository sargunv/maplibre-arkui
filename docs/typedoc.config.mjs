// TypeDoc renders the API reference into public/api from the declarations that
// scripts/emit-declarations.mjs writes into ../build/docs. `mise run docs:api`
// runs the whole pipeline.
import fs from "node:fs";

import { OptionDefaults } from "typedoc";

const build = new URL("../build/docs/", import.meta.url).pathname;
const { links } = JSON.parse(
  fs.readFileSync(`${build}ffi-reference.json`, "utf8"),
);

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
  readme: `${build}reference.md`,
  // The declarations are generated, so they link to no source.
  disableSources: true,
  // The struct components, which the declarations put in this group, first.
  groupOrder: ["Components", "*"],
  excludeInternal: true,
  excludePrivate: true,
  // FFI's re-exports are FFI's to document: link them to its reference.
  excludeExternals: true,
  externalPattern: [`${build}ffi/**`],
  externalSymbolLinkMappings: { "@maplibre/native-ffi": links },
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
