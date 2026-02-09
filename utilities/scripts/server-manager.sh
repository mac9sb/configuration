#!/bin/sh
# =============================================================================
#  Server Manager — single supervisor for all server binaries
#
#  Scans ~/Developer/sites/ for server binaries
#  (.build/release/<exec> or .build/<triple>/release/<exec>)
#  and manages each as a child process. No config file needed — the server
#  list is inferred from the filesystem, matching the same discovery logic
#  used by sites-watcher.sh and setup.sh.
#
#  All state is stored in a SQLite database (WAL mode) for atomic,
#  concurrent-safe access shared with sites-watcher and restart-server.sh.
#
#  State DB: ~/Library/Application Support/com.mac9sb/state.db
#    - sites table        port assignments shared with sites-watcher
#    - servers table      child process PID, binary mtime, start time
#    - config table       this process's PID (for signal delivery)
#    - restart_queue      IPC table written by restart-server.sh
#
#  Logs: ~/Library/Logs/com.mac9sb/
#    - server-manager.log this process's own log
#    - <site>.log         per-server stdout
#    - <site>.error.log   per-server stderr
#
#  Signals:
#    SIGHUP  — re-scan filesystem immediately (sites-watcher sends this)
#    SIGUSR1 — process pending restart requests from restart_queue table
#    SIGTERM — gracefully stop all servers and exit
#
#  Features:
#    - Adaptive polling: starts at 5s, backs off to 60s when idle, resets
#      on any change (binary rebuild, crash, new/removed server)
#    - HTTP health checks: periodically verifies servers respond to requests,
#      not just that the PID is alive (catches deadlocks/hangs)
#    - Binary isolation: servers run from a copied binary (<exec>.run)
#      so that swift build -c release can overwrite the original without
#      disrupting the running process
#    - Binary rollback: when a rebuild is detected, the currently running
#      binary is backed up (<exec>.bak) before swapping in the new one;
#      if the new binary crashes within ROLLBACK_WINDOW seconds, the backup
#      is restored and a notification is sent
#
#  Called by launchd via com.mac9sb.server-manager.plist (static, symlinked).
# =============================================================================

SITES_DIR="$HOME/Developer/sites"
LOG_DIR="$HOME/Library/Logs/com.mac9sb"
MANAGER_LOG="$LOG_DIR/server-manager.log"

# --- Adaptive polling ---------------------------------------------------------
POLL_MIN=5          # seconds — active polling interval (after changes)
POLL_MAX=60         # seconds — idle polling interval (nothing happening)
POLL_BACKOFF=2      # multiplier — how fast to back off
POLL_IDLE_CYCLES=5  # consecutive idle cycles before increasing interval

# --- Crash throttling ---------------------------------------------------------
THROTTLE_MIN_UPTIME=3   # seconds — if a server runs less than this, throttle restart

# --- Health checks ------------------------------------------------------------
HEALTH_CHECK_INTERVAL=6   # perform health check every N reconcile cycles
HEALTH_CHECK_TIMEOUT=5    # seconds — max time to wait for HTTP response
HEALTH_CHECK_PATH="/"     # path to probe (should return 2xx or 3xx)

# --- Rollback -----------------------------------------------------------------
ROLLBACK_WINDOW=10  # seconds — if new binary crashes within this window, roll back

# Source the shared SQLite helpers
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPTS_DIR/db.sh"

mkdir -p "$LOG_DIR"

# Initialise the database (creates tables if needed, enables WAL)
db_init

# Write our PID to the config table so other scripts can signal us
db_set_config "manager_pid" "$$"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$MANAGER_LOG"; }

# ── Signal flags ─────────────────────────────────────────────────────────────

reload_flag=0
restart_flag=0
shutdown_flag=0

trap 'reload_flag=1'  HUP
trap 'restart_flag=1' USR1
trap 'shutdown_flag=1' TERM INT

# ── Adaptive polling state ───────────────────────────────────────────────────

poll_interval=$POLL_MIN
idle_cycles=0
health_cycle_counter=0

# Reset polling interval to minimum (something changed)
poll_reset() {
    poll_interval=$POLL_MIN
    idle_cycles=0
}

