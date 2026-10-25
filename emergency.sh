#!/bin/sh
# k7 emergency repair
# Runs at boot as root via the jailbreak bridge upstart job
# (/etc/upstart/bridge.conf executes /mnt/us/emergency.sh before anything else).
# One-shot: repairs the ";log" debug command hook, then launches the board.

LOG=/mnt/us/k7.log
say() { echo "$(date '+%m-%d %H:%M:%S') [emergency] $*" >> "$LOG" 2>/dev/null; }

say "=== emergency repair start ==="

MKK=/var/local/mkk
DCJ=/usr/share/webkit-1.0/pillow/debug_cmds.json
FLAG=/PRE_GM_DEBUGGING_FEATURES_ENABLED__REMOVE_AT_GMC

# ---- 0. make sure /var/local/mkk exists (restore from USB backup if wiped)
if [ ! -f "$MKK/dispatch.sh" ] && [ -f /mnt/us/mkk/dispatch.sh ] ; then
    mkdir -p "$MKK" 2>/dev/null
    chattr -R -i "$MKK" 2>/dev/null
    cp -af /mnt/us/mkk/. "$MKK"/. 2>>"$LOG"
    chown -R root:root "$MKK" 2>/dev/null
    say "restored /var/local/mkk from USB backup"
fi

# ---- 0b. gandalf must stay setuid root (the framework stomps permissions)
if [ -f "$MKK/gandalf" ] ; then
    chattr -i "$MKK/gandalf" 2>/dev/null
    chown root:root "$MKK/gandalf" 2>/dev/null
    chmod a+rx "$MKK/gandalf" 2>/dev/null
    chmod +s "$MKK/gandalf" 2>/dev/null
    chattr +i "$MKK/gandalf" 2>/dev/null
    if [ ! -L "$MKK/su" ] ; then
        chattr -i "$MKK" 2>/dev/null
        ln -sf "$MKK/gandalf" "$MKK/su" 2>/dev/null
        chattr +i "$MKK" 2>/dev/null
    fi
    if [ -u "$MKK/gandalf" ] ; then
        say "gandalf ok (setuid root)"
    else
        say "WARNING: gandalf setuid bit not set"
    fi
fi

# ---- 1. /usr/bin/logThis.sh  (the ;log command handler)
DISPATCH_SRC="$MKK/dispatch.sh"
[ -f "$DISPATCH_SRC" ] || DISPATCH_SRC=/mnt/us/mkk/dispatch.sh
if [ -f "$DISPATCH_SRC" ] ; then
    if [ ! -f /usr/bin/logThis.sh ] || ! grep -q "Dispatch" /usr/bin/logThis.sh 2>/dev/null ; then
        chattr -i /usr/bin/logThis.sh 2>/dev/null
        rm -f /usr/bin/logThis.sh
        cp -f "$DISPATCH_SRC" /usr/bin/logThis.sh 2>>"$LOG"
        chmod 0755 /usr/bin/logThis.sh
        chattr +i /usr/bin/logThis.sh 2>/dev/null
        say "installed /usr/bin/logThis.sh"
    else
        say "logThis.sh already in place"
    fi
else
    say "WARNING: no dispatch.sh source found"
fi

# ---- 2. pillow debug_cmds.json hook (maps ;log to logThis.sh)
if [ -f "$DCJ" ] ; then
    if ! grep -q "logThis.sh" "$DCJ" ; then
        chattr -i "$DCJ" 2>/dev/null
        sed -e '/^{/a\' -e '    ";log" : "/usr/bin/logThis.sh",' -i "$DCJ" 2>>"$LOG"
        chattr +i "$DCJ" 2>/dev/null
        say "patched debug_cmds.json"
    else
        say "debug_cmds.json already hooked"
    fi
else
    say "WARNING: $DCJ not found"
fi

# ---- 3. FW 5.12+ debugging flag (re-enables the ; command system)
if [ ! -f "$FLAG" ] ; then
    chattr -i "$FLAG" 2>/dev/null
    touch "$FLAG"
    chattr +i "$FLAG" 2>/dev/null
    say "created debugging flag file"
else
    say "debugging flag already present"
fi

# ---- 4. bridge job must stay on disk for future boots
if [ ! -f /etc/upstart/bridge.conf ] && [ -f "$MKK/bridge.conf" ] ; then
    chattr -i /etc/upstart/bridge.conf 2>/dev/null
    cp -f "$MKK/bridge.conf" /etc/upstart/bridge.conf 2>>"$LOG"
    chmod 0664 /etc/upstart/bridge.conf
    chattr +i /etc/upstart/bridge.conf 2>/dev/null
    say "restored /etc/upstart/bridge.conf"
fi

# ---- verify and log the final state
say "verify: logThis=$( [ -f /usr/bin/logThis.sh ] && echo ok || echo MISSING ) hook=$( grep -q logThis.sh "$DCJ" 2>/dev/null && echo ok || echo MISSING ) flag=$( [ -f "$FLAG" ] && echo ok || echo MISSING )"
say "=== emergency repair done ==="

/usr/bin/eips 1 0 "K7 REPAIR OK" >/dev/null 2>&1

# ---- launch diag (this boot) or the board, in the background
if command -v setsid >/dev/null 2>&1; then
    setsid /bin/sh -c 'sleep 8; if [ -f /mnt/us/k7diag.sh ]; then exec /bin/sh /mnt/us/k7diag.sh; else exec /bin/sh /mnt/us/RUNME.sh; fi' >> "$LOG" 2>&1 &
else
    ( sleep 8; if [ -f /mnt/us/k7diag.sh ]; then /bin/sh /mnt/us/k7diag.sh; else /bin/sh /mnt/us/RUNME.sh; fi ) >> "$LOG" 2>&1 &
fi

# ---- one-shot: get out of the way so future boots run the normal bridge
mv -f /mnt/us/emergency.sh /mnt/us/emergency.sh.done 2>/dev/null

exit 0
