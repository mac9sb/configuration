#!/bin/sh
# =============================================================================
#  Sites Watcher — Auto-configures Apache & launchd for ~/Developer/sites
#
#  Scans ~/Developer/sites for project directories. When a project has:
#    - .output/                    → configured as a static site (Alias)
#    - .build/release/Application  → configured as a server (reverse proxy)
#
#  Runs idempotently: compares current state against a saved snapshot and
#  only regenerates config / restarts services when something has changed.
#
#  Uses template files from ~/Developer/utilities/ instead of inline heredocs.
#
#  Triggered by launchd via:
#    - WatchPaths on ~/Developer/sites (new project added/removed)
#    - StartInterval every 30s (catches .output / .build appearing)
# =============================================================================

GITHUB_USER="mac9sb"
DEV_DIR="$HOME/Developer"
SITES_DIR="$DEV_DIR/sites"
UTILITIES_DIR="$DEV_DIR/utilities"
WATCHER_DIR="$DEV_DIR/.watchers"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
CUSTOM_CONF="/etc/apache2/extra/custom.conf"
LOG_DIR="/var/log/apache2/sites"
PORTS_FILE="$WATCHER_DIR/port-assignments"
STATE_FILE="$WATCHER_DIR/sites-state"
WATCHER_LOG="$WATCHER_DIR/sites-watcher.log"
SERVER_PORT_START=8000
MAX_CRASH_RETRIES=5
UID_NUM="$(id -u)"

# --- Template directories ---
APACHE_TMPL_DIR="$UTILITIES_DIR/apache"
LAUNCHD_TMPL_DIR="$UTILITIES_DIR/launchd"
SCRIPTS_TMPL_DIR="$UTILITIES_DIR/scripts"

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$WATCHER_LOG"; }

# =============================================================================
#  Template Rendering
# =============================================================================
# Renders a template file by replacing {{KEY}} placeholders with values.
# Usage: render_template <template_file> KEY=value KEY2=value2 ...
# Output is written to stdout.

render_template() {
    _tmpl_file="$1"
    shift

    if [ ! -f "$_tmpl_file" ]; then
        log "ERROR: Template not found: $_tmpl_file"
        return 1
    fi

    _rendered="$(cat "$_tmpl_file")"
    for _pair in "$@"; do
        _key="${_pair%%=*}"
        _val="${_pair#*=}"
        _rendered="$(printf '%s' "$_rendered" | sed "s|{{${_key}}}|${_val}|g")"
    done
    printf '%s\n' "$_rendered"
}

# =============================================================================
#  Ensure directories exist
# =============================================================================
mkdir -p "$WATCHER_DIR" "$LAUNCH_AGENTS_DIR"
sudo mkdir -p "$LOG_DIR" 2>/dev/null || true

# =============================================================================
#  1. Scan sites directory and build current state
# =============================================================================
#  State is a sorted list of lines:  repo:type
#  e.g.  "my-api:server\nportfolio:static"