# Increase polling interval if nothing changed
poll_backoff() {
    idle_cycles=$((idle_cycles + 1))
    if [ "$idle_cycles" -ge "$POLL_IDLE_CYCLES" ]; then
        _new=$((poll_interval * POLL_BACKOFF))
        if [ "$_new" -gt "$POLL_MAX" ]; then
            _new=$POLL_MAX
        fi
        if [ "$poll_interval" -ne "$_new" ]; then
            log "Idle — backing off poll interval to ${_new}s"
        fi
        poll_interval=$_new
        idle_cycles=0
    fi
}

# ── Helpers ──────────────────────────────────────────────────────────────────

# Preserve the currently running binary (.run) as a backup (.bak).
# Called BEFORE swapping in a newly built binary, so .bak is genuinely
# the last-known-good version that was actually running and healthy.
# Usage: preserve_binary "name" "/path/to/release/<exec>"
preserve_binary() {
    _name="$1"
    _binary="$2"
    _run_binary="${_binary}.run"
    _backup="${_binary}.bak"

    if [ -f "$_run_binary" ]; then
        cp -f "$_run_binary" "$_backup" 2>/dev/null || true
        log "Preserved running binary as backup for ${_name}"
    fi
}

# Rollback to the last-known-good binary (.bak → .run).
# Returns 0 if rollback succeeded, 1 if no backup exists.
# Usage: rollback_binary "name" "/path/to/release/<exec>"
rollback_binary() {
    _name="$1"
    _binary="$2"
    _run_binary="${_binary}.run"
    _backup="${_binary}.bak"

    if [ -f "$_backup" ]; then
        cp -f "$_backup" "$_run_binary" 2>/dev/null
        chmod +x "$_run_binary" 2>/dev/null || true
        log "ROLLBACK: Restored last-known-good binary for ${_name}"
        osascript -e "display notification \"Rolled back ${_name} to previous binary after crash.\" with title \"Server Rollback\" sound name \"Basso\"" 2>/dev/null || true
        return 0
    else
        log "ROLLBACK: No backup binary available for ${_name}"
        return 1
    fi
}

# Deploy a source binary to the run location (.run) for execution.
# The server always runs from .run so that swift build can overwrite
# the original binary without disrupting the running process.
# Usage: deploy_binary "/path/to/release/<exec>"
deploy_binary() {
    _binary="$1"
    _run_binary="${_binary}.run"

    cp -f "$_binary" "$_run_binary" 2>/dev/null || return 1
    chmod +x "$_run_binary" 2>/dev/null || true
}

# Start a server as a child process.
# Deploys the source binary to .run and launches from there, so that
# swift build can freely overwrite the original without affecting us.
# Records PID, binary mtime, and start time in the database.
start_server() {
    _name="$1"
    _binary="$2"
    _workdir="$3"
    _port="$4"
    _run_binary="${_binary}.run"

    if [ ! -f "$_binary" ] && [ ! -f "$_run_binary" ]; then
        log "ERROR: binary not found for ${_name}: ${_binary}"
        return 1
    fi

    # Deploy source binary to .run (skip if caller already deployed,
    # e.g. after a rollback where .bak was copied to .run directly)
    if [ -f "$_binary" ]; then
        _src_mtime="$(stat -f '%m' "$_binary" 2>/dev/null || echo 0)"
        _run_mtime="$(stat -f '%m' "$_run_binary" 2>/dev/null || echo 0)"
        if [ "$_src_mtime" != "$_run_mtime" ] || [ ! -f "$_run_binary" ]; then
            deploy_binary "$_binary" || {
                log "ERROR: failed to deploy binary for ${_name}"
                return 1
            }
        fi
    fi

    (
        cd "$_workdir" 2>/dev/null || true
        exec env \
            PORT="$_port" \
            PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
            "$_run_binary" --port "$_port"
    ) >> "$LOG_DIR/${_name}.log" 2>> "$LOG_DIR/${_name}.error.log" &

    _pid=$!
    _mtime="$(stat -f '%m' "${_binary}" 2>/dev/null || echo 0)"

    db_save_server "$_name" "$_pid" "$_mtime"

    log "Started ${_name} (PID ${_pid}, port ${_port})"
}

# Stop a server by name.
# Sends SIGTERM, waits up to 5 seconds, then SIGKILL if still alive.
# Removes the server record from the database.
stop_server() {
    _name="$1"
    _pid="$(db_get_server_pid "$_name")"

    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        kill "$_pid" 2>/dev/null || true

        # Wait up to 5 seconds for graceful exit
        _i=0
        while kill -0 "$_pid" 2>/dev/null && [ "$_i" -lt 50 ]; do
            sleep 0.1
            _i=$((_i + 1))
        done

        # Force kill if still alive
        if kill -0 "$_pid" 2>/dev/null; then
            kill -9 "$_pid" 2>/dev/null || true
        fi

        log "Stopped ${_name} (PID ${_pid})"
    fi

    db_remove_server "$_name"
}

