#!/usr/bin/env bash
# Downloads the OHPM packages that MapLibre Native FFI's CI packed at a commit:
#
#   ffi-download.sh <commit> <out dir>
#
# FFI's CI uploads them as the `ohpm-packages-*` artifact of its CI run for
# each commit on main that changes them, and keeps the artifact for 30 days. The
# out dir gets native-ffi.har, the backend-free facade, and
# native-ffi-opengl.har, whose libraries cover every ABI. It needs `gh` signed
# in, or GH_TOKEN.
set -euo pipefail

usage="usage: ffi-download.sh <commit> <out dir>"
commit=${1:?$usage}
out=${2:?$usage}
repo=maplibre/maplibre-native-ffi

artifact=
for run in $(gh api "repos/$repo/actions/runs?head_sha=$commit&per_page=100" \
  --jq '.workflow_runs[] | select(.path == ".github/workflows/ci-coverage.yml") | .id'); do
  artifact=$(gh api "repos/$repo/actions/runs/$run/artifacts?per_page=100" \
    --jq '[.artifacts[] | select((.name | startswith("ohpm-packages-")) and (.expired | not))][0].id // empty')
  [[ -n $artifact ]] && break
done
if [[ -z $artifact ]]; then
  echo "error: FFI's CI has no unexpired ohpm-packages artifact for $commit." >&2
  echo "Pin a newer FFI commit whose CI packed them, or run ffi:pack with an FFI checkout." >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
gh api "repos/$repo/actions/artifacts/$artifact/zip" >"$work/packages.zip"
unzip -q "$work/packages.zip" -d "$work/packages"
rm -rf "$out"
mkdir -p "$out"
# The HARs carry FFI's version in their names, which this repository ignores.
cp "$work"/packages/native-ffi-[0-9]*.har "$out/native-ffi.har"
cp "$work"/packages/native-ffi-opengl-*.har "$out/native-ffi-opengl.har"
echo "$commit" >"$out/COMMIT"
echo "Downloaded the FFI packages from $commit into $out."
