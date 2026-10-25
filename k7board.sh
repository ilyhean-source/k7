#!/bin/sh
# Name: HZ Board
# Author: WorkBuddy
#
# Kindle 7 (KT2, FW 5.12.2.2) fullscreen kiosk launcher for the
# Hangzhou daily board (https://ilyhean-source.github.io/k7/).
#
# Usage: copy this file into the Kindle's "documents" folder over USB,
# then tap the book "HZ Board" in the library. Press the power button
# to exit back to the library.
#
# How it works:
#   1. Patches the stock browser config so it opens in fullscreen
#      viewmode (no address bar) with pinch-zoom disabled.
#   2. Keeps the screen awake and makes sure WiFi is on.
#   3. Opens the dashboard in the stock browser.
#   4. Waits for the power button, then restores the Kindle UI.
#
# The config patch and the browser launch follow the recipe proven by
# higoorc/kindle-dash on the same mesquite browser generation
# (Kindle Paperwhite 1, FW 5.3.x).

SITE="https://ilyhean-source.github.io/k7/"
LOG=/mnt/us/k7.log

say() {
    echo "$*"
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null
}

echo "=== k7board run $(date) ===" >> "$LOG" 2>/dev/null

say "[board] launching fullscreen kiosk..."

# --- Make sure the dashboard can reach the network ---
lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null

# --- Patch the stock browser config: hide the address bar ---
CFG=/var/local/mesquite/browser/config.xml
if [ -f "$CFG" ]; then
    cp "$CFG" "$CFG.wb_bak" 2>/dev/null
    mntroot rw 2>/dev/null
    if grep -q 'viewmodes="application"' "$CFG" 2>/dev/null; then
        sed 's/viewmodes="application"/viewmodes="fullscreen"/g' "$CFG" > "$CFG.new" 2>/dev/null
        [ -s "$CFG.new" ] && mv "$CFG.new" "$CFG" 2>/dev/null
        say "[board] address bar hidden (fullscreen viewmode)"
    else
        say "[board] viewmode pattern not found, toolbar may stay visible"
    fi
    if grep -q 'pinchzoom" value="yes"' "$CFG" 2>/dev/null; then
        sed 's/pinchzoom" value="yes"/pinchzoom" value="no"/g' "$CFG" > "$CFG.new" 2>/dev/null
        [ -s "$CFG.new" ] && mv "$CFG.new" "$CFG" 2>/dev/null
        say "[board] pinch zoom disabled"
    fi
else
    say "[board] browser config not found, running in normal mode"
fi

# --- Keep the screen awake ---
lipc-set-prop com.lab126.powerd preventScreenSaver 1

# --- Fresh browser instance so the ?view= URL is honored ---
killall mesquite 2>/dev/null
pkill mesquite 2>/dev/null
sleep 1

# --- Open the dashboard in the stock browser ---
say "[board] opening $SITE"
lipc-set-prop com.lab126.appmgrd start "app://com.lab126.browser/?view=$SITE"

say "[board] ready - press the power button to exit"

# --- Wait for the power button, then restore the Kindle UI ---
lipc-wait-event com.lab126.powerd PowerButtonQuickPress
lipc-set-prop com.lab126.powerd preventScreenSaver 0
killall mesquite 2>/dev/null
pkill mesquite 2>/dev/null
sleep 1
lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home 2>/dev/null
say "[board] exited"
exit
