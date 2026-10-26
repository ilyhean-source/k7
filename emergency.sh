#!/bin/sh
# emergency.sh - boot-time repair hook (runs as root before everything else)
#
# Executed by the jailbreak's bridge.conf upstart job on every boot.
# Repairs the privilege-escalation chain and the ;log registration,
# then hands over to k7kiosk.sh (permanent fullscreen board).
# NOT one-shot: stays in place so every boot gets the board automatically.

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG=/mnt/us/k7.log
log() { echo "$(date '+%m-%d %H:%M:%S') [emergency] $*" >> "$LOG"; }

log "=== emergency repair start ==="

mount -o rw,remount / 2>/dev/null

# ---- gandalf (setuid helper used by dispatch.sh ;log runme) ----
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

# ---- dispatch.sh (the ;log runme command router) ----
if [ -f /var/local/mkk/dispatch.sh ]; then
    log "dispatch: present"
else
    if cp /mnt/us/mkk/dispatch.sh /var/local/mkk/dispatch.sh 2>>"$LOG"; then
        chmod 0755 /var/local/mkk/dispatch.sh
        log "dispatch: restored"
    else
        log "dispatch: restore FAILED"
    fi
fi

# ---- debug_cmds.json (the ; command registry, idempotent inject) ----
DC=/usr/share/webkit-1.0/pillow/debug_cmds.json
if [ -f "$DC" ]; then
    if grep -q 'logThis' "$DC" 2>/dev/null; then
        log "debug hook: present"
    else
        if sed -e '/^{/a\' -e '    ";log" : "/usr/bin/logThis.sh",' -i "$DC" 2>>"$LOG"; then
            log "debug hook: re-injected"
        else
            log "debug hook: inject FAILED"
        fi
    fi
else
    log "debug_cmds.json: MISSING"
fi

# ---- logThis.sh (the ;log processor) ----
if [ -f /usr/bin/logThis.sh ]; then
    log "logThis: ok"
else
    log "logThis: MISSING (no backup on USB)"
fi

# ---- debug flag required by 5.12 firmware ----
if [ -f /var/local/mesquite/browser/debug ]; then
    log "debug flag: present"
else
    touch /var/local/mesquite/browser/debug 2>/dev/null && log "debug flag: created" || log "debug flag: FAILED"
fi

log "=== repair done, handing to k7kiosk ==="

# run the kiosk in the background; framework needs time to settle
if command -v setsid >/dev/null 2>&1; then
    setsid /bin/sh -c 'sleep 12; exec /bin/sh /mnt/us/k7kiosk.sh' >> "$LOG" 2>&1 &
else
    ( sleep 12; /bin/sh /mnt/us/k7kiosk.sh ) >> "$LOG" 2>&1 &
fi

exit 0
