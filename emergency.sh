#!/bin/sh
# emergency.sh - boot-time repair hook (runs as root before everything else)
#
# This file is executed by the jailbreak's bridge.conf upstart job on every
# boot. It repairs the ;log command channel if it broke, then hands over to
# the k7fix diagnostic run. One-shot: deletes itself when done.

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

LOG=/mnt/us/k7.log
log() { echo "$(date '+%m-%d %H:%M:%S') [emergency] $*" >> "$LOG"; }

# ---------------------------------------------------------- repair the hook
log "=== emergency repair start ==="

G=/usr/bin/gandalf
if [ -x "$G" ]; then
    log "gandalf ok (setuid root)"
else
    log "gandalf missing"
fi

# logThis.sh - the ;log command processor
if [ -f /usr/bin/logThis.sh ]; then
    log "logThis.sh already in place"
else
    cp /mnt/us/extensions/MRInstaller/bin/logThis.sh /usr/bin/logThis.sh 2>>"$LOG" \
        && log "logThis.sh restored from USB backup" \
        || log "logThis.sh restore failed"
fi

# debug_cmds.json - the ; command registry
if grep -q 'logThis' /usr/share/webkit-1.0/pillow/debug_cmds.json 2>/dev/null; then
    log "debug_cmds.json already hooked"
else
    cp /mnt/us/extensions/MRInstaller/debug_cmds.json /usr/share/webkit-1.0/pillow/debug_cmds.json 2>>"$LOG" \
        && log "debug_cmds.json restored from USB backup" \
        || log "debug_cmds.json restore failed"
fi

# debugging flag file required by 5.12 firmware
if [ -f /var/local/mesquite/browser/debug ]; then
    log "debugging flag already present"
else
    touch /var/local/mesquite/browser/debug 2>>"$LOG" \
        && log "debugging flag restored" \
        || log "debugging flag restore failed"
fi

log "verify: logThis=$( [ -f /usr/bin/logThis.sh ] && echo ok || echo MISSING ) hook=$( grep -q logThis /usr/share/webkit-1.0/pillow/debug_cmds.json 2>/dev/null && echo ok || echo MISSING ) flag=$( [ -f /var/local/mesquite/browser/debug ] && echo ok || echo MISSING )"
log "=== emergency repair done ==="

# ------------------------------------------------- run the k7fix diagnostic
if [ -f /mnt/us/k7fix.sh ]; then
    if command -v setsid >/dev/null 2>&1; then
        setsid /bin/sh -c 'sleep 5; exec /bin/sh /mnt/us/k7fix.sh' >> "$LOG" 2>&1 &
    else
        ( sleep 5; /bin/sh /mnt/us/k7fix.sh ) >> "$LOG" 2>&1 &
    fi
fi

# one-shot: remove ourselves so normal boots stay clean
rm -f /mnt/us/emergency.sh
log "emergency.sh removed (one-shot)"
exit 0