current_state=""
for dir in "$SITES_DIR"/*/; do
    [ ! -d "$dir" ] && continue
    repo="$(basename "$dir")"

    if [ -d "$dir/.output" ]; then
        current_state="${current_state}${repo}:static
"
    elif [ -f "$dir/.build/release/Application" ]; then
        current_state="${current_state}${repo}:server
"
    fi
done

current_state="$(printf '%s' "$current_state" | sort)"

# =============================================================================
#  2. Compare with previous state — exit early if nothing changed
# =============================================================================
previous_state=""
[ -f "$STATE_FILE" ] && previous_state="$(cat "$STATE_FILE")"

if [ "$current_state" = "$previous_state" ]; then
    exit 0
fi

log "Change detected — regenerating configuration"
log "Previous: $(printf '%s' "$previous_state" | tr '\n' ' ')"
log "Current:  $(printf '%s' "$current_state" | tr '\n' ' ')"

# =============================================================================
#  3. Load / assign stable port numbers
# =============================================================================
#  Port assignments are persisted in $PORTS_FILE so that a site always keeps
#  the same port even when other sites are added or removed.
#  Format:  repo=port

touch "$PORTS_FILE"

get_port() {
    _repo="$1"
    _existing="$(grep "^${_repo}=" "$PORTS_FILE" 2>/dev/null | head -1 | cut -d= -f2)"
    if [ -n "$_existing" ]; then
        printf '%s' "$_existing"
        return
    fi
    # Find the next free port
    _max=$SERVER_PORT_START
    while IFS='=' read -r _ _p; do
        [ -n "$_p" ] && [ "$_p" -ge "$_max" ] && _max=$((_p + 1))
    done < "$PORTS_FILE"
    printf '%s=%s\n' "$_repo" "$_max" >> "$PORTS_FILE"
    printf '%s' "$_max"
}

# =============================================================================
#  4. Generate Apache custom.conf from templates
# =============================================================================

# Start with the header
_conf_file="$(mktemp)"
cat "$APACHE_TMPL_DIR/custom.conf.header" > "$_conf_file"
printf '\n' >> "$_conf_file"

# Append per-site blocks
printf '%s' "$current_state" | while IFS=: read -r repo type; do
    [ -z "$repo" ] && continue
    _dir="$SITES_DIR/$repo"

    case "$type" in
        static)
            _output="$_dir/.output"
            render_template "$APACHE_TMPL_DIR/static-site.conf.tmpl" \
                "SITE_NAME=$repo" \
                "OUTPUT_DIR=$_output" \
                "LOG_DIR=$LOG_DIR" \
                >> "$_conf_file"
            printf '\n' >> "$_conf_file"
            ;;
        server)
            _port="$(get_port "$repo")"
            render_template "$APACHE_TMPL_DIR/server-site.conf.tmpl" \
                "SITE_NAME=$repo" \
                "PORT=$_port" \
                "LOG_DIR=$LOG_DIR" \
                >> "$_conf_file"
            printf '\n' >> "$_conf_file"
            ;;
    esac
done

sudo cp "$_conf_file" "$CUSTOM_CONF"
rm -f "$_conf_file"
log "Wrote $CUSTOM_CONF"

# =============================================================================
#  5. Set permissions on static site output directories
# =============================================================================
printf '%s' "$current_state" | while IFS=: read -r repo type; do
    [ "$type" != "static" ] && continue
    _dir="$SITES_DIR/$repo"
    chmod -R o+r "$_dir/.output" 2>/dev/null || true
    chmod o+x "$DEV_DIR" "$SITES_DIR" "$_dir" "$_dir/.output" 2>/dev/null || true
done

# =============================================================================
#  6. Manage launchd agents for server binaries
# =============================================================================
#  - Create / update agents for current server sites
#  - Remove agents for sites that are no longer servers

# Collect current server repos
printf '%s' "$current_state" | while IFS=: read -r repo type; do
    [ "$type" = "server" ] && printf '%s\n' "$repo"
done > /tmp/sites-watcher-servers.$$
current_servers="$(cat /tmp/sites-watcher-servers.$$)"
rm -f /tmp/sites-watcher-servers.$$

# Collect previous server repos
printf '%s' "$previous_state" | while IFS=: read -r repo type; do
    [ "$type" = "server" ] && printf '%s\n' "$repo"
done > /tmp/sites-watcher-prev-servers.$$
previous_servers="$(cat /tmp/sites-watcher-prev-servers.$$)"
rm -f /tmp/sites-watcher-prev-servers.$$

# --- Remove agents for sites no longer present as servers ---
for repo in $previous_servers; do
    if ! printf '%s' "$current_servers" | grep -qx "$repo"; then
        log "Removing agents for departed server: $repo"

        _label="com.${GITHUB_USER}.${repo}"
        _watcher_label="${_label}.watcher"

        launchctl bootout "gui/${UID_NUM}/${_label}" 2>/dev/null || true
        launchctl bootout "gui/${UID_NUM}/${_watcher_label}" 2>/dev/null || true
        rm -f "${LAUNCH_AGENTS_DIR}/${_label}.plist"
        rm -f "${LAUNCH_AGENTS_DIR}/${_watcher_label}.plist"
        rm -f "$WATCHER_DIR/${repo}-run.sh"
        rm -f "$WATCHER_DIR/${repo}-restart.sh"
        rm -f "$WATCHER_DIR/${repo}.crash_count"
    fi
done

# --- Create / update agents for current servers ---
for repo in $current_servers; do
    _dir="$SITES_DIR/$repo"
    _binary="$_dir/.build/release/Application"
    _port="$(get_port "$repo")"
    _label="com.${GITHUB_USER}.${repo}"
    _watcher_label="${_label}.watcher"
    _crash_file="$WATCHER_DIR/${repo}.crash_count"

    # -- Crash-guarded run wrapper (rendered from template) --
    _wrapper="$WATCHER_DIR/${repo}-run.sh"
    render_template "$SCRIPTS_TMPL_DIR/crash-wrapper.sh.tmpl" \
        "SITE_NAME=$repo" \
        "CRASH_COUNT_FILE=$_crash_file" \
        "MAX_RETRIES=$MAX_CRASH_RETRIES" \
        "PORT=$_port" \
        "BINARY_PATH=$_binary" \
        "WATCHER_DIR=$WATCHER_DIR" \
        > "$_wrapper"
    chmod +x "$_wrapper"

    # -- Server launchd plist (rendered from template) --
    _plist="${LAUNCH_AGENTS_DIR}/${_label}.plist"
    render_template "$LAUNCHD_TMPL_DIR/server-agent.plist.tmpl" \
        "LABEL=$_label" \
        "WRAPPER_SCRIPT=$_wrapper" \
        "LOG_FILE=$WATCHER_DIR/${repo}.log" \
        "ERROR_LOG_FILE=$WATCHER_DIR/${repo}.error.log" \
        > "$_plist"

    launchctl bootout "gui/${UID_NUM}/${_label}" 2>/dev/null || true
    launchctl bootstrap "gui/${UID_NUM}" "$_plist" 2>/dev/null || launchctl load "$_plist" 2>/dev/null || true
    log "Server agent loaded: $_label (port $_port)"

    # -- Binary watcher restart script (rendered from template) --
    _restart_script="$WATCHER_DIR/${repo}-restart.sh"
    _server_plist="${LAUNCH_AGENTS_DIR}/${_label}.plist"
    render_template "$SCRIPTS_TMPL_DIR/restart-server.sh.tmpl" \
        "SITE_NAME=$repo" \
        "CRASH_COUNT_FILE=$_crash_file" \
        "WATCHER_DIR=$WATCHER_DIR" \
        "UID_NUM=$UID_NUM" \
        "SERVER_LABEL=$_label" \
        "SERVER_PLIST=$_server_plist" \
        > "$_restart_script"
    chmod +x "$_restart_script"

    # -- Watcher launchd plist (rendered from template) --
    _watcher_plist="${LAUNCH_AGENTS_DIR}/${_watcher_label}.plist"
    render_template "$LAUNCHD_TMPL_DIR/watcher-agent.plist.tmpl" \
        "LABEL=$_watcher_label" \
        "RESTART_SCRIPT=$_restart_script" \
        "BINARY_PATH=$_binary" \
        "LOG_FILE=$WATCHER_DIR/${repo}-watcher.log" \
        "ERROR_LOG_FILE=$WATCHER_DIR/${repo}-watcher.error.log" \
        > "$_watcher_plist"

    launchctl bootout "gui/${UID_NUM}/${_watcher_label}" 2>/dev/null || true
    launchctl bootstrap "gui/${UID_NUM}" "$_watcher_plist" 2>/dev/null || launchctl load "$_watcher_plist" 2>/dev/null || true
    log "Watcher agent loaded: $_watcher_label"
done

# =============================================================================
#  7. Test & restart Apache
# =============================================================================
if sudo apachectl configtest >/dev/null 2>&1; then
    sudo apachectl restart
    log "Apache restarted successfully"
else
    log "ERROR: Apache config test failed — manual fix required"
    osascript -e 'display notification "Apache configuration test failed after sites-watcher update. Check '"$CUSTOM_CONF"'." with title "Apache Config Error" sound name "Basso"' 2>/dev/null || true
fi

# =============================================================================
#  8. Save state snapshot
# =============================================================================
printf '%s' "$current_state" > "$STATE_FILE"
log "State saved — done"
