#!/bin/sh
# Links this repo's copy of the ohos-sdk mise plugin, unless a working link
# exists. The copy matches MapLibre Native FFI's, whose checkouts link it too.
set -eu
plugins="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/plugins"
if [ ! -e "$plugins/ohos-sdk/metadata.lua" ]; then
  mise plugins link --force ohos-sdk .mise/plugins/ohos-sdk
fi
