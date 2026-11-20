#!/bin/bash
# Test mode = the safe daily settings for this laptop:
#  - no system sleep and no display sleep: the firmware has no S3 sleep, WhateverXe sleep/wake is experimental,
#    and display off/on has hung other Iris Xe 46A6 laptops (WhateverXe issues #90, #116, #117)
#  - Apple's media-analysis agents off (they start GPU compute work right after login, a reported Iris Xe hang trigger)
#   sudo bash /Volumes/1401/G15-GUIDE/06-test-mode.sh        -> test mode ON
# There is deliberately no "undo": turning sleep back on is not safe on this laptop yet.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
if [ -n "${1:-}" ]; then
  echo "STOP: not available - this laptop has no S3 sleep and display off/on is untested with Iris Xe acceleration. Nothing was changed."
  exit 1
fi
[ "$(id -u)" = 0 ] || { echo "STOP: run it with sudo:  sudo bash \"$0\""; exit 1; }
CUID=$(stat -f %u /dev/console)
pmset -a sleep 0 displaysleep 0 standby 0 hibernatemode 0 powernap 0 autopoweroff 0
pmset -a disablesleep 1
for a in com.apple.mediaanalysisd com.apple.photoanalysisd; do
  launchctl disable "gui/$CUID/$a" 2>/dev/null
  launchctl bootout "gui/$CUID/$a" 2>/dev/null
done
echo "DONE: test mode ON (no sleep, no display sleep, media analysis off). Keep the lid open."
echo "--- current power settings:"
pmset -g | grep -E ' sleep|displaysleep|disablesleep|standby|hibernatemode|powernap|SleepDisabled'
