#!/bin/sh
# =============================================================================
#  Sites Watcher — Auto-configures Apache for ~/Developer/sites
#
#  Scans ~/Developer/sites for project directories. When a project has:
#    - .output/                        → configured as a static site
#    - .build/release/<exec>           → configured as a server (reverse proxy)
#
#  Domain routing (derived from directory names + primary domain):
#    The primary domain is parsed from the cloudflared config comment:
#      # primary-domain: maclong.dev
#
#    Directory name        VirtualHost ServerName     Access
#    ─────────────────     ──────────────────────     ──────────────────────
#    sites/maclong.dev/    maclong.dev                root of primary domain
#    sites/api-thing/      api-thing.maclong.dev      subdomain of primary
#    sites/cool-app.com/   cool-app.com               custom domain
#
#    Every site also gets a path-based entry in the default VirtualHost
#    for local dev access at http://localhost/site-name/.
#
#  Runs idempotently: compares current state against the SQLite database
#  and only regenerates config / restarts services when something has changed.
#
#  Uses template files from ~/Developer/utilities/apache/ for Apache config.
#  Server binaries are managed by a separate server-manager process — this
#  script sends SIGHUP so it re-scans the filesystem for new/removed servers.
#
#  All state is stored in a SQLite database (WAL mode) for atomic,
#  concurrent-safe access shared with server-manager and restart-server.sh.
#
#  State DB: ~/Library/Application Support/com.mac9sb/state.db
#    - sites table        classification + port assignments
#    - config table       server-manager PID for signalling
#
#  Logs: ~/Library/Logs/com.mac9sb/
#    - sites-watcher.log
#
#  Triggered by launchd via:
#    - WatchPaths on ~/Developer/sites (new project added/removed)
#    - StartInterval every 30s (catches .output / .build appearing)
# =============================================================================

DEV_DIR="$HOME/Developer"
SITES_DIR="$DEV_DIR/sites"
UTILITIES_DIR="$DEV_DIR/utilities"
LOG_DIR="$HOME/Library/Logs/com.mac9sb"
CUSTOM_CONF="/etc/apache2/extra/custom.conf"
APACHE_LOG_DIR="/var/log/apache2/sites"
WATCHER_LOG="$LOG_DIR/sites-watcher.log"

APACHE_TMPL_DIR="$UTILITIES_DIR/apache"
CLOUDFLARED_CONFIG="$UTILITIES_DIR/cloudflared/config.yml"
INGRESS_BEGIN="# sites-watcher:BEGIN"
INGRESS_END="# sites-watcher:END"

# Source the shared SQLite helpers
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPTS_DIR/db.sh"

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$WATCHER_LOG"; }

# =============================================================================
#  Template Rendering
# =============================================================================

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
#  Parse primary domain from cloudflared config
# =============================================================================
#  Reads the "# primary-domain: maclong.dev" comment line from config.yml.
#  This is the single source of truth for subdomain generation.

PRIMARY_DOMAIN=""
if [ -f "$CLOUDFLARED_CONFIG" ]; then
    PRIMARY_DOMAIN="$(sed -n 's/^# *primary-domain: *//p' "$CLOUDFLARED_CONFIG" | head -1 | tr -d '[:space:]')"
fi

if [ -z "$PRIMARY_DOMAIN" ]; then
    log "WARN: No primary-domain found in $CLOUDFLARED_CONFIG — subdomain routing disabled"
fi

# =============================================================================
#  Resolve the public domain for a site directory name
# =============================================================================
#  - Name contains a dot  → custom domain (name IS the domain)
#  - Name has no dot       → subdomain of PRIMARY_DOMAIN
#  Returns the domain on stdout. Returns 1 only if no primary domain is
#  configured AND the name has no dot (cannot form a subdomain).

