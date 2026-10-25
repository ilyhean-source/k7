#!/bin/sh
# Name: HZ Board
# Author: WorkBuddy
# Description: Fullscreen kiosk launcher for the Hangzhou daily board
#              (Kindle 7 / KT2, firmware 5.12.2.2)
# Version: 1.4
#
# Usage: type ";log runme" in the Kindle search box and press enter.
#        Press the power button to exit back to the library.
#
# Diagnostics: every run appends a full report to /mnt/us/k7.log
# (connect the Kindle over USB, open k7.log at the drive root).
# This version prints each step on screen with eips and tries several
# different ways to open the dashboard, logging the result of each.

# --- environment: the ;log bridge runs this script through su, whose
# --- PATH may be minimal, so set our own and use absolute paths.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG=/mnt/us/k7.log
LIPC=/usr/bin/lipc-set-prop
LIPCG=/usr/bin/lipc-get-prop
EIPS=/usr/bin/eips
CFG=/var/local/mesquite/browser/config.xml

SITE_LOCAL="file:///mnt/us/documents/HZBoard.html"
SITE_HTTPD="http://127.0.0.1:8000/documents/HZBoard.html"
SITE_REMOTE="https://ilyhean-source.github.io/k7/"
SITE_TEST="http://example.com"

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"; }
scr() { "$EIPS" 0 0 "$*" >/dev/null 2>&1; log "screen: $*"; }

# ------------------------------------------------------------------ report
{
    echo ""
    echo "===== k7board v4 $(date) ====="
    echo "PATH=$PATH"
    echo "id=$(id 2>&1)"
    echo "-- binaries --"
    for b in lipc-set-prop lipc-get-prop lipc-wait-event eips mntroot \
             killall pkill sed grep head busybox nc curl wget; do
        echo "$b -> $(command -v "$b" 2>/dev/null || echo MISSING)"
    done
    echo "-- browser files --"
    ls -la /var/local/mesquite/browser/ 2>&1 | head -25
    echo "-- config keys --"
    grep -o 'viewmodes="[^"]*"' "$CFG" 2>&1
    grep -o 'pinchzoom" value="[^"]*"' "$CFG" 2>&1
    echo "-- rootfs write test --"
    if touch "$CFG.wtest" 2>/dev/null; then
        echo "WRITABLE"
        rm -f "$CFG.wtest"
    else
        echo "READ-ONLY"
    fi
    echo "-- foreground app before --"
    "$LIPCG" com.lab126.appmgrd activeApp 2>&1
} >> "$LOG" 2>&1

scr "K7 1/6 start"

# ------------------------------------------------------- wifi + keep awake
"$LIPC" com.lab126.wifid enable 1 >> "$LOG" 2>&1
log "wifid enable exit=$?"
"$LIPC" com.lab126.powerd preventScreenSaver 1 >> "$LOG" 2>&1
log "preventScreenSaver exit=$?"

# ------------------------------------------------------- fullscreen patch
mntroot rw >> "$LOG" 2>&1
log "mntroot exit=$?"
if grep -q 'viewmodes="application"' "$CFG" 2>/dev/null; then
    sed 's/viewmodes="application"/viewmodes="fullscreen"/g' "$CFG" > "$CFG.new" 2>>"$LOG"
    if [ -s "$CFG.new" ]; then
        mv "$CFG.new" "$CFG" 2>>"$LOG"
    else
        rm -f "$CFG.new" 2>/dev/null
    fi
fi
if grep -q 'pinchzoom" value="yes"' "$CFG" 2>/dev/null; then
    sed 's/pinchzoom" value="yes"/pinchzoom" value="no"/g' "$CFG" > "$CFG.new" 2>>"$LOG"
    if [ -s "$CFG.new" ]; then
        mv "$CFG.new" "$CFG" 2>>"$LOG"
    else
        rm -f "$CFG.new" 2>/dev/null
    fi
fi
log "viewmode now: $(grep -o 'viewmodes="[^"]*"' "$CFG" 2>/dev/null)"
log "pinchzoom now: $(grep -o 'pinchzoom" value="[^"]*"' "$CFG" 2>/dev/null)"
mntroot ro >> "$LOG" 2>&1
log "mntroot ro exit=$?"
scr "K7 2/6 patched"

