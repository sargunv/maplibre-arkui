// Emits TypeScript declarations of the library's public API for TypeDoc:
//
//   node emit-declarations.mjs <SDK ets dir> <Index.ets> <FFI index.d.ts> <out dir>
//
// The SDK's TypeScript fork, which ets-loader compiles ArkTS with, emits
// `.d.ets` files that keep the doc comments, the structs, and the decorators.
// Standard TypeScript reads none of the three ArkTS forms, so this script
// rewrites each file into a `.d.ts`:
//
// - A struct becomes a class without a constructor. Its members that aren't
//   params, such as `build()` and the `@Monitor` methods, become `@internal`.
// - A decorator becomes a modifier tag in its declaration's doc comment, which
//   TypeDoc shows as a badge: `@Param` becomes `@arkuiParam`.
// - Each top-level declaration gets the `@category` of its feature directory,
//   from categories.mjs.
// - An `ets` code block in a doc comment becomes a `ts` block, for TypeDoc.
//
// It fails when a file that the reference documents imports from MapLibre
// Native FFI, except for the escape hatch's MapHandle and RenderSessionHandle
// in map/MapController.d.ts.
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";

import { categories } from "./categories.mjs";

const usage =
  "usage: emit-declarations.mjs <SDK ets dir> <Index.ets> <FFI index.d.ts> <out dir>";
const [sdkEts, entry, ffiTypes, out] = process.argv.slice(2);
if (out === undefined) {
  console.error(usage);
  process.exit(2);
}

const loader = path.join(sdkEts, "build-tools/ets-loader");
const ts = createRequire(import.meta.url)(
  path.join(loader, "node_modules/typescript"),
);

// ets-loader's own options, which declare the ArkTS syntax and decorators.
const config = ts.readConfigFile(
  path.join(loader, "tsconfig.esm.json"),
  ts.sys.readFile,
);
const { options } = ts.parseJsonConfigFileContent(
  config.config,
  ts.sys,
  loader,
);
const root = path.dirname(path.resolve(entry));
// The built-in components and their attribute types, such as `Padding`.
const components = fs
  .readdirSync(path.join(sdkEts, "component"))
  .filter((file) => file.endsWith(".d.ts"))
  .map((file) => path.join(sdkEts, "component", file));
const program = ts.createProgram([path.resolve(entry), ...components], {
  ...options,
  declaration: true,
  emitDeclarationOnly: true,
  noEmit: false,
  noEmitOnError: false,
  rootDir: root,
  outDir: out,
  baseUrl: root,
  paths: {
    "@maplibre/native-ffi": [path.resolve(ffiTypes)],
    "@ohos.*": [path.join(sdkEts, "api/@ohos.*")],
  },
});

// The category title of each feature directory under src/main/ets.
const titles = new Map(
  categories.map(({ directory, title }) => [directory, title]),
);
// The FFI types that the escape hatch lends, in the one file that may name
// them.
const ESCAPE_HATCH = "src/main/ets/map/MapController.d.ts";
const ESCAPE_HATCH_TYPES = ["MapHandle", "RenderSessionHandle"];

fs.rmSync(out, { recursive: true, force: true });
let count = 0;
const leaks = [];
const result = program.emit(undefined, (fileName, text) => {
  if (!fileName.endsWith(".d.ets")) {
    return;
  }
  const target = fileName.replace(/\.d\.ets$/, ".d.ts");
  const file = path.relative(out, target).split(path.sep).join("/");
  leaks.push(...ffiImports(file, text));
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, rewrite(text, fileName, categoryOf(file)));
  count++;
});
if (leaks.length > 0) {
  for (const leak of leaks) {
    console.error(`error: ${leak}`);
  }
  console.error(
    "error: the API declares its own types, and lends FFI's only through MapController.withFfiMap()",
  );
  process.exit(1);
}
// A syntax error emits a broken file, so it stops the build. Type errors,
// such as a global that the SDK declares elsewhere, don't change what the
// declarations say.
const syntax = program
  .getSourceFiles()
  .filter((file) => file.fileName.startsWith(root + path.sep))
  .flatMap((file) => program.getSyntacticDiagnostics(file))
  .concat(result.diagnostics);
if (syntax.length > 0 || result.emitSkipped || count === 0) {
  for (const diagnostic of syntax) {
    console.error(
      ts.formatDiagnostic(diagnostic, {
        getCanonicalFileName: (name) => name,
        getCurrentDirectory: () => process.cwd(),
        getNewLine: () => "\n",
      }),
    );
  }
  console.error("error: the SDK's TypeScript didn't emit the declarations");
  process.exit(1);
}
console.log(`Wrote ${count} declaration files into ${out}.`);

/** The decorators that make a struct member part of its API. */
function isParamDecorator(name) {
  return [
    "Param",
    "Once",
    "Require",
    "Event",
    "BuilderParam",
    "Provider",
    "Consumer",
  ].includes(name);
}

