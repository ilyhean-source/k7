#!/bin/sh
# Name: HZ Board
# Author: WorkBuddy
# Last-opened: 0
#
# Kindle 7 (KT2, FW 5.12.2.2) fullscreen kiosk launcher for the
# Hangzhou daily board (https://ilyhean-source.github.io/k7/).
#
# How it works:
#   1. Patches the stock browser config so it opens in fullscreen
#      viewmode (no address bar) with pinch-zoom disabled.
#   2. Keeps the screen awake.
#   3. Opens the dashboard in the stock browser.
#   4. Waits for the power button, then restores the Kindle UI.
#
# Based on the approach proven by the kindle-dash project
# (https://github.com/higoorc/kindle-dash) on old firmware.

SITE="https://ilyhean-source.github.io/k7/"

# Keep this entry pinned near the top of the recent list
sed -i "s/^# Last-opened:.*/# Last-opened: $(date +%s)/" "$0" 2>/dev/null

echo "[board] launching fullscreen kiosk..."

# --- Patch the stock browser config: hide the address bar ---
CFG=/var/local/mesquite/browser/config.xml
if [ -f "$CFG" ]; then
    cp "$CFG" "$CFG.wb_bak" 2>/dev/null
    if grep -q 'viewmodes="application"' "$CFG" 2>/dev/null; then
        sed -i 's/viewmodes="application"/viewmodes="fullscreen"/g' "$CFG"
        echo "[board] address bar hidden (fullscreen viewmode)"
    else
        echo "[board] viewmode pattern not found, toolbar may stay visible"
    fi
    if grep -q 'pinchzoom" value="yes"' "$CFG" 2>/dev/null; then
        sed -i 's/pinchzoom" value="yes"/pinchzoom" value="no"/g' "$CFG"
        echo "[board] pinch zoom disabled"
    fi
else
    echo "[board] browser config not found, running in normal mode"
fi

# --- Keep the screen awake ---
lipc-set-prop com.lab126.powerd preventScreenSaver 1

# --- Open the dashboard in the stock browser ---
echo "[board] opening $SITE"
lipc-set-prop com.lab126.appmgrd start "app://com.lab126.browser/?view=$SITE"

echo "[board] ready - press the power button to exit"

# --- Wait for the power button, then restore the Kindle UI ---
lipc-wait-event com.lab126.powerd PowerButtonQuickPress
lipc-set-prop com.lab126.powerd preventScreenSaver 0
killall mesquite 2>/dev/null
pkill mesquite 2>/dev/null
sleep 1
lipc-set-prop com.lab126.appmgrd start 'app://com.lab126.booklet.home/?context=0' 2>/dev/null
echo "[board] exited"
exit
