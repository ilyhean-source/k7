#!/bin/sh
# Name: HZ Board
# Author: WorkBuddy
#
# Kindle 7 (KT2, FW 5.12.2.2) fullscreen kiosk launcher for the
# Hangzhou daily board. The dashboard itself lives in the documents
# folder as HZBoard.html, so it opens without any network access or
# certificate trust (live weather still loads over WiFi when possible).
#
# Usage:
#   1. Copy this file and HZBoard.html into the Kindle "documents" folder.
#   2. Easiest: tap the book "HZ Board" in the library (the browser is
#      already patched to fullscreen).
#   3. Permanent kiosk: type ";log runme" in the search box. Press the
#      power button to exit back to the library.
#
# How it works:
#   1. Patches the stock browser config so it opens in fullscreen
#      viewmode (no address bar) with pinch-zoom disabled.
#   2. Keeps the screen awake and makes sure WiFi is on.
#   3. Opens the dashboard (local file first, online page as fallback).
#   4. Waits for the power button, then restores the Kindle UI.
#
# The config patch and the browser launch follow the recipe proven by
# higoorc/kindle-dash on the same mesquite browser generation.
# NOTE: on Kindle firmware the power button fires the powerd event
# "goingToScreenSaver" - there is no "PowerButtonQuickPress" event.

SITE_LOCAL="file:///mnt/us/documents/HZBoard.html"
SITE_REMOTE="https://ilyhean-source.github.io/k7/"
LOG=/mnt/us/k7.log

say() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null
}

echo "=== k7board run $(date) ===" >> "$LOG" 2>/dev/null
say "[board] launching fullscreen kiosk..."

# --- Make sure the dashboard can reach the network (for live weather) ---
lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
lipc-set-prop com.lab126.wifid enable 1 2>/dev/null

# --- Patch the stock browser config: hide the address bar ---
CFG=/var/local/mesquite/browser/config.xml
mntroot rw 2>/dev/null
if grep -q 'viewmodes="application"' "$CFG" 2>/dev/null; then
    sed 's/viewmodes="application"/viewmodes="fullscreen"/g' "$CFG" > "$CFG.new" 2>/dev/null
    [ -s "$CFG.new" ] && mv "$CFG.new" "$CFG" 2>/dev/null
    say "[board] address bar hidden (fullscreen viewmode)"
elif grep -q 'viewmodes="fullscreen"' "$CFG" 2>/dev/null; then
    say "[board] fullscreen viewmode already active"
else
    say "[board] viewmode pattern not found, toolbar may stay visible"
fi
if grep -q 'pinchzoom" value="yes"' "$CFG" 2>/dev/null; then
    sed 's/pinchzoom" value="yes"/pinchzoom" value="no"/g' "$CFG" > "$CFG.new" 2>/dev/null
    [ -s "$CFG.new" ] && mv "$CFG.new" "$CFG" 2>/dev/null
    say "[board] pinch zoom disabled"
fi

# --- Keep the screen awake ---
lipc-set-prop com.lab126.powerd preventScreenSaver 1

# --- Fresh browser instance so the ?view= URL is honored ---
killall mesquite 2>/dev/null
pkill mesquite 2>/dev/null
sleep 1

# --- Open the dashboard: local file first, online page as fallback ---
open_url() {
    lipc-set-prop com.lab126.appmgrd start "app://com.lab126.browser/?view=$1" 2>/dev/null
}
browser_alive() {
    for c in /proc/[0-9]*/comm; do
        [ -r "$c" ] || continue
        grep -q mesquite "$c" 2>/dev/null && return 0
    done
    return 1
}

say "[board] opening local dashboard"
open_url "$SITE_LOCAL"
w=0
while [ $w -lt 10 ]; do
    sleep 1
    browser_alive && break
    w=$((w + 1))
done
if browser_alive; then
    say "[board] dashboard open (local file)"
else
    say "[board] browser did not start, trying online page"
    eips 1 0 "HZ Board: retrying online..." 2>/dev/null
    open_url "$SITE_REMOTE"
    w=0
    while [ $w -lt 10 ]; do
        sleep 1
        browser_alive && break
        w=$((w + 1))
    done
    if browser_alive; then
        say "[board] dashboard open (online page)"
    else
        say "[board] FAILED: browser did not start"
        eips 1 0 "HZ Board: browser failed - see k7.log" 2>/dev/null
    fi
fi

say "[board] ready - press the power button to exit"

# --- Wait for the power button, then restore the Kindle UI ---
lipc-wait-event com.lab126.powerd goingToScreenSaver
say "[board] power button pressed, exiting"
lipc-set-prop com.lab126.powerd preventScreenSaver 0
killall mesquite 2>/dev/null
pkill mesquite 2>/dev/null
sleep 1
lipc-set-prop com.lab126.appmgrd start "app://com.lab126.booklet.home/?context=0" 2>/dev/null
say "[board] exited"
exit
