#!/usr/bin/env bash
# Checks the rules of the API guidelines' Organization section that a script
# can check:
#
# - Index.ets lists the public API itself: no `export *`, and no export from
#   MapLibre Native FFI or from an `internal/` directory.
# - Each top-level file of a feature directory exports only names that
#   Index.ets exports, since every export of such a file is public.
# - Each source file is in a feature directory, and the API reference has a
#   category for each feature directory, in docs/scripts/categories.mjs.
set -euo pipefail

node --input-type=module - library/Index.ets library/src/main/ets docs/scripts/categories.mjs <<'EOF'
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [index, sources, categoriesFile] = process.argv.slice(2);
const { categories } = await import(pathToFileURL(path.resolve(categoriesFile)));
const errors = [];

// The names of an `export { … }` or `export type { … }` list, without their
// `as` part.
function listed(list) {
  return list
    .split(",")
    .map((item) => item.trim().split(/\s+as\s+/).pop())
    .filter((name) => name !== "");
}

const indexText = fs.readFileSync(index, "utf8");
if (/^\s*export\s+(type\s+)?\*/m.test(indexText)) {
  errors.push(`${index}: export * hides what the API is; list each name`);
}
const exported = new Set();
for (const match of indexText.matchAll(
  /^export\s+(?:type\s+)?\{([^}]*)\}\s*from\s*'([^']+)'/gm,
)) {
  const from = match[2];
  if (from === "@maplibre/native-ffi" || from.startsWith("@maplibre/native-ffi/")) {
    errors.push(`${index}: exports from ${from}; declare the library's own types`);
  }
  if (from.split("/").includes("internal")) {
    errors.push(`${index}: exports from ${from}, which is library-only`);
  }
  for (const name of listed(match[1])) {
    exported.add(name);
  }
}

const directories = new Set(categories.map((category) => category.directory));
for (const entry of fs.readdirSync(sources, { withFileTypes: true })) {
  const where = path.join(sources, entry.name);
  if (!entry.isDirectory()) {
    errors.push(`${where}: put it in a feature directory`);
    continue;
  }
  if (!directories.has(entry.name)) {
    errors.push(`${where}: ${categoriesFile} has no category for this feature directory`);
  }
  for (const file of fs.readdirSync(where)) {
    if (!file.endsWith(".ets")) {
      continue;
    }
    const text = fs.readFileSync(path.join(where, file), "utf8");
    const names = [
      ...text.matchAll(
        /^export\s+(?:declare\s+)?(?:abstract\s+)?(?:async\s+)?(?:function|const|let|var|class|interface|type|enum|struct)\s+(\w+)/gm,
      ),
    ].map((match) => match[1]);
    for (const match of text.matchAll(/^export\s+(?:type\s+)?\{([^}]*)\}/gm)) {
      names.push(...listed(match[1]));
    }
    for (const name of names) {
      if (!exported.has(name)) {
        errors.push(
          `${path.join(where, file)}: exports ${name}, which ${index} doesn't; ` +
            "list it there, or move it to internal/",
        );
      }
    }
  }
}

for (const error of errors) {
  console.error(error);
}
process.exit(errors.length > 0 ? 1 : 0);
EOF