// The category of the declarations in `file`, a path in the output directory,
// or undefined for Index.d.ts, which only re-exports.
function categoryOf(file) {
  const parts = file.split("/");
  if (parts.length === 1) {
    return undefined;
  }
  const title =
    parts.slice(0, 3).join("/") === "src/main/ets"
      ? titles.get(parts[3])
      : undefined;
  if (title === undefined) {
    throw new Error(
      `${file}: docs/scripts/categories.mjs has no category for its directory`,
    );
  }
  return title;
}

// What a file that the reference documents imports from FFI, besides what the
// escape hatch may: the files outside internal/, whose declarations are
// public. The library-only files under internal/ may use FFI's types.
function ffiImports(file, text) {
  if (file.split("/").includes("internal")) {
    return [];
  }
  const found = [];
  for (const match of text.matchAll(
    /^(?:import|export)\s+(?:type\s+)?(\{[^}]*\}|\*(?:\s+as\s+\w+)?|\w+)\s*from\s*['"]@maplibre\/native-ffi['"]/gm,
  )) {
    const names = match[1].startsWith("{")
      ? match[1]
          .slice(1, -1)
          .split(",")
          .map((item) => item.trim().split(/\s+as\s+/)[0])
          .filter((name) => name !== "")
      : [match[1]];
    for (const name of names) {
      if (file !== ESCAPE_HATCH || !ESCAPE_HATCH_TYPES.includes(name)) {
        found.push(`${file} imports ${name} from @maplibre/native-ffi`);
      }
    }
  }
  return found;
}

// Rewrites one file. `category` is that of its top-level declarations.
function rewrite(text, fileName, category) {
  const lines = text.split("\n");
  const output = [];
  // The comment that ends right above the next declaration, as indices into
  // `output`, and the decorators since then.
  let comment;
  let decorators = [];
  // The indentation of each struct's members, while in one.
  let structIndent;

  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    const trimmed = line.trim();

    if (trimmed.startsWith("/**")) {
      const start = output.length;
      output.push(line);
      while (!lines[index].includes("*/")) {
        // TypeDoc highlights no ArkTS, so its examples show as TypeScript.
        output.push(lines[++index].replace(/^(\s*\*\s*)```ets$/, "$1```ts"));
      }
      comment = { start, end: output.length - 1 };
      continue;
    }
    const decorator = /^@(\w+)(\(.*\))?$/.exec(trimmed);
    if (decorator !== null) {
      decorators.push(decorator[1]);
      continue;
    }
    if (trimmed === "" || trimmed.startsWith("//")) {
      output.push(line);
      continue;
    }

    const indent = line.length - line.trimStart().length;
    if (
      structIndent !== undefined &&
      trimmed === "}" &&
      indent < structIndent
    ) {
      structIndent = undefined;
    }
    const modifiers = decorators.map((name) => `@arkui${name}`);
    const blocks = [];
    const isStruct = /^export declare struct \w+/.test(trimmed);
    if (isStruct) {
      // A struct takes its params as an object literal, not with `new`.
      modifiers.push("@hideconstructor");
    }
    if (
      category !== undefined &&
      indent === 0 &&
      /^export\s+(declare\s+)?(abstract\s+)?(class|const|enum|function|interface|let|struct|type|var)\s/.test(
        trimmed,
      )
    ) {
      blocks.push(`@category ${category}`);
    }
    const inStruct =
      structIndent !== undefined &&
      indent === structIndent &&
      !/^[}\])]/.test(trimmed);
    const isPrivate = /^(private|protected) /.test(trimmed);
    if (inStruct && !isPrivate && !decorators.some(isParamDecorator)) {
      modifiers.push("@internal");
    }
    const tags = [...blocks];
    if (modifiers.length > 0) {
      tags.unshift(modifiers.join(" "));
    }
    if (tags.length > 0) {
      const pad = " ".repeat(indent);
      if (comment === undefined) {
        output.push(
          `${pad}/**`,
          ...tags.map((tag) => `${pad} * ${tag}`),
          `${pad} */`,
        );
      } else {
        addTags(output, comment, tags, pad);
      }
    }

    if (isStruct) {
      output.push(line.replace("declare struct", "declare class"));
      structIndent = indent + 4;
    } else if (/\bstruct\b/.test(trimmed) && indent === 0) {
      throw new Error(`${fileName}: unexpected struct: ${trimmed}`);
    } else {
      output.push(line);
    }
    comment = undefined;
    decorators = [];
  }
  return output.join("\n");
}

/** Adds lines of tags to the end of a doc comment in `output`. */
function addTags(output, comment, tags, pad) {
  const lines = tags.map((tag) => `${pad} * ${tag}`).join("\n");
  const last = output[comment.end];
  if (comment.start === comment.end) {
    // A one-line comment: `/** Text. */`.
    const body = last
      .trim()
      .replace(/^\/\*\*\s*/, "")
      .replace(/\s*\*\/$/, "");
    output[comment.end] =
      `${pad}/**\n${pad} * ${body}\n${pad} *\n${lines}\n${pad} */`;
  } else {
    output[comment.end] = `${pad} *\n${lines}\n${last}`;
  }
}
