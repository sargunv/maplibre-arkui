// Finds the page in MapLibre Native FFI's TypeScript reference of each FFI
// symbol that the library re-exports:
//
//   node ffi-reference.mjs <Index.d.ts> <out dir>
//
// It writes <out dir>/ffi-reference.json, which maps each FFI name to its page
// for TypeDoc's `externalSymbolLinkMappings` and the site's <Api> links, and
// <out dir>/reference.md, the reference's front page, which lists the
// re-exports. FFI's reference documents its main branch, so a name that it
// doesn't list, such as one that FFI renamed since the pinned commit, links to
// its module page with a warning.
import fs from "node:fs";
import path from "node:path";

const FFI_REFERENCE =
  "https://maplibre.org/maplibre-native-ffi/reference/typescript/";
const MODULE = `${FFI_REFERENCE}modules/index.html`;

const [index, out] = process.argv.slice(2);
if (out === undefined) {
  console.error("usage: ffi-reference.mjs <Index.d.ts> <out dir>");
  process.exit(2);
}

// `export { A, B as C } from '@maplibre/native-ffi';`, possibly `export type`.
const source = fs.readFileSync(index, "utf8");
const reexports = [];
for (const match of source.matchAll(
  /export\s+(?:type\s+)?\{([^}]*)\}\s+from\s+'@maplibre\/native-ffi'/g,
)) {
  for (const item of match[1].split(",")) {
    const [name, alias] = item.trim().split(/\s+as\s+/);
    if (name) {
      reexports.push({ name, alias: alias ?? name });
    }
  }
}
if (reexports.length === 0) {
  throw new Error(`${index} re-exports nothing from @maplibre/native-ffi`);
}

const response = await fetch(MODULE);
if (!response.ok) {
  throw new Error(`${MODULE}: ${response.status} ${response.statusText}`);
}
const pages = new Map();
for (const match of (await response.text()).matchAll(
  /href="\.\.\/(\w+)\/index\.(\w+)\.html"/g,
)) {
  pages.set(match[2], {
    kind: match[1],
    url: `${FFI_REFERENCE}${match[1]}/index.${match[2]}.html`,
  });
}

const links = {};
const kinds = new Map();
for (const { name, alias } of reexports) {
  const page = pages.get(name);
  if (page === undefined) {
    console.warn(`warning: FFI's reference has no page for ${name}`);
  }
  links[name] = page?.url ?? MODULE;
  const kind = page?.kind ?? "other";
  kinds.set(kind, [...(kinds.get(kind) ?? []), { name, alias }]);
}

const headings = {
  classes: "Classes",
  enums: "Enumerations",
  functions: "Functions",
  interfaces: "Interfaces",
  types: "Type aliases",
  variables: "Variables",
  other: "Newer than FFI's published reference",
};
const sections = [...kinds.entries()]
  .sort(
    ([a], [b]) =>
      Object.keys(headings).indexOf(a) - Object.keys(headings).indexOf(b),
  )
  .map(([kind, items]) => {
    const list = items
      .sort((a, b) => a.alias.localeCompare(b.alias))
      .map(
        ({ name, alias }) =>
          `- [${alias}](${links[name]})${alias === name ? "" : ` (FFI's \`${name}\`)`}`,
      )
      .join("\n");
    return `### ${headings[kind] ?? kind}\n\n${list}`;
  });

fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(
  path.join(out, "ffi-reference.json"),
  `${JSON.stringify({ reexports, links }, null, 2)}\n`,
);
fs.writeFileSync(
  path.join(out, "reference.md"),
  `The API reference of \`@maplibre/arkui\`, generated from the library's doc
comments. Struct components and classes show their ArkUI decorators as badges,
such as \`@Param\` for a component's params.

## Re-exported from MapLibre Native FFI

The package also re-exports the [MapLibre Native FFI](${MODULE}) types and
functions that its API takes and returns, and the FFI API for styles, queries,
requests, offline regions, and logs. FFI's reference documents them, and the
links here and in the signatures go to it. FFI publishes its reference with
each release, so the names that FFI added since link to its module page.

${sections.join("\n\n")}
`,
);
console.log(`Linked ${reexports.length} FFI re-exports to FFI's reference.`);
