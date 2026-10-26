#!/bin/sh
# k7kiosk.sh - permanent dashboard kiosk for Kindle 7 (firmware 5.12.2.2)
#
# Runs as root (via bridge.conf emergency hook on every boot).
# - repairs the privilege-escalation chain (gandalf)
# - keeps the browser config in fullscreen mode
# - launches the local HZBoard.html
# - blocks the screen saver / lock permanently (preventScreenSaver 1)
# - supervises the browser: if mesquite dies, relaunch it
# - exit backdoor: create an empty file /mnt/us/k7.stop -> next loop
#   iteration closes the board and returns to the library

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG=/mnt/us/k7.log
LIPC=/usr/bin/lipc-set-prop
LIPCG=/usr/bin/lipc-get-prop
EIPS=/usr/sbin/eips
CFG=/var/local/mesquite/browser/config.xml
SITE="file:///mnt/us/documents/HZBoard.html"
STOPFILE=/mnt/us/k7.stop

log() { echo "$(date '+%m-%d %H:%M:%S') [kiosk] $*" >> "$LOG"; }
scr() { "$EIPS" 0 0 "$*" >/dev/null 2>&1; log "screen: $*"; }

log "=== kiosk start $(date) ==="

# ------------------------------------------------ 1. privilege chain repair
mount -o rw,remount / 2>/dev/null
if [ -x /var/local/mkk/gandalf ]; then
    log "gandalf: ok"
else
    mkdir -p /var/local/mkk
    if cp /mnt/us/mkk/gandalf /var/local/mkk/gandalf 2>>"$LOG"; then
        chown root:root /var/local/mkk/gandalf 2>/dev/null
        chmod 0755 /var/local/mkk/gandalf
        log "gandalf: restored"
    else
        log "gandalf: restore FAILED"
    fi
fi

# ------------------------------------------------ 2. browser config patch
if [ -f "$CFG" ]; then
    sed -i 's/viewmodes="application"/viewmodes="fullscreen"/' "$CFG" 2>>"$LOG"
    sed -i 's/pinchzoom" value="yes"/pinchzoom" value="no"/' "$CFG" 2>>"$LOG"
    log "config viewmodes: $(grep -o 'viewmodes="[^"]*"' "$CFG" 2>/dev/null)"
fi

# ------------------------------------------------ 3. launch the board
scr "K7: board starting"
$LIPC com.lab126.powerd preventScreenSaver 1 >>"$LOG" 2>&1
killall mesquite >>"$LOG" 2>&1
sleep 1
$LIPC com.lab126.appmgrd start "app://com.lab126.browser/?view=$SITE" >>"$LOG" 2>&1
sleep 3
$LIPC com.lab126.pillow dismissChrome "" >>"$LOG" 2>&1
log "board launched, activeApp=$($LIPCG com.lab126.appmgrd activeApp 2>&1)"

# ------------------------------------------------ 4. supervise forever
scr "K7: board live"
while true; do
    # keep the screen awake (other apps may reset the flag)
    $LIPC com.lab126.powerd preventScreenSaver 1 >>"$LOG" 2>&1

    # graceful exit backdoor
    if [ -f "$STOPFILE" ]; then
        log "stop file detected - exiting kiosk"
        rm -f "$STOPFILE"
        $LIPC com.lab126.powerd preventScreenSaver 0 >>"$LOG" 2>&1
        killall mesquite >>"$LOG" 2>&1
        sleep 1
        $LIPC com.lab126.appmgrd start "app://com.lab126.booklet.home" >>"$LOG" 2>&1
        scr "K7: kiosk stopped"
        log "=== kiosk stopped ==="
        exit 0
    fi

    # browser died? bring it back
    if ! pidof mesquite >/dev/null 2>&1; then
        log "browser gone - relaunching"
        killall mesquite >>"$LOG" 2>&1
        sleep 1
        $LIPC com.lab126.appmgrd start "app://com.lab126.browser/?view=$SITE" >>"$LOG" 2>&1
        sleep 3
        $LIPC com.lab126.pillow dismissChrome "" >>"$LOG" 2>&1
        $LIPC com.lab126.powerd preventScreenSaver 1 >>"$LOG" 2>&1
        log "browser relaunched, activeApp=$($LIPCG com.lab126.appmgrd activeApp 2>&1)"
    fi

    sleep 15
done