# Check if a server's child process is still alive.
is_running() {
    _name="$1"
    _pid="$(db_get_server_pid "$_name")"
    [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null
}

# Check if the source binary has been rebuilt since the server was started.
# Compares the source binary's mtime against the mtime stored when the
# server was last started (which reflects the source binary at deploy time).
binary_changed() {
    _name="$1"
    _binary="$2"

    [ ! -f "$_binary" ] && return 1

    _old="$(db_get_server_mtime "$_name")"
    [ -z "$_old" ] && return 1

    _new="$(stat -f '%m' "$_binary" 2>/dev/null)"

    [ "$_old" != "$_new" ]
}

# Check whether a crashed server should be throttled before restart.
should_throttle() {
    _name="$1"
    _started="$(db_get_server_started "$_name")"

    [ -z "$_started" ] && return 1

    _now="$(date +%s)"
    _uptime=$((_now - _started))

    [ "$_uptime" -lt "$THROTTLE_MIN_UPTIME" ]
}

# Check if a server crashed within the rollback window after a binary update.
# Returns 0 if the crash happened shortly after a rebuild (candidate for rollback).
should_rollback() {
    _name="$1"
    _started="$(db_get_server_started "$_name")"

    [ -z "$_started" ] && return 1

    _now="$(date +%s)"
    _uptime=$((_now - _started))

    # Only rollback if the crash happened very quickly after start
    [ "$_uptime" -lt "$ROLLBACK_WINDOW" ]
}

# Perform an HTTP health check against a running server.
# Returns 0 if the server responds with a 2xx or 3xx status.
# Returns 1 if the server is unresponsive or returns an error.
health_check() {
    _name="$1"
    _port="$2"

    # Use curl with a short timeout; accept any 2xx/3xx response
    _status="$(curl -s -o /dev/null -w '%{http_code}' \
        --max-time "$HEALTH_CHECK_TIMEOUT" \
        --connect-timeout "$HEALTH_CHECK_TIMEOUT" \
        "http://127.0.0.1:${_port}${HEALTH_CHECK_PATH}" 2>/dev/null)" || true

    case "$_status" in
        2*|3*) return 0 ;;
        *)     return 1 ;;
    esac
}

# Stop every managed server.
stop_all() {
    db_list_tracked_servers | while IFS= read -r _name; do
        [ -z "$_name" ] && continue
        stop_server "$_name"
    done
}

# ── Reconcile ────────────────────────────────────────────────────────────────
# Scan ~/Developer/sites/ for server binaries, compare with running children.
# Start missing servers, stop removed ones, restart rebuilt binaries.
# Returns 0 if something changed, 1 if everything is stable.

