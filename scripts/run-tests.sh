#!/usr/bin/env bash
# Installs a test HAP on a device, runs its hypium suite, and fails unless
# every case passed:
#
#   run-tests.sh <hdc connect key> <test HAP>
#
# The HAP's module runs ets/testrunner/OpenHarmonyTestRunner, which starts the
# suite. `aa test` exits 0 whatever the cases did, so hypium's tally decides.
set -euo pipefail

usage="usage: run-tests.sh <hdc connect key> <test HAP>"
device=${1:?$usage}
hap=${2:?$usage}
hdc=(hdc -t "$device")
bundle=org.maplibre.arkui.test
module=entry_test

"${hdc[@]}" uninstall "$bundle" >/dev/null 2>&1 || true
"${hdc[@]}" install -r "$hap"
report=$(mktemp)
trap 'rm -f "$report"' EXIT
# A case that never settles would hold `aa test` until its own timeout.
timeout "${MAPLIBRE_ARKUI_TEST_TIMEOUT:-600}" "${hdc[@]}" shell aa test -b "$bundle" -m "$module" \
  -s unittest /ets/testrunner/OpenHarmonyTestRunner -s timeout 60000 |
  tr -d '\r' | tee "$report"

tally=$(grep -o 'Tests run: [0-9]*, Failure: [0-9]*, Error: [0-9]*, Pass: [0-9]*, Ignore: [0-9]*' "$report" | tail -1 || true)
if [[ -z $tally ]]; then
  echo "error: hypium didn't report a tally; the suite didn't finish" >&2
  exit 1
fi
read -r ran failed errored passed ignored < <(sed -E 's/[^0-9]+/ /g' <<<"$tally")
echo "hypium ran $ran cases: $passed passed, $failed failed, $errored errors, $ignored ignored"
if ((ran == 0 || passed != ran)); then
  exit 1
fi