resolve_domain() {
    case "$1" in
        *.*)
            # Custom domain — directory name is the domain
            printf '%s' "$1"
            return 0
            ;;
        *)
            # Subdomain of primary domain
            if [ -n "$PRIMARY_DOMAIN" ]; then
                printf '%s.%s' "$1" "$PRIMARY_DOMAIN"
                return 0
            fi
            return 1
            ;;
    esac
}

# =============================================================================
#  Sync cloudflared ingress entries for custom domains
# =============================================================================

sync_cloudflared_ingress() {
    [ ! -f "$CLOUDFLARED_CONFIG" ] && return 0

    if ! grep -q "$INGRESS_BEGIN" "$CLOUDFLARED_CONFIG" || ! grep -q "$INGRESS_END" "$CLOUDFLARED_CONFIG"; then
        log "WARN: cloudflared config missing ingress markers — skipping custom domain sync"
        return 0
    fi

    _primary_domain="${PRIMARY_DOMAIN:-}"
    # Directory names with dots represent custom domains; subdomains never include dots.
    # If a primary domain is configured, exclude it from the custom domain list.
    _custom_domains="$(printf '%s' "$current_state" | awk -F: -v primary="$_primary_domain" 'NF { if ($1 ~ /\./ && (primary == "" || $1 != primary)) print $1 }' | sort -u)"
    _block_file="$(mktemp "${TMPDIR:-/tmp}/cloudflared.ingress.XXXXXX")"
    if [ -n "$_custom_domains" ]; then
        for _domain in $_custom_domains; do
            printf '  - hostname: %s\n    service: http://localhost:80\n' "$_domain" >> "$_block_file"
        done
    else
        printf '  # (none)\n' >> "$_block_file"
    fi

    _tmp_config="$(mktemp "${TMPDIR:-/tmp}/cloudflared.config.XXXXXX")"
    # Replace the contents between ingress markers with the generated block.
    awk -v begin="$INGRESS_BEGIN" -v end="$INGRESS_END" -v block="$_block_file" '
        $0 ~ begin {
            print
            while ((getline line < block) > 0) {
                print line
            }
            close(block)
            in_block=1
            next
        }
        $0 ~ end { in_block=0; print; next }
        !in_block { print }
    ' "$CLOUDFLARED_CONFIG" > "$_tmp_config"

    if ! cmp -s "$_tmp_config" "$CLOUDFLARED_CONFIG"; then
        if cp "$_tmp_config" "$CLOUDFLARED_CONFIG"; then
            log "Updated cloudflared ingress entries for custom domains (restart cloudflared to apply)"
        else
            log "ERROR: Failed to update cloudflared ingress entries"
            return 1
        fi
    fi

    rm -f "$_block_file" "$_tmp_config"
}

# =============================================================================
#  Ensure directories exist & initialise database
# =============================================================================
mkdir -p "$LOG_DIR"
sudo mkdir -p "$APACHE_LOG_DIR" 2>/dev/null || true

db_init

# =============================================================================
#  1. Scan sites directory and build current state
# =============================================================================
#  State is a sorted list of lines:  repo:type
#  e.g.  "maclong.dev:static\napi-thing:server"