reconcile() {
    _changed=1   # assume no change (shell: 1 = false)
    _discovered_names=""

    for _dir in "$SITES_DIR"/*/; do
        [ ! -d "$_dir" ] && continue
        _name="$(basename "$_dir")"

        # Skip static sites
        [ -d "$_dir/.output" ] && continue

        # Detect executable name from Package.swift
        _exec_name="$(get_exec_name "$_dir")" || continue
        _binary="$(get_release_binary "$_dir" "$_exec_name")" || continue

        _discovered_names="${_discovered_names} ${_name}"
        _port="$(db_get_port "$_name")"

        if is_running "$_name"; then
            # Running — check for source binary rebuild
            if binary_changed "$_name" "$_binary"; then
                log "Binary rebuilt for ${_name} — backing up running binary and deploying new"
                # 1. Back up the currently running .run as .bak (genuinely last-known-good)
                preserve_binary "$_name" "$_binary"
                # 2. Deploy the new source binary to .run
                deploy_binary "$_binary"
                # 3. Restart the server from the new .run
                stop_server "$_name"
                sleep 1
                start_server "$_name" "$_binary" "$_dir" "$_port"
                _changed=0
            fi
        else
            # Not running — figure out why and how to restart
            _was_tracked="$(db_get_server_pid "$_name")"

            if [ -n "$_was_tracked" ]; then
                # Was running before — it crashed
                if should_rollback "$_name"; then
                    log "CRASH within rollback window for ${_name} — attempting rollback"
                    if rollback_binary "$_name" "$_binary"; then
                        # .bak has been copied to .run — start from .run directly
                        # (start_server will skip deploy since .run is already set)
                        sleep 1
                        start_server "$_name" "$_binary" "$_dir" "$_port"
                        _changed=0
                        continue
                    fi
                fi

                if should_throttle "$_name"; then
                    log "Throttling restart for ${_name} (crashed too quickly)"
                    sleep "$THROTTLE_MIN_UPTIME"
                fi
            fi

            start_server "$_name" "$_binary" "$_dir" "$_port"
            _changed=0
        fi
    done

    # Stop servers whose binaries no longer exist
    db_list_tracked_servers | while IFS= read -r _name; do
        [ -z "$_name" ] && continue
        case "$_discovered_names" in
            *" $_name "*|*" $_name") ;;  # still present
            "$_name "*)              ;;  # still present (first entry)
            "$_name")                ;;  # still present (only entry)
            *)
                log "Server ${_name} no longer detected — stopping"
                stop_server "$_name"
                _changed=0
                ;;
        esac
    done

    return $_changed
}

# ── Health check pass ────────────────────────────────────────────────────────
# Probe each running server via HTTP. If a server is unresponsive, restart it.

run_health_checks() {
    for _dir in "$SITES_DIR"/*/; do
        [ ! -d "$_dir" ] && continue
        _name="$(basename "$_dir")"

        [ -d "$_dir/.output" ] && continue

        _exec_name="$(get_exec_name "$_dir")" || continue
        _binary="$(get_release_binary "$_dir" "$_exec_name")" || continue

        if ! is_running "$_name"; then
            continue
        fi

        _port="$(db_get_port_if_exists "$_name")"
        [ -z "$_port" ] && continue

        if ! health_check "$_name" "$_port"; then
            _pid="$(db_get_server_pid "$_name")"
            log "HEALTH: ${_name} (PID ${_pid}, port ${_port}) is unresponsive — restarting"
            stop_server "$_name"
            sleep 1
            start_server "$_name" "$_binary" "$_dir" "$_port"
            poll_reset
        fi
    done
}

# ── Main ─────────────────────────────────────────────────────────────────────

log "Server manager started (PID $$)"
log "Adaptive polling: ${POLL_MIN}s–${POLL_MAX}s, backoff ×${POLL_BACKOFF} after ${POLL_IDLE_CYCLES} idle cycles"

reconcile && poll_reset || true

while [ "$shutdown_flag" -eq 0 ]; do
    sleep "$poll_interval" &
    _sleep_pid=$!
    wait "$_sleep_pid" 2>/dev/null || true

    [ "$shutdown_flag" -eq 1 ] && break

    # ── SIGHUP: re-scan now (sent by sites-watcher after changes) ──
    if [ "$reload_flag" -eq 1 ]; then
        reload_flag=0
        log "SIGHUP received — re-scanning sites"
        reconcile && poll_reset || poll_reset  # signal always resets poll
        continue
    fi

    # ── SIGUSR1: process pending restart requests from the queue ──
    if [ "$restart_flag" -eq 1 ]; then
        restart_flag=0
        db_pop_all_restarts | while IFS= read -r _req; do
            [ -z "$_req" ] && continue
            _req_dir="$SITES_DIR/$_req"
            _req_exec="$(get_exec_name "$_req_dir")" || true
            if [ -n "$_req_exec" ] && _binary="$(get_release_binary "$_req_dir" "$_req_exec")"; then
                _port="$(db_get_port "$_req")"
                log "Restart requested for ${_req}"
                stop_server "$_req"
                sleep 1
                start_server "$_req" "$_binary" "$_req_dir" "$_port"
            else
                log "ERROR: restart requested for ${_req} but binary not found"
            fi
        done
        poll_reset
        continue
    fi

    # ── Regular poll: reap crashed children, detect rebuilds ──
    if reconcile; then
        poll_reset
    else
        poll_backoff
    fi

    # ── Periodic health checks ──
    health_cycle_counter=$((health_cycle_counter + 1))
    if [ "$health_cycle_counter" -ge "$HEALTH_CHECK_INTERVAL" ]; then
        health_cycle_counter=0
        run_health_checks
    fi
done

log "SIGTERM received — stopping all servers"
stop_all
db_remove_config "manager_pid"
log "Server manager stopped"
