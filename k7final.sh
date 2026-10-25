#!/bin/sh
# k7final.sh - final board launch: gandalf repair + fullscreen attempt + snapshot
#
# Runs as root (via bridge.conf emergency hook). Verifies whether the
# default-chrome-style=NH appreg.db patch removes the browser address bar.

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG=/mnt/us/k7.log
LIPC=/usr/bin/lipc-set-prop
LIPCG=/usr/bin/lipc-get-prop
EIPS=/usr/sbin/eips
CFG=/var/local/mesquite/browser/config.xml
DIAGDIR=/mnt/us/documents/k7diag
SITE="file:///mnt/us/documents/HZBoard.html"

log() { echo "$(date '+%m-%d %H:%M:%S') [final] $*" >> "$LOG"; }
scr() { "$EIPS" 0 0 "$*" >/dev/null 2>&1; log "screen: $*"; }

{
echo ""
echo "===== k7final $(date) ====="
echo "-- id: $(id) --"
echo "-- browser props --"
/usr/bin/sqlite3 /var/local/appreg.db "select name, value from properties where handlerId='com.lab126.browser' order by name;" 2>&1
} >> "$LOG" 2>&1

# ------------------------------------------------ 1. repair privilege escalation
mount -o rw,remount / 2>/dev/null
if [ -x /var/local/mkk/gandalf ]; then
    log "gandalf: ok"
else
    mkdir -p /var/local/mkk
    if cp /mnt/us/mkk/gandalf /var/local/mkk/gandalf 2>>"$LOG"; then
        chown root:root /var/local/mkk/gandalf 2>/dev/null
        chmod 0755 /var/local/mkk/gandalf
        log "gandalf: restored from USB backup"
    else
        log "gandalf: restore FAILED"
    fi
fi

# ------------------------------------------------ 2. keep config.xml fullscreen
if [ -f "$CFG" ]; then
    sed -i 's/viewmodes="application"/viewmodes="fullscreen"/' "$CFG" 2>>"$LOG"
    sed -i 's/pinchzoom" value="yes"/pinchzoom" value="no"/' "$CFG" 2>>"$LOG"
    log "config viewmodes now: $(grep -o 'viewmodes="[^"]*"' "$CFG" 2>/dev/null)"
    log "config pinchzoom now: $(grep -o 'pinchzoom" value="[^"]*"' "$CFG" 2>/dev/null)"
fi

# ------------------------------------------------ 3. launch the board
scr "K7: launching board"
$LIPC com.lab126.powerd preventScreenSaver 1 >>"$LOG" 2>&1
killall mesquite >>"$LOG" 2>&1
sleep 1
$LIPC com.lab126.appmgrd start "app://com.lab126.browser/?view=$SITE" >>"$LOG" 2>&1
log "launch rc=$? activeApp=$($LIPCG com.lab126.appmgrd activeApp 2>&1)"

# let the page render, then dismiss chrome as double insurance
sleep 4
$LIPC com.lab126.pillow dismissChrome "" >>"$LOG" 2>&1
log "dismissChrome rc=$?"

# ------------------------------------------------ 4. snapshot after render
sleep 20
log "pre-snapshot activeApp=$($LIPCG com.lab126.appmgrd activeApp 2>&1)"
dd if=/dev/fb0 of="$DIAGDIR/fb_B_board.raw" bs=4096 count=798 2>>"$LOG"
log "fbdump B: got=$(wc -c < "$DIAGDIR/fb_B_board.raw" 2>/dev/null) bytes"

# ------------------------------------------------ 5. power-key exit
scr "K7: press POWER to exit"
$LIPC com.lab126.powerd preventScreenSaver 0 >>"$LOG" 2>&1
log "waiting for goingToScreenSaver (120s max)"
( /usr/bin/lipc-wait-event -mt com.lab126.powerd goingToScreenSaver >>"$LOG" 2>&1 ) &
WPID=$!
sleep 120
kill "$WPID" 2>/dev/null
log "exit wait finished"

killall mesquite >>"$LOG" 2>&1
sleep 1
$LIPC com.lab126.appmgrd start "app://com.lab126.booklet.home" >>"$LOG" 2>&1
scr "K7 final done"
log "=== k7final complete ==="
mount -o ro,remount / 2>/dev/null
exit 0
