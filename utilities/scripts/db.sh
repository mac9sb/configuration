#!/bin/sh
# =============================================================================
#  SQLite State Database — shared helper library
#
#  Provides a single transactional store for all runtime state, replacing
#  flat files (port-assignments, sites-state, pids/, restart-request, etc.)
#
#  Schema:
#    sites         — discovered sites with classification and port assignment
#    servers       — running server process state (PID, mtime, start time)
#    config        — key-value store for global state (e.g. manager PID)
#    restart_queue — pending restart requests (written by restart-server.sh)
#
#  Usage:
#    . "$HOME/Developer/utilities/scripts/db.sh"
#    db_init
#    db_get_port "my-site"
#
#  All functions use WAL mode for safe concurrent access from multiple
#  processes (server-manager, sites-watcher, restart-server.sh).
#
#  Requires: /usr/bin/sqlite3 (ships with macOS)
# =============================================================================

DB_DIR="${DB_DIR:-$HOME/Library/Application Support/com.mac9sb}"
DB_PATH="${DB_PATH:-$DB_DIR/state.db}"

# ── Low-level helpers ────────────────────────────────────────────────────────

# Execute a write statement (INSERT, UPDATE, DELETE, CREATE, etc.)
# Usage: db_exec "SQL statement" [args...]
db_exec() {
    sqlite3 "$DB_PATH" "$1"
}

# Execute a read query and return results (one value per line by default).
# Usage: db_query "SELECT ..."
db_query() {
    sqlite3 "$DB_PATH" "$1"
}

# Execute a read query with pipe-separated columns.
# Usage: db_query_separated "SELECT col1, col2 ..."
db_query_separated() {
    sqlite3 -separator '|' "$DB_PATH" "$1"
}

# ── Initialisation ───────────────────────────────────────────────────────────

