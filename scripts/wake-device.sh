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

"${hdc[@]}" shell power-shell wakeup >/dev/null
# A day, so a long run doesn't sleep. A reboot restores the default.
"${hdc[@]}" shell power-shell timeout -o 86400000 >/dev/null
layout=/data/local/tmp/wake-device-layout.json
if "${hdc[@]}" shell "uitest dumpLayout -p $layout >/dev/null && grep -q screenlock $layout && echo locked" |
  grep -q locked; then
  # From near the bottom to near the top of the screen, in its own pixels.
  size=$("${hdc[@]}" shell hidumper -s RenderService -a screen | grep -o 'physical resolution=[0-9]*x[0-9]*' | head -1)
  size=${size#physical resolution=}
  width=${size%x*}
  height=${size#*x}
  "${hdc[@]}" shell uitest uiInput swipe $((width / 2)) $((height * 5 / 6)) $((width / 2)) $((height / 6)) 800 >/dev/null
fi
