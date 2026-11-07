#!/usr/bin/env bash
# Turns a device's screen on, keeps it on, and swipes away the lock screen, so
# an app can start and the tests' UI cases see their pages:
#
#   wake-device.sh <hdc connect key>
#
# For the Oniro emulator; ohos-key.sh runs it. The emulator turns its screen off
# after a while and shows the lock screen when it wakes. `aa start` then fails,
# and hypium's UI cases fail behind it. The swipe dismisses a lock screen without a passcode, as the
# emulator's is.
set -euo pipefail

device=${1:?usage: wake-device.sh <hdc connect key>}
hdc=(hdc -t "$device")

# A running lock survives the lock screen resetting the timeout. A reboot
# releases it. The shell is available before the power service has created
# this lock, and the command returns success even when it acquired nothing.
for ((attempt = 0; attempt < 30; attempt++)); do
  "${hdc[@]}" shell power-shell dump -t >/dev/null
  if "${hdc[@]}" shell power-shell dump -r | grep -q 'name=PowerMgrKeepOnLock.*state=1'; then
    break
  fi
  if ((attempt == 29)); then
    echo "error: the emulator didn't acquire its screen running lock" >&2
    exit 1
  fi
  sleep 1
done
"${hdc[@]}" shell power-shell wakeup >/dev/null
layout=/data/local/tmp/wake-device-layout.json
# An empty layout during boot isn't an unlocked screen. Wait for the lock
# screen to initialize, then verify it disappears after the swipe animation.
for ((attempt = 0; attempt < 30; attempt++)); do
  if "${hdc[@]}" shell param get bootevent.lockscreen.ready | grep -q true; then
    state=$("${hdc[@]}" shell "uitest dumpLayout -p $layout >/dev/null && if grep -qi screenlock $layout; then echo locked; elif grep -q com.ohos.sceneboard $layout; then echo ready; fi" | tr -d '\r')
    if [[ $state == ready ]]; then
      echo "emulator screen is awake and unlocked" >&2
      exit 0
    fi
    if [[ $state == locked ]]; then
      # From near the bottom to near the top, in the screen's own pixels.
      size=$("${hdc[@]}" shell hidumper -s RenderService -a screen | grep -o 'physical resolution=[0-9]*x[0-9]*' | head -1)
      size=${size#physical resolution=}
      width=${size%x*}
      height=${size#*x}
      "${hdc[@]}" shell uitest uiInput swipe $((width / 2)) $((height * 5 / 6)) $((width / 2)) $((height / 6)) 800 >/dev/null
    fi
  fi
  sleep 1
done
echo "error: the emulator's lock screen didn't become ready and unlock" >&2
"${hdc[@]}" shell hidumper -s ScreenlockService -a -all >&2 || true
exit 1
