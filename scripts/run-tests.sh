#!/usr/bin/env bash
# Installs a test HAP on a device, runs its hypium suite, and fails unless
# every case passed:
#
#   run-tests.sh <hdc connect key> <test HAP> [attempts]
#
# The HAP's module runs ets/testrunner/OpenHarmonyTestRunner, which starts the
# suite, and its module.json names the bundle and the module. `aa test` exits 0
# whatever the cases did, so hypium's tally decides.
#
# On the Oniro emulator, Mesa's llvmpipe sometimes crashes the app while maps
# render (see docs/ffi-feedback.md), and the suite ends without a tally. Only
# such a crashed run is tried again, up to [attempts] runs in all (default 3);
# a run with a failed case fails at once.
set -euo pipefail

usage="usage: run-tests.sh <hdc connect key> <test HAP> [attempts]"
device=${1:?$usage}
hap=${2:?$usage}
attempts=${3:-3}
scripts="$(cd "$(dirname "$0")" && pwd)"
hdc=(hdc -t "$device")
manifest=$(unzip -p "$hap" module.json)
bundle=$(jq -er .app.bundleName <<<"$manifest")
module=$(jq -er .module.name <<<"$manifest")
report=$(mktemp)
trap 'rm -f "$report"' EXIT

for ((attempt = 1; attempt <= attempts; attempt++)); do
  "$scripts/wake-device.sh" "$device"
  "${hdc[@]}" uninstall "$bundle" >/dev/null 2>&1 || true
  "${hdc[@]}" install -r "$hap"
  # hypium fails a case that doesn't settle within the per-case timeout.
  "${hdc[@]}" shell aa test -b "$bundle" -m "$module" \
    -s unittest /ets/testrunner/OpenHarmonyTestRunner -s timeout 60000 |
    tr -d '\r' | tee "$report"
  tally=$(grep -o 'Tests run: [0-9]*, Failure: [0-9]*, Error: [0-9]*, Pass: [0-9]*, Ignore: [0-9]*' "$report" | tail -1 || true)
  if [[ -n $tally ]]; then
    break
  fi
  echo "warning: run $attempt of $attempts ended without hypium's tally; the app crashed or hung" >&2
done
if [[ -z $tally ]]; then
  echo "error: hypium didn't report a tally in $attempts runs; the suite didn't finish" >&2
  exit 1
fi
read -r ran failed errored passed ignored < <(sed -E 's/[^0-9]+/ /g' <<<"$tally")
echo "hypium ran $ran cases in run $attempt of $attempts: $passed passed, $failed failed, $errored errors, $ignored ignored"
if ((ran == 0 || passed != ran)); then
  exit 1
fi
