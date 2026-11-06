#!/usr/bin/env bash
# Prints the ABI that build-hap.sh builds for a device, the first that the
# device lists:
#
#   device-abi.sh <hdc connect key>
set -euo pipefail

device=${1:?usage: device-abi.sh <hdc connect key>}
abis=$(hdc -t "$device" shell param get const.product.cpu.abilist | tr -d '\r[:space:]')
abi=${abis%%,*}
case "$abi" in
  arm64-v8a | x86_64) echo "$abi" ;;
  *)
    echo "error: device $device lists the ABIs '$abis', and the HAPs build for arm64-v8a and x86_64" >&2
    exit 1
    ;;
esac
