#!/usr/bin/env bash
# Prints the hdc connect key of this worktree's OpenHarmony emulator. devices-cli
# boots it on demand from the Oniro image that mise installed, and keeps it
# running until `devices-cli release`. From MapLibre Native FFI's
# tools/devices/ohos-key, plus wake-device.sh, so the emulator is awake and
# unlocked for the app. Other devices, named with --device, are left as they are.
set -euo pipefail

if [[ -z "${OHOS_EMULATOR_IMAGES:-}" ]]; then
  oniro=$(mise where http:oniro-emulator)
  export OHOS_EMULATOR_IMAGES="$oniro/images"
fi
key=$(devices-cli get ohos)
"$(dirname "$0")/wake-device.sh" "$key"
echo "$key"
