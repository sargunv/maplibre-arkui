// Fixes two bugs in ets-loader's webpack build while Node loads it:
//
//   node --require scripts/ets-loader-patches.cjs <ets-loader's webpack>
//
// build-hap.sh runs that build instead of hvigor, which drives ets-loader's
// rollup build. Neither bug is in the rollup build.
//
// The SDK version is pinned, so the text each patch replaces is too. If an SDK
// update changes it, the build stops here rather than miscompiling.

const Module = require("node:module");
const path = require("node:path");

const patches = [
  {
    // The webpack build finds the components that a file imports by reading
    // the files it imports, and counts only @Component structs there. A page
    // that builds an imported @ComponentV2 struct then fails with "does not
    // meet UI component syntax". This registers the struct the way the rollup
    // build does, with the two functions it calls. `n` maps the names that
    // the importing file uses, and `d` is the imported file.
    file: path.join("ets-loader", "lib", "process_import.js"),
    find: "_typescript.default.isStructDeclaration(e)&&_typescript.default.isIdentifier(e.name)&&isCustomComponent(e,m)&&(",
    insert:
      "_typescript.default.isStructDeclaration(e)&&_typescript.default.isIdentifier(e.name)&&isComponentV2(e)&&(function(k){" +
      "_validate_ui_syntax.componentCollection.customComponents.add(k);" +
      "parseComponentV2InImportNode(e,k,d,_process_struct_componentV.default.getOrCreateStructInfo(k))" +
      "})(n.get(e.name.getText())||e.name.getText()),",
  },
  {
    // The webpack build names an imported file's record after the last
    // src/main/ets in its path, but the record itself after the first. A
    // source HAR keeps its sources in src/main/ets, so its imports in the
    // module's ets/ named records that don't exist. This matches the first.
    file: path.join("ets-loader", "lib", "ark_utils.js"),
    find: String.raw`.match(/(\S+)(\/|\\)src(\/|\\)(?:main|ohosTest)(\/|\\)(ets|js)(\/|\\)(\S+)/))&&t.aceModuleJsonPath`,
    replace: String.raw`.match(/(\S+?)(\/|\\)src(\/|\\)(?:main|ohosTest)(\/|\\)(ets|js)(\/|\\)(\S+)/))&&t.aceModuleJsonPath`,
  },
];

const compile = Module.prototype._compile;
Module.prototype._compile = function (content, filename) {
  for (const patch of patches) {
    if (!filename.endsWith(patch.file)) {
      continue;
    }
    if (!content.includes(patch.find)) {
      throw new Error(
        `ets-loader-patches.cjs: ${filename} changed; update the patch`,
      );
    }
    content = content.replace(
      patch.find,
      patch.replace ?? patch.insert + patch.find,
    );
  }
  return compile.call(this, content, filename);
};
