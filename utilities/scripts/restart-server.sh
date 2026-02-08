#!/bin/sh
# Restart a launchd-managed server after its binary is rebuilt.
# Usage: restart-server.sh <launchd-label>
#
# Called by per-site watcher plists via WatchPaths. The label is passed
# as the first argument so this single script handles every server.

LABEL="$1"
[ -z "$LABEL" ] && exit 1

UID_NUM="$(id -u)"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

# Brief delay to ensure the binary write is fully flushed to disk
sleep 1

# kickstart -k kills the running instance and restarts it in one shot.
# Fall back to bootout/bootstrap if kickstart is unavailable.
launchctl kickstart -k "gui/${UID_NUM}/${LABEL}" 2>/dev/null || {
    launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
    [ -f "$PLIST" ] && launchctl bootstrap "gui/${UID_NUM}" "$PLIST" 2>/dev/null || true
}
