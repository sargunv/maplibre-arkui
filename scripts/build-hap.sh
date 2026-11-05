#!/usr/bin/env bash
# Builds and signs a HAP from a module and the OHPM packages it uses:
#
#   build-hap.sh <module dir> <work dir> <abi> <package>...
#
# <module dir> holds module.json, which also carries the app's fields, ets/,
# and resources/. Each <package> is a HAR or an unpacked package directory.
# The HAP is <work dir>/<module>.hap, for the native libraries of <abi>.
#
# DevEco Studio builds apps with hvigor, whose packages have no clear license,
# so this script calls the OpenHarmony SDK's tools instead, as MapLibre Native
# FFI's examples/arkui/scripts/build-hap.sh does: ets-loader compiles ArkTS with
# the SDK's webpack configuration, es2abc merges every record into
# modules.abc, and pack-hap.sh packs and signs the HAP. ets-loader's webpack
# build doesn't rewrite `@kit.*` imports, so sources import `@ohos.*` modules.
#
# It installs each package as ohpm would, in the module's oh_modules, and then
# by its kind:
#
# - A source HAR, whose main is an .ets file, is compiled with the module. The
#   webpack build compiles a package in oh_modules as a CommonJS module, which
#   breaks ArkTS, so the HAR's sources join the module's own under
#   ets/<package name>, and the module's imports of the package name become
#   relative imports of them.
# - A JavaScript package, whose main is a .js file, such as FFI's facade or
#   hypium, stays external to the webpack build, which imports it by its record
#   name. es2abc compiles its files into records beside the module's.
# - A package with libs/<abi> supplies native libraries, such as FFI's backend.
set -euo pipefail

usage="usage: build-hap.sh <module dir> <work dir> <abi> <package>..."
source_dir="$(cd "${1:?$usage}" && pwd)"
work=${2:?$usage}
abi=${3:?$usage}
shift 3
scripts="$(cd "$(dirname "$0")" && pwd)"
sdk="$(dirname "${OHOS_SDK_NATIVE:?OHOS_SDK_NATIVE must name the OpenHarmony native SDK; run mise install}")"
loader="$sdk/ets/build-tools/ets-loader"
case "$(uname -s)" in
  Darwin) es2abc="$loader/bin/ark/build-mac/bin/es2abc" ;;
  *) es2abc="$loader/bin/ark/build/bin/es2abc" ;;
esac
for tool in "$loader/webpack.config.js" "$es2abc"; do
  if [[ ! -e "$tool" ]]; then
    echo "error: the OpenHarmony SDK has no $tool; reinstall it with mise install --force ohos-sdk" >&2
    exit 1
  fi
done

rm -rf "$work"
mkdir -p "$work"
work="$(cd "$work" && pwd)"
module=$(jq -er .module.name "$source_dir/module.json")
bundle=$(jq -er .app.bundleName "$source_dir/module.json")
root="$work/project"
src="$root/$module/src/main"
modules="$root/$module/oh_modules"
mkdir -p "$src" "$modules" "$work/libs/$abi" "$work/cache" "$work/records"
cp -R "$source_dir/." "$src/"

# A record names a system module @ohos:x and a packed library
# @app:<bundle>/<module>/<name>, and a relative import names its record without
# an extension.
records="$work/records.txt"
: >"$records"
add_js_records() {
  local package=$1 name=$2 file relative
  while IFS= read -r -d '' file; do
    relative=${file#"$package"/}
    mkdir -p "$(dirname "$work/records/$name/$relative")"
    BUNDLE="$bundle/$module" perl -pe '
      s#(["\x27])\@ohos\.#$1\@ohos:#g;
      s#(["\x27])lib(\w+)\.so(["\x27])#$1\@app:$ENV{BUNDLE}/$2$3#g;
      s#(["\x27])(\.\.?/[^"\x27]*)\.(?:js|mjs)(["\x27])#$1$2$3#g;
    ' "$file" >"$work/records/$name/$relative"
    printf '%s;%s;esm;%s;%s\n' "$work/records/$name/$relative" \
      "$bundle/$module/oh_modules/$name/${relative%.*}" \
      "$module/oh_modules/$name/$relative" "$module" >>"$records"
  done < <(find "$package" -name '*.js' -type f -print0)
}

ohm_map='{}'
source_hars=()
api=0
for package in "$@"; do
  if [[ ! -e $package ]]; then
    echo "error: no package at $package. For FFI's, run mise run ffi:download or ffi:pack." >&2
    exit 1
  elif [[ -f $package ]]; then
    unpacked=$(mktemp -d "$work/package.XXXXXX")
    tar -xzf "$package" -C "$unpacked" --strip-components 1
    package=$unpacked
  fi
  name=$(jq -er .name "$package/oh-package.json5")
  main=$(jq -r '.main // ""' "$package/oh-package.json5")
  api=$(jq --argjson api "$api" '[$api, .compatibleSdkVersion // 0] | max' "$package/oh-package.json5")
  mkdir -p "$modules/$name"
  cp -R "$package/." "$modules/$name/"
  if [[ -d "$package/libs/$abi" ]]; then
    cp "$package/libs/$abi/"*.so "$work/libs/$abi/"
  fi
  case "$main" in
    *.ets)
      mkdir -p "$src/ets/$name/src/main"
      cp "$package/$main" "$src/ets/$name/"
      cp -R "$package/src/main/ets" "$src/ets/$name/src/main/"
      source_hars+=("$name/${main%.ets}")
      ;;
    *.js)
      ohm_map=$(jq --arg name "$name" --arg record "@bundle:$bundle/$module/oh_modules/$name/${main%.js}" \
        '.[$name] = $record' <<<"$ohm_map")
      add_js_records "$package" "$name"
      ;;
  esac