# ------------------------------------------------------------------ helpers
killall mesquite >> "$LOG" 2>&1
pkill mesquite >> "$LOG" 2>&1
sleep 1

browser_alive() {
    for c in /proc/[0-9]*/comm; do
        [ -r "$c" ] || continue
        grep -q mesquite "$c" 2>/dev/null && return 0
    done
    return 1
}

launch() {
    "$LIPC" com.lab126.appmgrd start "app://com.lab126.browser/?view=$1" >> "$LOG" 2>&1
    log "launch exit=$? url=$1"
}

try_url() {
    _label="$1"
    _url="$2"
    scr "K7 opening $_label"
    launch "$_url"
    _w=0
    while [ $_w -lt 8 ]; do
        sleep 1
        browser_alive && break
        _w=$((_w + 1))
    done
    if browser_alive; then
        log "OK browser running: $_label"
        log "foreground app now: $("$LIPCG" com.lab126.appmgrd activeApp 2>&1)"
        return 0
    fi
    log "FAIL no mesquite process after: $_label"
    return 1
}

# ------------------------------------------------------------ launch ladder
ok=""

try_url "local file" "$SITE_LOCAL" && ok=1

if [ -z "$ok" ] && command -v busybox >/dev/null 2>&1; then
    scr "K7 starting local server"
    busybox httpd -p 8000 -h /mnt/us >> "$LOG" 2>&1 &
    sleep 1
    log "httpd start exit=$?"
    try_url "localhost server" "$SITE_HTTPD" && ok=1
fi

if [ -z "$ok" ]; then
    try_url "online page" "$SITE_REMOTE" && ok=1
fi

if [ -z "$ok" ]; then
    try_url "test page" "$SITE_TEST" && ok=1
fi

# last resort: run the browser binary directly, without appmgrd
if [ -z "$ok" ]; then
    scr "K7 direct launch"
    /usr/bin/mesquite -l com.lab126.browser -c /var/local/mesquite/browser/ >> "$LOG" 2>&1 &
    sleep 5
    if browser_alive; then
        log "OK mesquite direct launch"
        ok=1
    else
        log "FAIL direct mesquite launch"
    fi
fi

scr "K7 6/6 ready"

if [ -z "$ok" ]; then
    "$EIPS" -c >/dev/null 2>&1
    "$EIPS" 10 180 "K7 BOARD FAILED" >/dev/null 2>&1
    "$EIPS" 10 220 "all launch methods failed" >/dev/null 2>&1
    "$EIPS" 10 260 "connect USB, open k7.log" >/dev/null 2>&1
    log "=== ALL LAUNCH METHODS FAILED ==="
    exit 1
fi

log "=== dashboard up, waiting for exit ==="

# -------------------------------------------------------------- exit logic
# The power button event name differs between firmwares; wait for either.
# Also give up if the browser disappears on its own (user exited it).
rm -f /mnt/us/k7exit
( /usr/bin/lipc-wait-event com.lab126.powerd goingToScreenSaver >> "$LOG" 2>&1; echo ss > /mnt/us/k7exit ) &
( /usr/bin/lipc-wait-event com.lab126.powerd PowerButtonQuickPress >> "$LOG" 2>&1; echo pb > /mnt/us/k7exit ) &

_w=0
while [ ! -f /mnt/us/k7exit ]; do
    sleep 2
    _w=$((_w + 1))
    if [ $_w -gt 1800 ]; then
        log "exit wait timeout after 1 hour"
        break
    fi
    if ! browser_alive; then
        log "browser closed by user"
        break
    fi
done
log "exit trigger: $(cat /mnt/us/k7exit 2>/dev/null)"
rm -f /mnt/us/k7exit

# ---------------------------------------------------------------- cleanup
"$LIPC" com.lab126.powerd preventScreenSaver 0 >> "$LOG" 2>&1
killall mesquite >> "$LOG" 2>&1
pkill mesquite >> "$LOG" 2>&1
for c in /proc/[0-9]*/comm; do
    [ -r "$c" ] || continue
    grep -q httpd "$c" 2>/dev/null && kill "${c#/proc/}" 2>/dev/null
done
sleep 1
"$LIPC" com.lab126.appmgrd start "app://com.lab126.booklet.home/?context=0" >> "$LOG" 2>&1
log "=== exited, back to library ==="
exit 0
