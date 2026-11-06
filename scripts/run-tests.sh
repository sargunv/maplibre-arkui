#!/usr/bin/env bash
# Installs a test HAP on a device, runs its hypium suite, and fails unless
# every case passed:
#
#   run-tests.sh <hdc connect key> <test HAP>
#
# The HAP's module runs ets/testrunner/OpenHarmonyTestRunner, which starts the
# suite, and its module.json names the bundle and the module. `aa test` exits 0
# whatever the cases did, so hypium's tally decides.
set -euo pipefail

usage="usage: run-tests.sh <hdc connect key> <test HAP>"
device=${1:?$usage}
hap=${2:?$usage}
hdc=(hdc -t "$device")
manifest=$(unzip -p "$hap" module.json)
bundle=$(jq -er .app.bundleName <<<"$manifest")
module=$(jq -er .module.name <<<"$manifest")

"${hdc[@]}" uninstall "$bundle" >/dev/null 2>&1 || true
"${hdc[@]}" install -r "$hap"
work=$(mktemp -d)
watchdog=
# The watchdog must see the marker and exit before the marker goes, or it
# outlives this script and can stop a later run's app.
trap 'touch "$work/finished"; [[ -z $watchdog ]] || wait "$watchdog"; rm -rf "$work"' EXIT
report="$work/report.txt"
# If the app dies or a case never settles, `aa test` waits forever. A watchdog
# ends the run when the app's process has been gone for 10 seconds, or at a
# deadline, after dumping the app's thread stacks, as MapLibre Native FFI's
# runner does.
deadline=${MAPLIBRE_ARKUI_TEST_TIMEOUT:-1800}
# The app's process is the one whose whole command line is the bundle name.
# pidof found no process on Oniro 7.0 in CI, so match the command line instead.
app_pid() {
  "${hdc[@]}" shell "ps -A -o PID,ARGS" | tr -d '\r' |
    awk -v bundle="$bundle" 'NF == 2 && $2 == bundle { print $1; exit }' || true
}
(
  SECONDS=0
  seen=false
  gone=0
  while ((SECONDS < deadline && gone < 2)); do
    sleep 1
    [[ -e $work/finished ]] && exit
    ((SECONDS % 5 == 0)) || continue
    pid=$(app_pid)
    if [[ -n $pid ]]; then
      seen=true
      gone=0
    elif [[ $seen == true ]]; then
      gone=$((gone + 1))
    fi
  done
  if ((gone >= 2)); then
    echo "error: $bundle exited before the suite finished; stopping the run" >&2
  else
    echo "error: the run took longer than $deadline seconds; stopping $bundle" >&2
    pid=$(app_pid)
    if [[ -n $pid ]]; then
      "${hdc[@]}" shell dumpcatcher -p "$pid" >&2 || true
    fi
    "${hdc[@]}" shell aa force-stop "$bundle" >/dev/null 2>&1
  fi
  "${hdc[@]}" shell "pkill -f 'aa test -b $bundle'" >/dev/null 2>&1 || true
) &
watchdog=$!
# hypium fails a case that doesn't settle within the per-case timeout.
"${hdc[@]}" shell aa test -b "$bundle" -m "$module" \
  -s unittest /ets/testrunner/OpenHarmonyTestRunner -s timeout 60000 |
  tr -d '\r' | tee "$report"
touch "$work/finished"

tally=$(grep -o 'Tests run: [0-9]*, Failure: [0-9]*, Error: [0-9]*, Pass: [0-9]*, Ignore: [0-9]*' "$report" | tail -1 || true)
if [[ -z $tally ]]; then
  echo "error: hypium didn't report a tally; the suite didn't finish" >&2
  # The device's newest app freeze and crash reports say why. The device's
  # shell expands these commands, not this one.
  # shellcheck disable=SC2016
  "${hdc[@]}" shell 'f=$(ls -t /data/log/eventlog/*TIMEOUT* /data/log/eventlog/*FREEZE* 2>/dev/null | head -1); [ -n "$f" ] && head -40 "$f"' >&2 || true
  # shellcheck disable=SC2016
  "${hdc[@]}" shell 'f=$(ls -t /data/log/faultlog/faultlogger/cppcrash-* 2>/dev/null | head -1); [ -n "$f" ] && head -40 "$f"' >&2 || true
  exit 1
fi
read -r ran failed errored passed ignored < <(sed -E 's/[^0-9]+/ /g' <<<"$tally")
echo "hypium ran $ran cases: $passed passed, $failed failed, $errored errors, $ignored ignored"
if ((ran == 0 || passed != ran)); then
  exit 1
fi
