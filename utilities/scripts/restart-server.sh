#!/bin/sh
# =============================================================================
#  Restart a server managed by server-manager.sh
#
#  Usage: restart-server.sh <server-name>
#
#  Writes the server name to the restart_queue table in the shared SQLite
#  database and sends SIGUSR1 to the server-manager process, which picks
#  up the request and restarts just that one child.
#
#  State DB: ~/Library/Application Support/com.mac9sb/state.db
# =============================================================================

SERVER_NAME="$1"
[ -z "$SERVER_NAME" ] && { echo "Usage: restart-server.sh <server-name>" >&2; exit 1; }
case "$SERVER_NAME" in
    *[!A-Za-z0-9._-]*|'')
        echo "Invalid server name: $SERVER_NAME" >&2
        exit 1
        ;;
esac

# Source the shared SQLite helpers
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPTS_DIR/db.sh"

# Initialise DB (no-op if already exists)
db_init

# Queue the restart request atomically
db_queue_restart "$SERVER_NAME"

# Signal the server-manager to process the queue
_pid="$(db_get_config "manager_pid")"

if [ -z "$_pid" ]; then
    echo "Server manager PID not found in database" >&2
    exit 1
fi

if kill -0 "$_pid" 2>/dev/null; then
    kill -USR1 "$_pid"
else
    echo "Server manager (PID $_pid) is not running" >&2
    exit 1
fi