done

# Rewrite the module's imports of each source HAR to relative imports of its
# copy under ets/.
while IFS= read -r -d '' file; do
  directory=$(dirname "${file#"$src/ets/"}")
  up=$(sed -E 's#[^/]+#..#g' <<<"$directory")
  [[ $directory == . ]] && up=.
  for entry in ${source_hars[@]+"${source_hars[@]}"}; do
    name=${entry%/*}
    NAME="$name" TARGET="$up/$entry" perl -pi -e \
      's#(from\s+["\x27])\Q$ENV{NAME}\E(["\x27])#$1$ENV{TARGET}$2#g' "$file"
  done
done < <(find "$src/ets" \( -name '*.ets' -o -name '*.ts' \) -type f -print0)

# The app requires and targets the highest API floor of its packages.
if ((api == 0)); then
  echo "error: no package declares compatibleSdkVersion" >&2
  exit 1
fi
jq --argjson api "$api" '.app.minAPIVersion = $api | .app.targetAPIVersion = $api' \
  "$source_dir/module.json" >"$src/module.json"

# ets-loader reads the project from the environment and a build file, and
# compiles the pages, the abilities, and any test runner into records named
# <bundle>/<module>/ets/<path>. It deletes nodeModulesPath, which is its own
# output.
runners='[]'
if [[ -d "$src/ets/testrunner" ]]; then
  runners=$(find "$src/ets/testrunner" -name '*.ets' | jq -R . | jq -s .)
fi
jq -n --arg root "$root" --arg module "$module" --arg work "$work" \
  --argjson ohm "$ohm_map" --argjson runners "$runners" '{
  compileMode: "esmodule",
  packageManagerType: "ohpm",
  projectRootPath: $root,
  modulePathMap: { ($module): ($root + "/" + $module) },
  nodeModulesPath: ($work + "/cache/oh_modules"),
  harNameOhmMap: $ohm,
  otherCompileFiles: $runners,
  moduleName: $module
}' >"$work/build.json"
(
  # The configuration resolves its loaders from its own directory.
  cd "$loader"
  aceModuleRoot="$src/ets" aceModuleBuild="$work/ets" \
    aceModuleJsonPath="$src/module.json" \
    aceProfilePath="$src/resources/base/profile" \
    aceBuildJson="$work/build.json" cachePath="$work/cache" \
    node --require "$scripts/ets-loader-patches.cjs" \
    "$loader/node_modules/webpack/bin/webpack.js" \
    --config "$loader/webpack.config.js" \
    --env buildMode=debug --env compilerType=ark --env sourceMap=none
)
if [[ ! -s "$work/cache/filesInfo.txt" ]]; then
  echo "error: ets-loader didn't compile the module" >&2
  exit 1
fi
# ets-loader reports breaks of the ArkTS rules as warnings and builds anyway.
linter="$work/cache/ArkTS/ArkTSLinter_output.json"
if [[ -s $linter ]] && jq -e 'any(.[]; .categoryInfo == "Error")' "$linter" >/dev/null; then
  jq -r '.[] | select(.categoryInfo == "Error") | "\(.fileName):\(.line):\(.character): \(.messageText)"' \
    "$linter" | sed "s#$src/##" >&2
  echo "error: the module breaks the ArkTS rules" >&2
  exit 1
fi

cat "$work/cache/filesInfo.txt" "$records" >"$work/all-records.txt"
"$es2abc" --merge-abc --module --output "$work/modules.abc" "@$work/all-records.txt"
"$scripts/pack-hap.sh" "$src" "$work/modules.abc" "$work/libs" "$work/$module.hap"
echo "Signed $work/$module.hap for $abi."