# Initialise the database: create tables if they don't exist, enable WAL.
# Safe to call multiple times (all statements are IF NOT EXISTS).
db_init() {
    mkdir -p "$DB_DIR"

    sqlite3 "$DB_PATH" <<'SQL'
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS sites (
    name       TEXT PRIMARY KEY,
    type       TEXT NOT NULL CHECK(type IN ('static', 'server')),
    port       INTEGER,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS servers (
    name         TEXT PRIMARY KEY,
    pid          INTEGER NOT NULL,
    binary_mtime INTEGER,
    started_at   INTEGER NOT NULL,
    FOREIGN KEY (name) REFERENCES sites(name) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS config (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS restart_queue (
    name         TEXT PRIMARY KEY,
    requested_at TEXT NOT NULL DEFAULT (datetime('now'))
);
SQL
}

# ── Sites ────────────────────────────────────────────────────────────────────

# Upsert a site record with its classification type.
# Port is assigned automatically for server-type sites.
# Usage: db_set_site "repo-name" "static|server"
db_set_site() {
    _name="$1"
    _type="$2"

    if [ "$_type" = "server" ]; then
        # Assign a port if one doesn't exist yet
        _port="$(db_get_port "$_name")"
        db_exec "INSERT INTO sites (name, type, port, updated_at)
                 VALUES ('$_name', '$_type', $_port, datetime('now'))
                 ON CONFLICT(name) DO UPDATE SET
                   type = '$_type',
                   port = $_port,
                   updated_at = datetime('now');"
    else
        db_exec "INSERT INTO sites (name, type, port, updated_at)
                 VALUES ('$_name', '$_type', NULL, datetime('now'))
                 ON CONFLICT(name) DO UPDATE SET
                   type = '$_type',
                   port = NULL,
                   updated_at = datetime('now');"
    fi
}

# Remove a site record (cascades to servers table).
# Usage: db_remove_site "repo-name"
db_remove_site() {
    db_exec "DELETE FROM sites WHERE name = '$1';"
}

# Remove all sites not in the provided space-separated list.
# Usage: db_prune_sites "site1 site2 site3"
db_prune_sites() {
    _keep_list="$1"

    if [ -z "$_keep_list" ]; then
        db_exec "DELETE FROM sites;"
        return
    fi

    # Build an IN clause: ('site1','site2','site3')
    _in=""
    for _s in $_keep_list; do
        [ -n "$_in" ] && _in="${_in},"
        _in="${_in}'${_s}'"
    done

    db_exec "DELETE FROM sites WHERE name NOT IN (${_in});"
}

# Get a sorted state snapshot string for comparison.
# Returns lines like "repo:type" sorted by name — same format as the
# old sites-state flat file.
# Usage: _state="$(db_get_sites_state)"
db_get_sites_state() {
    db_query "SELECT name || ':' || type FROM sites ORDER BY name;"
}

# Get a site's type.
# Usage: _type="$(db_get_site_type "repo-name")"
db_get_site_type() {
    db_query "SELECT type FROM sites WHERE name = '$1';"
}

# List all sites of a given type (one name per line).
# Usage: db_list_sites_by_type "server"
db_list_sites_by_type() {
    db_query "SELECT name FROM sites WHERE type = '$1' ORDER BY name;"
}

# ── Port assignment ──────────────────────────────────────────────────────────

SERVER_PORT_START="${SERVER_PORT_START:-8000}"

# Get or assign a stable port for a server site.
# If the site already has a port, return it. Otherwise, find the next
# available port and assign it atomically.
# Usage: _port="$(db_get_port "repo-name")"
db_get_port() {
    _name="$1"

    # Check for existing assignment
    _existing="$(db_query "SELECT port FROM sites WHERE name = '$_name' AND port IS NOT NULL;")"
    if [ -n "$_existing" ]; then
        printf '%s' "$_existing"
        return
    fi

    # Find the next available port (max existing + 1, or SERVER_PORT_START)
    _max="$(db_query "SELECT COALESCE(MAX(port), $(($SERVER_PORT_START - 1))) FROM sites WHERE port IS NOT NULL;")"
    _next_port=$((_max + 1))

    # Reserve it immediately (upsert the port on the sites row)
    db_exec "INSERT INTO sites (name, type, port, updated_at)
             VALUES ('$_name', 'server', $_next_port, datetime('now'))
             ON CONFLICT(name) DO UPDATE SET
               port = $_next_port,
               updated_at = datetime('now');"

    printf '%s' "$_next_port"
}

# Get the port for a site without assigning one.
# Returns empty string if no port is assigned.
# Usage: _port="$(db_get_port_if_exists "repo-name")"
db_get_port_if_exists() {
    db_query "SELECT port FROM sites WHERE name = '$1' AND port IS NOT NULL;"
}

# ── Server process tracking ─────────────────────────────────────────────────

# Record that a server process has been started.
# Usage: db_save_server "repo-name" PID BINARY_MTIME
db_save_server() {
    _name="$1"
    _pid="$2"
    _mtime="$3"
    _now="$(date +%s)"

    db_exec "INSERT INTO servers (name, pid, binary_mtime, started_at)
             VALUES ('$_name', $_pid, $_mtime, $_now)
             ON CONFLICT(name) DO UPDATE SET
               pid = $_pid,
               binary_mtime = $_mtime,
               started_at = $_now;"
}

# Remove a server process record.
# Usage: db_remove_server "repo-name"
db_remove_server() {
    db_exec "DELETE FROM servers WHERE name = '$1';"
}

# Get the PID of a running server.
# Usage: _pid="$(db_get_server_pid "repo-name")"
db_get_server_pid() {
    db_query "SELECT pid FROM servers WHERE name = '$1';"
}

# Get the stored binary mtime for a server.
# Usage: _mtime="$(db_get_server_mtime "repo-name")"
db_get_server_mtime() {
    db_query "SELECT binary_mtime FROM servers WHERE name = '$1';"
}

# Get the start timestamp for a server.
# Usage: _started="$(db_get_server_started "repo-name")"
db_get_server_started() {
    db_query "SELECT started_at FROM servers WHERE name = '$1';"
}

# List all tracked server names (one per line).
# Usage: db_list_tracked_servers
db_list_tracked_servers() {
    db_query "SELECT name FROM servers ORDER BY name;"
}

# Get full server info: name|pid|binary_mtime|started_at
# Usage: db_get_server_info "repo-name"
db_get_server_info() {
    db_query_separated "SELECT name, pid, binary_mtime, started_at FROM servers WHERE name = '$1';"
}

# ── Config (key-value) ───────────────────────────────────────────────────────

# Set a config value.
# Usage: db_set_config "manager_pid" "12345"
db_set_config() {
    db_exec "INSERT INTO config (key, value)
             VALUES ('$1', '$2')
             ON CONFLICT(key) DO UPDATE SET value = '$2';"
}

# Get a config value (empty string if not set).
# Usage: _val="$(db_get_config "manager_pid")"
db_get_config() {
    db_query "SELECT value FROM config WHERE key = '$1';"
}

# Remove a config key.
# Usage: db_remove_config "manager_pid"
db_remove_config() {
    db_exec "DELETE FROM config WHERE key = '$1';"
}

# ── Restart queue ────────────────────────────────────────────────────────────

# Queue a restart request for a server.
# Usage: db_queue_restart "repo-name"
db_queue_restart() {
    db_exec "INSERT INTO restart_queue (name, requested_at)
             VALUES ('$1', datetime('now'))
             ON CONFLICT(name) DO UPDATE SET requested_at = datetime('now');"
}

# Pop the next restart request (returns the name and removes it).
# Usage: _name="$(db_pop_restart)"
db_pop_restart() {
    _name="$(db_query "SELECT name FROM restart_queue ORDER BY requested_at LIMIT 1;")"
    if [ -n "$_name" ]; then
        db_exec "DELETE FROM restart_queue WHERE name = '$_name';"
        printf '%s' "$_name"
    fi
}

# Pop all pending restart requests (one name per line).
# Usage: db_pop_all_restarts
db_pop_all_restarts() {
    _names="$(db_query "SELECT name FROM restart_queue ORDER BY requested_at;")"
    if [ -n "$_names" ]; then
        db_exec "DELETE FROM restart_queue;"
        printf '%s\n' "$_names"
    fi
}

# Check if any restart requests are pending.
# Usage: if db_has_pending_restarts; then ...
db_has_pending_restarts() {
    _count="$(db_query "SELECT COUNT(*) FROM restart_queue;")"
    [ "$_count" -gt 0 ] 2>/dev/null
}

# ── Migration helpers ────────────────────────────────────────────────────────

# Import port assignments from the legacy flat file.
# Reads lines like "repo=port" and inserts them into the sites table.
# Usage: db_import_port_assignments "/path/to/port-assignments"
db_import_port_assignments() {
    _file="$1"
    [ ! -f "$_file" ] && return 0

    while IFS='=' read -r _repo _port; do
        [ -z "$_repo" ] && continue
        [ -z "$_port" ] && continue
        db_exec "INSERT INTO sites (name, type, port, updated_at)
                 VALUES ('$_repo', 'server', $_port, datetime('now'))
                 ON CONFLICT(name) DO UPDATE SET
                   port = $_port,
                   updated_at = datetime('now');"
    done < "$_file"
}

# Import sites state from the legacy flat file.
# Reads lines like "repo:type" and inserts them into the sites table.
# Usage: db_import_sites_state "/path/to/sites-state"
db_import_sites_state() {
    _file="$1"
    [ ! -f "$_file" ] && return 0

    while IFS=: read -r _repo _type; do
        [ -z "$_repo" ] && continue
        [ -z "$_type" ] && continue
        db_exec "INSERT INTO sites (name, type, updated_at)
                 VALUES ('$_repo', '$_type', datetime('now'))
                 ON CONFLICT(name) DO UPDATE SET
                   type = '$_type',
                   updated_at = datetime('now');"
    done < "$_file"
}
