#!/bin/sh
# k7fix.sh - decisive test for hiding the Kindle 7 browser address bar
#
# Runs once at boot via /mnt/us/emergency.sh. Tries three independent ways to
# kill the browser chrome (address bar) and takes a framebuffer snapshot
# after each attempt, so the result can be verified offline on a PC.
#
# Attempt 1: baseline (config.xml already says fullscreen, chrome still shows)
# Attempt 2: lipc-set-prop com.lab126.pillow dismissChrome ""
# Attempt 3: patch appreg.db viewModes for com.lab126.browser + relaunch
# Attempt 4: lipc-set-prop com.lab126.pillow disableEnablePillow disable
#
# Also tests whether the raw power key device (/dev/input/event0) reports
# presses even while preventScreenSaver is on - that is the exit channel.

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG=/mnt/us/k7.log
LIPC=/usr/bin/lipc-set-prop
LIPCG=/usr/bin/lipc-get-prop
EIPS=/usr/sbin/eips
CFG=/var/local/mesquite/browser/config.xml
DB=/var/local/appreg.db
DIAGDIR=/mnt/us/documents/k7diag
SITE="file:///mnt/us/documents/HZBoard.html"

log() { echo "$(date '+%m-%d %H:%M:%S') [fix] $*" >> "$LOG"; }
scr() { "$EIPS" 0 0 "$*" >/dev/null 2>&1; log "screen: $*"; }

mkdir -p "$DIAGDIR" 2>/dev/null

# framebuffer snapshot: read the exact amount the fb reports
fbdump() {
    _name="$1"
    _vs=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)
    _bpp=$(cat /sys/class/graphics/fb0/bits_per_pixel 2>/dev/null)
    _w=$(echo "$_vs" | cut -d, -f1)
    _h=$(echo "$_vs" | cut -d, -f2)
    [ -z "$_w" ] && _w=600
    [ -z "$_h" ] && _h=800
    [ -z "$_bpp" ] && _bpp=8
    _bytes=$(( (_w * _h * _bpp) / 8 ))
    dd if=/dev/fb0 of="$_DIAGDIR/fb_$_name.raw" bs="$_bytes" count=1 2>>"$LOG"
    log "fbdump $_name: ${_w}x${_h} bpp=$_bpp bytes=$_bytes -> fb_$_name.raw ($(wc -c < "$_DIAGDIR/fb_$_name.raw" 2>/dev/null) bytes on disk)"
}

launch() {
    killall mesquite >>"$LOG" 2>&1
    sleep 1
    $LIPC com.lab126.appmgrd start "app://com.lab126.browser/?view=$1" >>"$LOG" 2>&1
}

{
    echo ""
    echo "===== k7fix $(date) ====="
    echo "-- sqlite3 present? --"
    command -v sqlite3 || ls -la /usr/bin/sqlite3 2>&1
    echo "-- appreg.db present? --"
    ls -la "$DB" 2>&1
    echo "-- backup appreg.db --"
    cp "$DB" "$DIAGDIR/appreg.db.bak" 2>&1 && log "appreg.db backed up to documents/k7diag/"
    echo "-- ALL viewModes values in appreg.db --"
    /usr/bin/sqlite3 "$DB" "select handlerid, value from properties where name='viewModes';" 2>&1
    echo "-- browser properties --"
    /usr/bin/sqlite3 "$DB" "select name, value from properties where handlerid='com.lab126.browser';" 2>&1
    echo "-- fb info --"
    cat /sys/class/graphics/fb0/virtual_size 2>&1
    cat /sys/class/graphics/fb0/bits_per_pixel 2>&1
} >> "$LOG" 2>&1

scr "K7 FIX 1/4 baseline"

# ---------------------------------------------------------------- attempt 1
launch "$SITE"
sleep 9
fbdump "1_baseline"
log "attempt1 baseline done"

# ---------------------------------------------------------------- attempt 2
scr "K7 FIX 2/4 dismissChrome"
$LIPC com.lab126.pillow dismissChrome "" >>"$LOG" 2>&1
log "dismissChrome exit=$?"
sleep 4
fbdump "2_dismiss"
log "attempt2 dismissChrome done"

# ---------------------------------------------------------------- attempt 3
scr "K7 FIX 3/4 appreg"
log "patching appreg.db viewModes for com.lab126.browser"
/usr/bin/sqlite3 "$DB" "update properties set value='fullscreen' where handlerid='com.lab126.browser' and name='viewModes';" >>"$LOG" 2>&1
/usr/bin/sqlite3 "$DB" "select value from properties where handlerid='com.lab126.browser' and name='viewModes';" >>"$LOG" 2>&1
launch "$SITE"
sleep 9
fbdump "3_appreg"
log "attempt3 appreg done"

# ---------------------------------------------------------------- attempt 4
scr "K7 FIX 4/4 noPillow"
$LIPC com.lab126.pillow disableEnablePillow "disable" >>"$LOG" 2>&1
log "disableEnablePillow exit=$?"
sleep 4
fbdump "4_nopillow"
# re-enable pillow so the device stays usable afterwards
$LIPC com.lab126.pillow disableEnablePillow "enable" >>"$LOG" 2>&1
log "pillow re-enabled exit=$?"
log "attempt4 done"

# ------------------------------------------------- power key raw input test
scr "K7: press POWER once now"
log "power key test: reading /dev/input/event0 for 45s"
( od -An -tu1 -w16 /dev/input/event0 > "$DIAGDIR/event0.log" 2>&1 ) &
ODPID=$!
sleep 45
kill "$ODPID" 2>/dev/null
log "event0 raw dump:"; cat "$DIAGDIR/event0.log" >> "$LOG" 2>/dev/null
log "power key test done ($(wc -l < "$DIAGDIR/event0.log" 2>/dev/null) lines captured)"

# --------------------------------------------------------- exit channel test
# NOTE: deliberately NOT setting preventScreenSaver here - v5 proved it
# suppresses the goingToScreenSaver event that we need for exit.
scr "K7: waiting for power exit"
log "waiting for goingToScreenSaver (no preventScreenSaver)"
/usr/bin/lipc-wait-event com.lab126.powerd goingToScreenSaver >> "$LOG" 2>&1
log "EXIT EVENT CAUGHT: goingToScreenSaver"
killall mesquite >>"$LOG" 2>&1
sleep 1
$LIPC com.lab126.appmgrd start "app://com.lab126.booklet.home" >>"$LOG" 2>&1
log "returned to library"
scr "K7 exited"
exit 0
