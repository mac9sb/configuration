#!/bin/sh
# =============================================================================
#  Cloudflared Launcher — waits for tunnel setup then runs the tunnel
#
#  On a fresh machine, cloudflared won't have credentials yet. This script
#  polls ~/.cloudflared/ until the tunnel credential JSON file exists,
#  then exec's into `cloudflared tunnel run`.
#
#  Once credentials are in place (after initial `cloudflared tunnel create`),
#  subsequent launches skip the wait and start immediately.
#
#  Managed by launchd via com.mac9sb.cloudflared (KeepAlive = true):
#    - First boot:  polls until credentials appear, then starts tunnel
#    - Crash/exit:  launchd restarts this script, credentials exist → instant
#
#  Logs: ~/Library/Logs/com.mac9sb/cloudflared-launcher.log
# =============================================================================

set -e

CRED_DIR="$HOME/.cloudflared"
CONFIG="$CRED_DIR/config.yml"
LOG_DIR="$HOME/Library/Logs/com.mac9sb"
LOG_FILE="$LOG_DIR/cloudflared-launcher.log"
POLL_INTERVAL=10

mkdir -p "$LOG_DIR"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

# ---------------------------------------------------------------------------
#  Wait for tunnel credentials
# ---------------------------------------------------------------------------

_has_credentials() {
    # Need the tunnel credential JSON file
    [ -f "$CRED_DIR/maclong.json" ] || return 1
    return 0
}

if ! _has_credentials; then
    log "Tunnel credentials not found — waiting for setup..."
    log "  Watching: $CRED_DIR for maclong.json"
    log "  To set up: cloudflared tunnel login && cloudflared tunnel create --credentials-file $CRED_DIR/maclong.json maclong"

    while ! _has_credentials; do
        sleep "$POLL_INTERVAL"
    done

    log "Credentials detected — starting tunnel"
fi

# ---------------------------------------------------------------------------
#  Hand off to cloudflared (replaces this process)
# ---------------------------------------------------------------------------

log "Launching: cloudflared tunnel run --credentials-file $CRED_DIR/maclong.json maclong"
exec /usr/local/bin/cloudflared tunnel run --credentials-file "$CRED_DIR/maclong.json" maclong
