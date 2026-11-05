#!/usr/bin/env bash
# Prints the hdc connect key of this worktree's OpenHarmony emulator. devices-cli
# boots it on demand from the Oniro image that mise installed, and keeps it
# running until `devices-cli release`. From MapLibre Native FFI's
# tools/devices/ohos-key.
set -euo pipefail

if [[ -z "${OHOS_EMULATOR_IMAGES:-}" ]]; then
  oniro=$(mise where http:oniro-emulator)
  export OHOS_EMULATOR_IMAGES="$oniro/images"
fi
exec devices-cli get ohos