current_state=""
_discovered_names=""
for dir in "$SITES_DIR"/*/; do
    [ ! -d "$dir" ] && continue
    repo="$(basename "$dir")"

    if [ -d "$dir/.output" ]; then
        current_state="${current_state}${repo}:static
"
        _discovered_names="${_discovered_names} ${repo}"
    else
        _exec_name="$(get_exec_name "$dir")" || true
        if [ -n "$_exec_name" ] && [ -f "$dir/.build/release/$_exec_name" ]; then
            current_state="${current_state}${repo}:server
"
            _discovered_names="${_discovered_names} ${repo}"
        fi
    fi
done

current_state="$(printf '%s' "$current_state" | sort)"

# =============================================================================
#  2. Sync cloudflared ingress entries from filesystem
# =============================================================================
sync_cloudflared_ingress

# =============================================================================
#  3. Compare with previous state — exit early if nothing changed
# =============================================================================
previous_state="$(db_get_sites_state)"

if [ "$current_state" = "$previous_state" ]; then
    exit 0
fi

log "Change detected — regenerating configuration"
log "Previous: $(printf '%s' "$previous_state" | tr '\n' ' ')"
log "Current:  $(printf '%s' "$current_state" | tr '\n' ' ')"

# =============================================================================
#  4. Update site records in the database (upsert + prune removed sites)
# =============================================================================

printf '%s' "$current_state" | while IFS=: read -r repo type; do
    [ -z "$repo" ] && continue
    db_set_site "$repo" "$type"
done

db_prune_sites "$_discovered_names"

# =============================================================================
#  5. Generate Apache custom.conf from templates
# =============================================================================
#
#  Every site gets TWO config entries:
#    1. A VirtualHost block for public access (domain or subdomain)
#    2. A path-based entry in the default VirtualHost for localhost dev access
#
#  Layout:
#    - Default VirtualHost (listed FIRST — catches localhost and any unmatched
#      request). Contains path-based Alias / Location blocks for ALL sites.
#    - Per-site VirtualHosts for domain and subdomain access.

_conf_file="$(mktemp)"
_vhost_file="$(mktemp)"
_default_file="$(mktemp)"

printf '%s' "$current_state" | while IFS=: read -r repo type; do
    [ -z "$repo" ] && continue
    _dir="$SITES_DIR/$repo"

    # ── Path-based entry (always generated, for localhost dev access) ──
    case "$type" in
        static)
            _output="$_dir/.output"
            render_template "$APACHE_TMPL_DIR/static-site.conf.tmpl" \
                "SITE_NAME=$repo" \
                "OUTPUT_DIR=$_output" \
                "LOG_DIR=$APACHE_LOG_DIR" \
                >> "$_default_file"
            printf '\n' >> "$_default_file"
            ;;
        server)
            _port="$(db_get_port "$repo")"
            render_template "$APACHE_TMPL_DIR/server-site.conf.tmpl" \
                "SITE_NAME=$repo" \
                "PORT=$_port" \
                "LOG_DIR=$APACHE_LOG_DIR" \
                >> "$_default_file"
            printf '\n' >> "$_default_file"
            ;;
    esac

    # ── VirtualHost entry (for public domain/subdomain access) ──
    _domain="$(resolve_domain "$repo")" || true

    if [ -z "$_domain" ]; then
        log "  Path-only: /$repo (no primary domain configured for subdomain)"
        continue
    fi

    case "$type" in
        static)
            _output="$_dir/.output"
            render_template "$APACHE_TMPL_DIR/static-vhost.conf.tmpl" \
                "SITE_NAME=$repo" \
                "DOMAIN=$_domain" \
                "OUTPUT_DIR=$_output" \
                "LOG_DIR=$APACHE_LOG_DIR" \
                >> "$_vhost_file"
            printf '\n' >> "$_vhost_file"
            log "  VirtualHost: $_domain → static ($repo)"
            ;;
        server)
            _port="$(db_get_port "$repo")"
            render_template "$APACHE_TMPL_DIR/server-vhost.conf.tmpl" \
                "SITE_NAME=$repo" \
                "DOMAIN=$_domain" \
                "PORT=$_port" \
                "LOG_DIR=$APACHE_LOG_DIR" \
                >> "$_vhost_file"
            printf '\n' >> "$_vhost_file"
            log "  VirtualHost: $_domain → proxy :$_port ($repo)"
            ;;
    esac
done

# --- Assemble the final config ---
cat > "$_conf_file" <<APACHE_HEADER
# =============================================================================
#  Auto-generated by sites-watcher.sh — do not edit directly.
#
#  Primary domain: ${PRIMARY_DOMAIN:-"(not configured)"}
#  Routing:
#    sites/maclong.dev/   → VirtualHost maclong.dev        (custom domain)
#    sites/api-thing/     → VirtualHost api-thing.${PRIMARY_DOMAIN:-"???"}  (subdomain)
#    All sites            → localhost/site-name/            (path-based dev)
# =============================================================================

APACHE_HEADER

_has_vhosts=false
_has_defaults=false

if [ -s "$_vhost_file" ]; then
    _has_vhosts=true
fi

if [ -s "$_default_file" ]; then
    _has_defaults=true
fi

if [ "$_has_vhosts" = true ] || [ "$_has_defaults" = true ]; then

    # --- Default VirtualHost (must come first — catches localhost + unmatched) ---
    cat >> "$_conf_file" <<'DEFAULT_OPEN'
# --- Default VirtualHost (localhost path-based access for all sites) ---
<VirtualHost *:80>
    ServerName localhost
    ServerAlias *

    ProxyPreserveHost On
    ProxyRequests Off

    # --- Global proxy headers (Cloudflare terminates TLS) ---
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Port "443"

DEFAULT_OPEN

    if [ "$_has_defaults" = true ]; then
        cat "$_default_file" >> "$_conf_file"
    fi

    cat >> "$_conf_file" <<'DEFAULT_CLOSE'
</VirtualHost>

DEFAULT_CLOSE

    # --- Domain / subdomain VirtualHosts ---
    if [ "$_has_vhosts" = true ]; then
        cat "$_vhost_file" >> "$_conf_file"
    fi
fi

rm -f "$_vhost_file" "$_default_file"

# Atomic swap: backup old config, install new, validate, rollback on failure
_old_conf=""
if [ -f "$CUSTOM_CONF" ]; then
    _old_conf="$(mktemp)"
    sudo cp "$CUSTOM_CONF" "$_old_conf"
fi

sudo cp "$_conf_file" "$CUSTOM_CONF"
rm -f "$_conf_file"

if sudo apachectl configtest >/dev/null 2>&1; then
    log "Wrote $CUSTOM_CONF (configtest passed)"
else
    log "ERROR: New config failed configtest — rolling back"
    if [ -n "$_old_conf" ] && [ -f "$_old_conf" ]; then
        sudo cp "$_old_conf" "$CUSTOM_CONF"
        log "Restored previous $CUSTOM_CONF"
    else
        sudo rm -f "$CUSTOM_CONF"
        log "Removed broken $CUSTOM_CONF (no previous config to restore)"
    fi
    rm -f "$_old_conf"
    osascript -e 'display notification "Apache configuration test failed after sites-watcher update. Rolled back to previous config." with title "Apache Config Error" sound name "Basso"' 2>/dev/null || true
    exit 1
fi
rm -f "$_old_conf"

# =============================================================================
#  6. Set permissions on static site output directories
# =============================================================================
printf '%s' "$current_state" | while IFS=: read -r repo type; do
    [ "$type" != "static" ] && continue
    _dir="$SITES_DIR/$repo"
    chmod -R o+r "$_dir/.output" 2>/dev/null || true
    chmod o+x "$DEV_DIR" "$SITES_DIR" "$_dir" "$_dir/.output" 2>/dev/null || true
done

# =============================================================================
#  7. Signal the server-manager to re-scan
# =============================================================================
_mgr_pid="$(db_get_config "manager_pid")"
if [ -n "$_mgr_pid" ]; then
    if kill -0 "$_mgr_pid" 2>/dev/null; then
        kill -HUP "$_mgr_pid"
        log "Sent SIGHUP to server-manager (PID $_mgr_pid)"
    else
        log "WARN: server-manager (PID $_mgr_pid) is not running"
    fi
else
    log "WARN: server-manager PID not found in database — manager may not be running"
fi

# =============================================================================
#  8. Restart Apache (config already validated during atomic swap above)
# =============================================================================
sudo apachectl restart
log "Apache restarted successfully"

# =============================================================================
#  9. Done — state is already persisted in the database
# =============================================================================
log "State saved — done"
