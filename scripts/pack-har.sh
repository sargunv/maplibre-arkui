#!/usr/bin/env bash
# Packs the library into an OHPM source HAR:
#
#   pack-har.sh <library dir> <out dir>
#
# A source HAR carries its ArkTS sources, which the app's build compiles. The
# HAR is <out dir>/maplibre-arkui.har. Its module manifest gains the API floor
# that oh-package.json5 declares, as the one hvigor generates does. The test
# suite in src/ohosTest stays out.
set -euo pipefail

usage="usage: pack-har.sh <library dir> <out dir>"
library="$(cd "${1:?$usage}" && pwd)"
out=${2:?$usage}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
package="$work/package"
mkdir -p "$package/src/main"
cp "$library/oh-package.json5" "$library/Index.ets" "$library/README.md" "$package/"
cp -R "$library/src/main/ets" "$package/src/main/ets"
api=$(jq -er .compatibleSdkVersion "$library/oh-package.json5")
jq --argjson api "$api" \
  '.app = {minAPIVersion: $api, targetAPIVersion: $api, apiReleaseType: "Release"}' \
  "$library/src/main/module.json" >"$package/src/main/module.json"

mkdir -p "$out"
tar -czf "$out/maplibre-arkui.har" -C "$work" package
echo "Packed $out/maplibre-arkui.har."
