#!/usr/bin/env bash
# Packs the library into an OHPM source HAR:
#
#   pack-har.sh <library dir> <out dir>
#
# A source HAR carries its ArkTS sources, which the app's build compiles. The
# HAR is <out dir>/maplibre-arkui.har. Its module manifest gains the API floor
# that oh-package.json5 declares, as the one hvigor generates does. The test
# suite in src/ohosTest stays out. OHPM's review needs a README, a CHANGELOG
# that names the version, and a LICENSE, which comes from the repository's
# root.
set -euo pipefail

usage="usage: pack-har.sh <library dir> <out dir>"
library="$(cd "${1:?$usage}" && pwd)"
out=${2:?$usage}
manifest="$library/oh-package.json5"
version=$(jq -er .version "$manifest")
if ! grep -qxF "## $version" "$library/CHANGELOG.md"; then
  echo "error: $library/CHANGELOG.md has no '## $version' section" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
package="$work/package"
mkdir -p "$package/src/main"
cp "$manifest" "$library/Index.ets" "$library/README.md" "$library/CHANGELOG.md" "$package/"
cp -R "$library/src/main/ets" "$package/src/main/ets"
api=$(jq -er .compatibleSdkVersion "$manifest")
jq --argjson api "$api" \
  '.app = {minAPIVersion: $api, targetAPIVersion: $api, apiReleaseType: "Release"}' \
  "$library/src/main/module.json" >"$package/src/main/module.json"

# The HAR builds apps either way; these only keep it off ohpm.
if [[ -f "$library/../LICENSE" ]]; then
  cp "$library/../LICENSE" "$package/"
else
  echo "warning: the repository has no LICENSE, which ohpm requires" >&2
fi
if ! jq -e '.license' "$manifest" >/dev/null; then
  echo "warning: $manifest has no license, which ohpm requires" >&2
fi
local_dependencies=$(jq -r '.dependencies // {} | to_entries[] | select(.value | startswith("file:")) | .key' "$manifest")
if [[ -n $local_dependencies ]]; then
  echo "warning: ohpm rejects the local dependencies on $(paste -sd, <<<"$local_dependencies"); see AGENTS.md, Releasing" >&2
fi

mkdir -p "$out"
tar -czf "$out/maplibre-arkui.har" -C "$work" package
echo "Packed $out/maplibre-arkui.har, version $version."
