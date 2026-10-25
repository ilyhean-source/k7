#!/bin/sh
# Name: HZ Board
# Author: WorkBuddy
# Description: Fullscreen kiosk launcher for the Hangzhou daily board
#              (Kindle 7 / KT2, firmware 5.12.2.2)
# Version: 1.5
#
# Usage: runs automatically at boot via /mnt/us/emergency.sh, or type
#        ";log runme" in the Kindle search box. Press the power button to exit.
#
# v5 changes:
#  - config.xml is patched IN PLACE (same inode) so the browser keeps seeing
#    its own owner/permissions (framewor:javauser 0775). The previous mv-based
#    patch turned the file root:root 0644, which likely makes the stock
#    browser discard the patch and rewrite factory defaults.
#  - full config.xml dump + /etc/upstart job list + browser.js listing in log
#  - post-launch re-check of viewmodes (did the browser reset it on start?)
#  - powerd event sniffer logs every powerd event with timestamps, so a
#    power button press is recorded even if no exit is triggered

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG=/mnt/us/k7.log
LIPC=/usr/bin/lipc-set-prop
LIPCG=/usr/bin/lipc-get-prop
EIPS=/usr/sbin/eips
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
    echo "===== k7board v5 $(date) ====="
    echo "PATH=$PATH"
    echo "id=$(id 2>&1)"
    echo "-- binaries --"
    for b in lipc-set-prop lipc-get-prop lipc-wait-event eips mntroot \
             killall pkill sed grep head busybox nc curl wget stop start; do
        echo "$b -> $(command -v "$b" 2>/dev/null || echo MISSING)"
    done
    echo "-- upstart jobs --"
    ls /etc/upstart/ 2>&1 | head -40
    echo "-- browser files --"
    ls -la /var/local/mesquite/browser/ 2>&1 | head -25
    echo "-- browser javascripts --"
    ls -la /var/local/mesquite/browser/javascripts/ 2>&1 | head -15
    echo "-- FULL config.xml --"
    cat "$CFG" 2>&1
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

# powerd event sniffer: log every powerd event with timestamps for the
# whole session, so we can see exactly what a power button press emits.
( /usr/bin/lipc-wait-event -mt com.lab126.powerd '*' >> "$LOG" 2>&1 ) &

scr "K7 1/6 start"

# ------------------------------------------------------- wifi + keep awake
"$LIPC" com.lab126.wifid enable 1 >> "$LOG" 2>&1
log "wifid enable exit=$?"
"$LIPC" com.lab126.powerd preventScreenSaver 1 >> "$LOG" 2>&1
log "preventScreenSaver exit=$?"

# ------------------------------------------------------- fullscreen patch
mntroot rw >> "$LOG" 2>&1
log "mntroot exit=$?"

# Patch by rewriting the file in place: keeps inode, owner and permissions,
# so the browser still sees its own framewor:javauser 0775 config file.
patch_cfg() {
    _pat="$1"
    _rep="$2"
    grep -q "$_pat" "$CFG" 2>/dev/null || return 1
    sed "s/$_pat/$_rep/g" "$CFG" > "$CFG.new" 2>>"$LOG"
    if [ ! -s "$CFG.new" ]; then
        rm -f "$CFG.new" 2>/dev/null
        return 1
    fi
    chattr -i "$CFG" 2>/dev/null
    if cat "$CFG.new" > "$CFG" 2>>"$LOG"; then
        rm -f "$CFG.new"
        log "patched in place (inode/owner/perms kept): $_pat -> $_rep"
        return 0
    fi
    # Fallback: replace the file, then restore the original metadata by hand.
    mv "$CFG.new" "$CFG" 2>>"$LOG"
    chmod 0775 "$CFG" 2>>"$LOG"
    chown framewor:javauser "$CFG" 2>>"$LOG"
    log "patched via replace (metadata restored): $_pat -> $_rep"
    return 0
}

patch_cfg 'viewmodes="application"' 'viewmodes="fullscreen"'
patch_cfg 'pinchzoom" value="yes"' 'pinchzoom" value="no"'

log "viewmode now: $(grep -o 'viewmodes="[^"]*"' "$CFG" 2>/dev/null)"
log "pinchzoom now: $(grep -o 'pinchzoom" value="[^"]*"' "$CFG" 2>/dev/null)"
log "config stat now: $(ls -la "$CFG" 2>/dev/null)"
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
    while [ $_w -lt 10 ]; do
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

# ------------------------------------------- post-launch config verification
# Decisive check: if viewmodes flipped back to "application" here, the stock
# browser reset the config when it started (regardless of our patch method).
sleep 5
log "POST-LAUNCH viewmodes: $(grep -o 'viewmodes="[^"]*"' "$CFG" 2>/dev/null)"
log "POST-LAUNCH pinchzoom: $(grep -o 'pinchzoom" value="[^"]*"' "$CFG" 2>/dev/null)"
log "POST-LAUNCH config stat: $(ls -la "$CFG" 2>/dev/null)"

if [ -z "$ok" ]; then
    "$EIPS" -c >/dev/null 2>&1
    "$EIPS" 10 180 "K7 BOARD FAILED" >/dev/null 2>&1
    "$EIPS" 10 220 "all launch methods failed" >/dev/null 2>&1
    "$EIPS" 10 260 "connect USB, open k7.log" >/dev/null 2>&1
    log "=== ALL LAUNCH METHODS FAILED ==="
    pkill -f 'lipc-wait-event -mt' 2>/dev/null
    exit 1
fi

log "=== dashboard up, waiting for exit ==="

# -------------------------------------------------------------- exit logic
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
pkill -f 'lipc-wait-event -mt' 2>/dev/null
for c in /proc/[0-9]*/comm; do
    [ -r "$c" ] || continue
    grep -q httpd "$c" 2>/dev/null && kill "${c#/proc/}" 2>/dev/null
done
sleep 1
"$LIPC" com.lab126.appmgrd start "app://com.lab126.booklet.home/?context=0" >> "$LOG" 2>&1
log "=== exited, back to library ==="
exit 0
