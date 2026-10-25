#!/bin/sh
# k7fix2.sh - round 2: register the browser as a fullscreen (no-chrome) app
#
# Round 1 proved:
#   - exit channel works: no preventScreenSaver + goingToScreenSaver (verified)
#   - dismissChrome / disableEnablePillow both return exit=0 but effect unknown
#   - appreg.db has NO viewModes property on 5.12.2.2
#   - the real fullscreen switch is: default-chrome-style=NH + searchbar-mode=transient
#     (proven recipe from KindleModding/sh_integration + com.lab126.booklet.reader)
#   - the fb snapshot path had a typo ($_DIAGDIR) - fixed here
#
# This run:
#   1. fresh appreg.db backup
#   2. insert default-chrome-style=NH + searchbar-mode=transient for com.lab126.browser
#   3. restart the framework (lab126_gui) so the registry is re-read from disk
#   4. launch the board, snapshot the framebuffer
#   5. power-key exit-channel test WITH preventScreenSaver on (real kiosk config)

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG=/mnt/us/k7.log
LIPC=/usr/bin/lipc-set-prop
LIPCG=/usr/bin/lipc-get-prop
EIPS=/usr/sbin/eips
DB=/var/local/appreg.db
DIAGDIR=/mnt/us/documents/k7diag
SITE="file:///mnt/us/documents/HZBoard.html"
SQL=/usr/bin/sqlite3

log() { echo "$(date '+%m-%d %H:%M:%S') [fix2] $*" >> "$LOG"; }
scr() { "$EIPS" 0 0 "$*" >/dev/null 2>&1; log "screen: $*"; }

mkdir -p "$DIAGDIR" 2>/dev/null

fbdump() {
    _name="$1"
    _vs=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)
    _bpp=$(cat /sys/class/graphics/fb0/bits_per_pixel 2>/dev/null)
    _w=$(echo "$_vs" | cut -d, -f1); _h=$(echo "$_vs" | cut -d, -f2)
    [ -z "$_w" ] && _w=608
    [ -z "$_h" ] && _h=5376
    [ -z "$_bpp" ] && _bpp=8
    _bytes=$(( (_w * _h * _bpp) / 8 ))
    _cnt=$(( (_bytes + 4095) / 4096 ))
    dd if=/dev/fb0 of="$DIAGDIR/fb_$_name.raw" bs=4096 count=$_cnt 2>>"$LOG"
    log "fbdump $_name: ${_w}x${_h} bpp=$_bpp want=$_bytes got=$(wc -c < "$DIAGDIR/fb_$_name.raw" 2>/dev/null)"
}

launch() {
    killall mesquite >>"$LOG" 2>&1
    sleep 1
    $LIPC com.lab126.appmgrd start "app://com.lab126.browser/?view=$1" >>"$LOG" 2>&1
}

{
    echo ""
    echo "===== k7fix2 $(date) ====="
    echo "-- backup --"
    cp "$DB" "$DIAGDIR/appreg.db.bak2" 2>&1 && echo "backup2 ok"
    echo "-- browser props BEFORE patch --"
    $SQL "$DB" "select name, value from properties where handlerId='com.lab126.browser' order by name;" 2>&1
    echo "-- reference (reader) props --"
    $SQL "$DB" "select name, value from properties where handlerId='com.lab126.booklet.reader' order by name;" 2>&1
} >> "$LOG" 2>&1

# ------------------------------------------------------- patch appreg.db
log "inserting default-chrome-style=NH + searchbar-mode=transient"
$SQL "$DB" "insert or replace into properties (handlerId, name, value) values ('com.lab126.browser', 'default-chrome-style', 'NH');" >>"$LOG" 2>&1
$SQL "$DB" "insert or replace into properties (handlerId, name, value) values ('com.lab126.browser', 'searchbar-mode', 'transient');" >>"$LOG" 2>&1
log "browser props AFTER patch:"
$SQL "$DB" "select name, value from properties where handlerId='com.lab126.browser' order by name;" >>"$LOG" 2>&1

# ------------------------------------------- restart framework to re-read db
scr "K7: restarting UI"
log "stopping lab126_gui"
stop lab126_gui >>"$LOG" 2>&1
sleep 4
log "starting lab126_gui"
start lab126_gui >>"$LOG" 2>&1
sleep 15
scr "K7: UI back, launching"

# ------------------------------------------------------------ launch board
$LIPC com.lab126.powerd preventScreenSaver 1 >>"$LOG" 2>&1
log "preventScreenSaver=1 exit=$?"
launch "$SITE"
sleep 9
log "activeApp=$($LIPCG com.lab126.appmgrd activeApp 2>&1)"
fbdump "A_chromeNH"
log "framebuffer snapshot A taken"

# --------------------------------------- power-key test (kiosk config: prevent on)
scr "K7: press POWER once"
log "power test: event0 od 60s + powerd lipc sniff 60s + blanket sniff 60s"
( od -An -tu1 -w16 /dev/input/event0 > "$DIAGDIR/event0b.log" 2>&1 ) &
ODPID=$!
( /usr/bin/lipc-wait-event -mt com.lab126.powerd '*' >> "$LOG" 2>&1 ) &
LIPCPID=$!
( /usr/bin/lipc-wait-event -mt com.lab126.blanket '*' >> "$DIAGDIR/blanket.log" 2>&1 ) &
BLPID=$!
sleep 60
kill "$ODPID" "$LIPCPID" "$BLPID" 2>/dev/null
log "event0 lines: $(wc -l < "$DIAGDIR/event0b.log" 2>/dev/null)"
log "event0 dump:"; cat "$DIAGDIR/event0b.log" >> "$LOG" 2>/dev/null
log "blanket dump:"; cat "$DIAGDIR/blanket.log" >> "$LOG" 2>/dev/null
log "power test done"

# ---------------------------------------------------------------- cleanup
$LIPC com.lab126.powerd preventScreenSaver 0 >>"$LOG" 2>&1
killall mesquite >>"$LOG" 2>&1
sleep 1
$LIPC com.lab126.appmgrd start "app://com.lab126.booklet.home" >>"$LOG" 2>&1
log "cleanup done, back to library"
scr "K7 test done"
exit 0
