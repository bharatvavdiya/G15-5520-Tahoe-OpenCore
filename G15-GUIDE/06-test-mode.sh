#!/bin/bash
# Test mode for the graphics tests:
#  - no system sleep and no display sleep (WhateverXe sleep/wake is experimental; display off/on can hang Iris Xe 46A6)
#  - Apple's media-analysis agents off (they start GPU compute work right after login, a reported Iris Xe hang trigger)
#   sudo bash /Volumes/1401/G15-GUIDE/06-test-mode.sh        -> test mode ON
#   sudo bash /Volumes/1401/G15-GUIDE/06-test-mode.sh undo   -> back to normal
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
[ "$(id -u)" = 0 ] || { echo "STOP: run it with sudo:  sudo bash \"$0\""; exit 1; }
CUID=$(stat -f %u /dev/console)
if [ "${1:-}" = undo ]; then
  pmset -a disablesleep 0
  pmset restoredefaults
  launchctl enable "gui/$CUID/com.apple.mediaanalysisd" 2>/dev/null
  launchctl enable "gui/$CUID/com.apple.photoanalysisd" 2>/dev/null
  echo "DONE: normal sleep settings and media analysis restored (log out and back in)."
else
  pmset -a sleep 0 displaysleep 0 standby 0 hibernatemode 0 powernap 0 autopoweroff 0
  pmset -a disablesleep 1
  for a in com.apple.mediaanalysisd com.apple.photoanalysisd; do
    launchctl disable "gui/$CUID/$a" 2>/dev/null
    launchctl bootout "gui/$CUID/$a" 2>/dev/null
  done
  echo "DONE: test mode ON (no sleep, no display sleep, media analysis off). Keep the lid open during tests."
fi
echo "--- current power settings:"
pmset -g | grep -E ' sleep|displaysleep|disablesleep|standby|hibernatemode|powernap|SleepDisabled'
