#!/usr/bin/env bash
# Packs MapLibre Native FFI's OHPM packages from a checkout of FFI:
#
#   ffi-pack.sh <FFI checkout> <preset> <out dir>
#
# FFI builds the C library and its Node-API addon for the preset, which takes
# a while the first time, and packs the facade and the backend whose libraries
# the preset names. The x64 emulator needs ohos-x64-egl. The out dir gets
# native-ffi.har and native-ffi-opengl.har, and COMMIT names the checkout's
# commit.
set -euo pipefail

usage="usage: ffi-pack.sh <FFI checkout> <preset> <out dir>"
ffi="$(cd "${1:?$usage}" && pwd)"
preset=${2:?$usage}
out=${3:?$usage}
case "$preset" in
  *-egl) backend=opengl ;;
  *) echo "error: only the OpenGL backend is supported, not $preset" >&2; exit 2 ;;
esac

(cd "$ffi" && mise -E ohos run //bindings/typescript:pack-ohpm "$preset")
rm -rf "$out"
mkdir -p "$out"
cp "$ffi/bindings/typescript/build/ohpm/native-ffi-0.0.0.har" "$out/native-ffi.har"
cp "$ffi/bindings/typescript/build/ohpm/native-ffi-$backend-0.0.0.har" "$out/native-ffi-$backend.har"
commit=$(git -C "$ffi" rev-parse HEAD)
echo "$commit" >"$out/COMMIT"
if ! git -C "$ffi" diff --quiet HEAD; then
  echo "warning: $ffi has uncommitted changes on top of $commit" >&2
fi
echo "Packed the FFI packages from $commit into $out."
