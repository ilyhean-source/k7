#!/bin/sh
# k7fix3.sh - round 3: just re-open the board and snapshot after it renders
#
# Round 2 patched appreg.db (default-chrome-style=NH + searchbar-mode=transient)
# and restarted the framework, but the framebuffer snapshot caught the boot
# splash (framework was still coming up). The patch is already live in the
# running framework - all we need is a clean board launch + late snapshot.

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG=/mnt/us/k7.log
LIPC=/usr/bin/lipc-set-prop
LIPCG=/usr/bin/lipc-get-prop
EIPS=/usr/sbin/eips
DB=/var/local/appreg.db
DIAGDIR=/mnt/us/documents/k7diag
SITE="file:///mnt/us/documents/HZBoard.html"
SQL=/usr/bin/sqlite3

log() { echo "$(date '+%m-%d %H:%M:%S') [fix3] $*" >> "$LOG"; }
scr() { "$EIPS" 0 0 "$*" >/dev/null 2>&1; log "screen: $*"; }

fbdump() {
    _name="$1"
    dd if=/dev/fb0 of="$DIAGDIR/fb_$_name.raw" bs=4096 count=798 2>>"$LOG"
    log "fbdump $_name: got=$(wc -c < "$DIAGDIR/fb_$_name.raw" 2>/dev/null) bytes"
}

{
    echo ""
    echo "===== k7fix3 $(date) ====="
    echo "-- browser props (should show NH + transient) --"
    $SQL "$DB" "select name, value from properties where handlerId='com.lab126.browser' order by name;" 2>&1
} >> "$LOG" 2>&1

scr "K7: opening board"
$LIPC com.lab126.powerd preventScreenSaver 1 >>"$LOG" 2>&1
killall mesquite >>"$LOG" 2>&1
sleep 1
$LIPC com.lab126.appmgrd start "app://com.lab126.browser/?view=$SITE" >>"$LOG" 2>&1

sleep 15
log "activeApp=$($LIPCG com.lab126.appmgrd activeApp 2>&1)"
fbdump "B1_after15s"

sleep 12
fbdump "B2_after27s"
log "snapshots done"

# --------------------------------------- power-key test (kiosk config: prevent on)
scr "K7: PRESS POWER NOW"
log "power test window 60s: event0 + powerd + blanket"
( od -An -tu1 -w16 /dev/input/event0 > "$DIAGDIR/event0c.log" 2>&1 ) &
ODPID=$!
( /usr/bin/lipc-wait-event -mt com.lab126.powerd '*' >> "$DIAGDIR/powerd3.log" 2>&1 ) &
LIPCPID=$!
( /usr/bin/lipc-wait-event -mt com.lab126.blanket '*' >> "$DIAGDIR/blanket3.log" 2>&1 ) &
BLPID=$!
sleep 60
kill "$ODPID" "$LIPCPID" "$BLPID" 2>/dev/null
log "event0c lines: $(wc -l < "$DIAGDIR/event0c.log" 2>/dev/null)"
log "powerd3 dump:"; cat "$DIAGDIR/powerd3.log" >> "$LOG" 2>/dev/null
log "blanket3 dump:"; cat "$DIAGDIR/blanket3.log" >> "$LOG" 2>/dev/null
log "power test done"

# ---------------------------------------------------------------- cleanup
$LIPC com.lab126.powerd preventScreenSaver 0 >>"$LOG" 2>&1
killall mesquite >>"$LOG" 2>&1
sleep 1
$LIPC com.lab126.appmgrd start "app://com.lab126.booklet.home" >>"$LOG" 2>&1
log "cleanup done, back to library"
scr "K7 test3 done"
exit 0
