#!/bin/sh
# k7diag - diagnostics for the fullscreen chrome problem (KT2 / 5.12.2.2)
#
# Runs at boot via /mnt/us/emergency.sh. Does NOT change anything on the
# device except copying browser source files to documents/k7diag/ for
# offline analysis, launching the browser once, and logging raw power
# button events.
#
# What it answers:
#   1. Which process draws the browser chrome? (process dump with browser up)
#   2. Do power button events reach userspace on KT2? (raw od sniffers)
#   3. What does the mesquite browser source actually do? (file copy)

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG=/mnt/us/k7.log
LIPC=/usr/bin/lipc-set-prop
LIPCG=/usr/bin/lipc-get-prop
EIPS=/usr/sbin/eips
CFG=/var/local/mesquite/browser/config.xml
BDIR=/var/local/mesquite/browser
DIAGDIR=/mnt/us/documents/k7diag

log() { echo "$(date '+%m-%d %H:%M:%S') [diag] $*" >> "$LOG"; }

# ------------------------------------------------------------------ phase 1
{
    echo ""
    echo "===== k7diag $(date) ====="
    echo "-- id / uname --"
    id
    echo "-- input devices (name + key capability bitmap) --"
    for d in /dev/input/event*; do
        [ -e "$d" ] || continue
        _b=$(basename "$d")
        _n=$(cat "/sys/class/input/$_b/device/name" 2>/dev/null || echo "?")
        _c=$(cat "/sys/class/input/$_b/device/capabilities/key" 2>/dev/null || echo "?")
        echo "$d name=$_n keycap=$_c"
    done
    echo "-- upstart jobs (full list) --"
    ls /etc/upstart/ 2>&1
    echo "-- lipc props --"
    echo "activeApp=$($LIPCG com.lab126.appmgrd activeApp 2>&1)"
    echo "-- browser-related processes BEFORE launch --"
    for p in /proc/[0-9]*; do
        c=$(cat "$p/comm" 2>/dev/null)
        case "$c" in
            *mesquite*|*chromebar*|*webkit*|*pillow*|*framework*|*lab126*)
                echo "$p $c [$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)]" ;;
        esac
    done
    echo "-- config viewmode on disk --"
    grep -o 'viewmodes="[^"]*"' "$CFG" 2>/dev/null
} >> "$LOG" 2>&1
log "phase1 done (devices, jobs, procs)"

# ------------------------------------------------- copy browser source files
mkdir -p "$DIAGDIR" 2>/dev/null
cp -a "$BDIR/config.xml" "$DIAGDIR/" 2>>"$LOG"
cp -a "$BDIR/index.html" "$DIAGDIR/" 2>>"$LOG"
cp -a "$BDIR/javascripts" "$DIAGDIR/" 2>>"$LOG"
log "browser source copied to documents/k7diag/"
ls -la "$DIAGDIR" >> "$LOG" 2>&1
ls -la "$DIAGDIR/javascripts" >> "$LOG" 2>&1

# ------------------------------------------------------- launch the browser
killall mesquite >> "$LOG" 2>&1
sleep 1
$LIPC com.lab126.appmgrd start "app://com.lab126.browser/?view=file:///mnt/us/documents/HZBoard.html" >> "$LOG" 2>&1
log "browser launched (normal, config patch on disk)"

sleep 8

# ------------------------------------------------------------------ phase 2
{
    echo "-- browser-related processes WITH browser running (chrome visible) --"
    for p in /proc/[0-9]*; do
        c=$(cat "$p/comm" 2>/dev/null)
        case "$c" in
            *mesquite*|*chromebar*|*webkit*|*pillow*|*framework*|*lab126*)
                echo "$p $c [$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)]" ;;
        esac
    done
    echo "-- ALL processes --"
    for p in /proc/[0-9]*; do
        c=$(cat "$p/comm" 2>/dev/null)
        [ -n "$c" ] && echo "$(basename "$p") $c"
    done
    echo "-- lipc props after launch --"
    echo "activeApp=$($LIPCG com.lab126.appmgrd activeApp 2>&1)"
} >> "$LOG" 2>&1
log "phase2 done (process dump with chrome visible)"

# ------------------------------------------------- power button sniffers
# 1) lipc events from powerd (what the framework sees)
( /usr/bin/lipc-wait-event -mt com.lab126.powerd '*' >> "$LOG" 2>&1 ) &
# 2) raw kernel input events from every input device (what userspace can see)
for d in /dev/input/event*; do
    [ -e "$d" ] || continue
    ( od -An -tu1 -w16 "$d" >> "$LOG" 2>&1 ) &
done
log "sniffers started - waiting for power press"

# ------------------------------------------------------------------ wait
sleep 300

# ------------------------------------------------------------------ cleanup
for p in /proc/[0-9]*; do
    c=$(cat "$p/comm" 2>/dev/null)
    case "$c" in
        od|lipc-wait-event) kill "${p#/proc/}" 2>/dev/null ;;
    esac
done
log "diag wait done, sniffers stopped"
exit 0
