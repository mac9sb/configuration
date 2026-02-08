#!/bin/sh
set -e

# =============================================================================
#  macOS Developer Environment Setup
#  Author: Mac (maclong9)
#
#  This script sets up a complete development environment including:
#    - Touch ID for sudo
#    - Dotfiles (symlinked from utilities/dotfiles)
#    - SSH key generation
#    - Xcode CLI tools & Swift
#    - CLI tooling (cloudflared)
#    - Git submodule initialization & hook installation
#    - Building Swift projects (with rollback preservation)
#    - Apache with mod_proxy/mod_rewrite/mod_headers + per-site config
#    - Cloudflare tunnel config (in-repo config, credentials off-repo)
#    - SQLite state database initialisation + port assignments
#    - Symlinked launchd agents (server-manager, sites-watcher, backup, cloudflared)
#    - Log rotation via newsyslog
#
#  All runtime state is stored in a single SQLite database (WAL mode)
#  at ~/Library/Application Support/com.mac9sb/state.db — shared by
#  server-manager, sites-watcher, and restart-server.sh for atomic,
#  concurrent-safe access.
#
#  Repos are managed entirely as git submodules. No hardcoded arrays —
#  everything is derived from .gitmodules and filesystem state.
# =============================================================================

GITHUB_USER="mac9sb"
GIT_EMAIL="maclong9@icloud.com"

DEV_DIR="$HOME/Developer"
SITES_DIR="$DEV_DIR/sites"
TOOLING_DIR="$DEV_DIR/tooling"
UTILITIES_DIR="$DEV_DIR/utilities"
STATE_DIR="$HOME/Library/Application Support/com.mac9sb"
LOG_DIR="$HOME/Library/Logs/com.mac9sb"

HTTPD_CONF="/etc/apache2/httpd.conf"
CUSTOM_CONF="/etc/apache2/extra/custom.conf"
APACHE_LOG_DIR="/var/log/apache2/sites"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# --- Utility directories ---
APACHE_TMPL_DIR="$UTILITIES_DIR/apache"
LAUNCHD_DIR="$UTILITIES_DIR/launchd"
SCRIPTS_DIR="$UTILITIES_DIR/scripts"
DOTFILES_DIR="$UTILITIES_DIR/dotfiles"
GITHOOKS_DIR="$UTILITIES_DIR/githooks"
CLOUDFLARED_DIR="$UTILITIES_DIR/cloudflared"
NEWSYSLOG_DIR="$UTILITIES_DIR/newsyslog"

# --- Port allocation ----------------------------------------------------------
SERVER_PORT_START=8000

# --- Classification timeout (seconds) ----------------------------------------
CLASSIFY_TIMEOUT=15

# --- Source shared SQLite helpers ---------------------------------------------
. "$SCRIPTS_DIR/db.sh"

UID_NUM="$(id -u)"
TOTAL_STEPS=14

# Initialise the state database early so db_* helpers are available
mkdir -p "$STATE_DIR" "$LOG_DIR"
db_init

# =============================================================================
#  Utility Functions
# =============================================================================

info()    { printf "\033[1;34m[INFO]\033[0m  %s\n" "$1"; }
success() { printf "\033[1;32m[OK]\033[0m    %s\n" "$1"; }
warn()    { printf "\033[1;33m[WARN]\033[0m  %s\n" "$1"; }
error()   { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1"; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Renders a template file by replacing {{KEY}} placeholders with values.
# Usage: render_template <template_file> KEY=value KEY2=value2 ...
# Output is written to stdout.
render_template() {
    _tmpl_file="$1"
    shift

    if [ ! -f "$_tmpl_file" ]; then
        error "Template not found: $_tmpl_file"
    fi

    _rendered="$(cat "$_tmpl_file")"
    for _pair in "$@"; do
        _key="${_pair%%=*}"
        _val="${_pair#*=}"
        _rendered="$(printf '%s' "$_rendered" | sed "s|{{${_key}}}|${_val}|g")"
    done
    printf '%s\n' "$_rendered"
}

# Run a command with a timeout.
# Usage: run_with_timeout <seconds> <command> [args...]
# Returns 0 if the command finished in time, 1 if it was killed.
run_with_timeout() {
    _timeout="$1"
    shift

    "$@" &
    _cmd_pid=$!

    (
        sleep "$_timeout"
        kill "$_cmd_pid" 2>/dev/null || true
    ) &
    _timer_pid=$!

    if wait "$_cmd_pid" 2>/dev/null; then
        kill "$_timer_pid" 2>/dev/null || true
        wait "$_timer_pid" 2>/dev/null || true
        return 0
    else
        kill "$_timer_pid" 2>/dev/null || true
        wait "$_timer_pid" 2>/dev/null || true
        return 1
    fi
}

# =============================================================================
#  Step 1 — Touch ID for sudo
# =============================================================================

info "Step 1/${TOTAL_STEPS}: Touch ID for sudo"
if [ ! -f /etc/pam.d/sudo_local ] || ! grep -q "pam_tid.so" /etc/pam.d/sudo_local 2>/dev/null; then
    sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
    sudo sed -i '' 's/^#auth/auth/' /etc/pam.d/sudo_local
    success "Touch ID enabled for sudo"
else
    success "Touch ID already configured"
fi

# =============================================================================
#  Step 2 — Symlink Dotfiles
# =============================================================================

info "Step 2/${TOTAL_STEPS}: Symlinking dotfiles"

for _src in "$DOTFILES_DIR"/*; do
    [ ! -f "$_src" ] && continue
    _base="$(basename "$_src")"
    # ssh_config is handled separately below (nested ~/.ssh/ directory)
    [ "$_base" = "ssh_config" ] && continue
    _dest="$HOME/.${_base}"

    if [ -L "$_dest" ] && [ "$(readlink "$_dest")" = "$_src" ]; then
        success "  ~/.${_base} already symlinked"
    else
        if [ -e "$_dest" ] && [ ! -L "$_dest" ]; then
            mv "$_dest" "${_dest}.bak.$(date +%Y%m%d%H%M%S)"
            warn "  Backed up existing ~/.${_base}"
        fi
        ln -sf "$_src" "$_dest"
        success "  ~/.${_base} → $_src"
    fi
done

# SSH config is a special case (nested directory)
_ssh_config_src="$DOTFILES_DIR/ssh_config"
_ssh_config_dest="$HOME/.ssh/config"
if [ -f "$_ssh_config_src" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    if [ -L "$_ssh_config_dest" ] && [ "$(readlink "$_ssh_config_dest")" = "$_ssh_config_src" ]; then
        success "  ~/.ssh/config already symlinked"
    else
        if [ -e "$_ssh_config_dest" ] && [ ! -L "$_ssh_config_dest" ]; then
            mv "$_ssh_config_dest" "${_ssh_config_dest}.bak.$(date +%Y%m%d%H%M%S)"
            warn "  Backed up existing ~/.ssh/config"
        fi
        ln -sf "$_ssh_config_src" "$_ssh_config_dest"
        success "  ~/.ssh/config → $_ssh_config_src"
    fi
fi

# =============================================================================
#  Step 3 — SSH key
# =============================================================================

info "Step 3/${TOTAL_STEPS}: SSH key"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$HOME/.ssh/id_ed25519" -N ""
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" 2>/dev/null || ssh-add "$HOME/.ssh/id_ed25519"
    success "SSH key generated at ~/.ssh/id_ed25519"
    warn "Add this public key to GitHub:"
    cat "$HOME/.ssh/id_ed25519.pub"
    printf "\n"
else
    success "SSH key already exists"
fi

# =============================================================================
#  Step 4 — Xcode CLI Tools & Swift
# =============================================================================

info "Step 4/${TOTAL_STEPS}: Xcode Command Line Tools & Swift"
if ! xcode-select -p >/dev/null 2>&1; then
    info "Installing Xcode Command Line Tools (this may take a while)..."
    xcode-select --install 2>/dev/null || true
    until xcode-select -p >/dev/null 2>&1; do
        sleep 5
    done
    success "Xcode CLI Tools installed"
else
    success "Xcode CLI Tools already installed"
fi

if command_exists swift; then
    success "Swift available: $(swift --version 2>&1 | head -1)"
else
    error "Swift not found after Xcode CLI tools install. Install Xcode or Xcode CLI tools manually."
fi

# =============================================================================
#  Step 5 — Install cloudflared
# =============================================================================

info "Step 5/${TOTAL_STEPS}: Installing cloudflared"
if ! command_exists cloudflared; then
    CF_LATEST=$(curl -sL -o /dev/null -w '%{url_effective}' https://github.com/cloudflare/cloudflared/releases/latest | sed 's|.*/||')
    CF_PKG_URL="https://github.com/cloudflare/cloudflared/releases/download/${CF_LATEST}/cloudflared-darwin-arm64.pkg"
    info "Downloading cloudflared ${CF_LATEST}..."
    TMPDIR_CF="$(mktemp -d)"
    curl -sL "$CF_PKG_URL" -o "$TMPDIR_CF/cloudflared.pkg"
    sudo installer -pkg "$TMPDIR_CF/cloudflared.pkg" -target / >/dev/null 2>&1
    rm -rf "$TMPDIR_CF"
    if command_exists cloudflared; then
        success "cloudflared installed: $(cloudflared --version 2>&1 | head -1)"
    else
        warn "cloudflared pkg installed but binary not found on PATH — check /usr/local/bin"
    fi
else
    success "cloudflared already installed: $(cloudflared --version 2>&1 | head -1)"
fi


# =============================================================================
#  Step 6 — Initialize git submodules & install hooks
# =============================================================================

info "Step 6/${TOTAL_STEPS}: Initializing git submodules & installing hooks"
mkdir -p "$SITES_DIR" "$TOOLING_DIR" "$STATE_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"

cd "$DEV_DIR"

if [ -f "$DEV_DIR/.gitmodules" ]; then
    git submodule update --init --recursive 2>/dev/null
    success "All submodules initialized"

    # Report what was found
    git submodule foreach --quiet 'printf "  %s\n" "$sm_path"' | while read -r _path; do
        success "$_path"
    done
else
    warn "No .gitmodules found — add submodules with 'git submodule add'"
fi

# Install git hooks from utilities/githooks
if [ -d "$GITHOOKS_DIR" ]; then
    _hooks_dest="$DEV_DIR/.git/hooks"
    mkdir -p "$_hooks_dest"
    for _hook in "$GITHOOKS_DIR"/*; do
        [ ! -f "$_hook" ] && continue
        _hook_name="$(basename "$_hook")"
        cp "$_hook" "$_hooks_dest/$_hook_name"
        chmod +x "$_hooks_dest/$_hook_name"
        success "  Installed git hook: $_hook_name"
    done
else
    warn "No githooks directory found at $GITHOOKS_DIR"
fi

# =============================================================================
#  Step 7 — Build Swift projects (with rollback preservation)
# =============================================================================

info "Step 7/${TOTAL_STEPS}: Building Swift projects"

# Build any Swift package found under tooling/
for _dir in "$TOOLING_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    if [ -f "$_dir/Package.swift" ]; then
        info "  Building tooling: $_name..."
        (cd "$_dir" && swift build -c release 2>&1 | tail -1)
        success "  $_name built"
    fi
done

# Build any Swift package found under sites/
# After building, determine type by running the binary once with a timeout —
# if it exits cleanly and produces .output, it's static. Otherwise it's a
# server that launchd will manage. The timeout prevents hangs from server
# binaries that block waiting for connections.
for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    if [ -f "$_dir/Package.swift" ]; then
        _binary="$_dir/.build/release/Application"

        # Preserve current run binary as backup before rebuilding
        if [ -f "${_binary}.run" ]; then
            cp -f "${_binary}.run" "${_binary}.bak" 2>/dev/null || true
        fi

        info "  Building site: $_name..."
        if (cd "$_dir" && swift build -c release 2>&1 | tail -1); then
            success "  $_name built"
        else
            warn "  $_name build failed"
            # Restore backup if build produced no binary
            if [ ! -f "$_binary" ] && [ -f "${_binary}.bak" ]; then
                cp -f "${_binary}.bak" "$_binary" 2>/dev/null || true
                warn "  Restored backup binary for $_name"
            fi
        fi

        # If no .output exists yet but the binary is present, try running it
        # once with a timeout to see if it generates static output.
        if [ ! -d "$_dir/.output" ] && [ -f "$_binary" ]; then
            info "  Classifying $_name (timeout ${CLASSIFY_TIMEOUT}s)..."
            if run_with_timeout "$CLASSIFY_TIMEOUT" sh -c "cd '$_dir' && .build/release/Application" 2>/dev/null; then
                success "  $_name exited cleanly"
            else
                success "  $_name did not exit within ${CLASSIFY_TIMEOUT}s (likely a server)"
            fi
        fi

        if [ -d "$_dir/.output" ]; then
            success "  $_name → static site (.output generated)"
        elif [ -f "$_binary" ]; then
            success "  $_name → server binary (launchd will manage)"
        fi
    fi
done

# =============================================================================
#  Step 8 — Configure Apache (with atomic reload)
# =============================================================================

info "Step 8/${TOTAL_STEPS}: Configuring Apache"

enable_module() {
    _mod="$1"
    if grep -q "^#.*$_mod" "$HTTPD_CONF"; then
        sudo sed -i '' "s|^#\\(.*$_mod\\)|\\1|" "$HTTPD_CONF"
        success "  Enabled $_mod"
    else
        success "  $_mod already enabled"
    fi
}

sudo cp "$HTTPD_CONF" "${HTTPD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
for _mod in mod_proxy.so mod_proxy_http.so mod_rewrite.so mod_proxy_wstunnel.so mod_headers.so; do
    enable_module "$_mod"
done

if ! grep -q "extra/custom.conf" "$HTTPD_CONF"; then
    printf "\n# Developer custom site configuration\nInclude /private/etc/apache2/extra/custom.conf\n" \
        | sudo tee -a "$HTTPD_CONF" >/dev/null
    success "  Added custom.conf Include to httpd.conf"
else
    success "  custom.conf Include already in httpd.conf"
fi

sudo mkdir -p "$APACHE_LOG_DIR"
sudo chown root:wheel "$APACHE_LOG_DIR"

# Build custom.conf by scanning sites/ for static (.output) and server
# (.build/release/Application) projects — no hardcoded arrays.
# Port assignments come from the SQLite database (initialised in step 9).
#
# Domain routing is derived from directory names + primary domain from
# the cloudflared config (# primary-domain: maclong.dev):
#   sites/maclong.dev/   → VirtualHost maclong.dev         (custom domain)
#   sites/api-thing/     → VirtualHost api-thing.maclong.dev (subdomain)
#   sites/cool-app.com/  → VirtualHost cool-app.com        (custom domain)
#   All sites            → localhost/site-name/             (path-based dev)

# Parse primary domain from cloudflared config
_cf_config="$CLOUDFLARED_DIR/config.yml"
PRIMARY_DOMAIN=""
if [ -f "$_cf_config" ]; then
    PRIMARY_DOMAIN="$(sed -n 's/^# *primary-domain: *//p' "$_cf_config" | head -1 | tr -d '[:space:]')"
fi

if [ -n "$PRIMARY_DOMAIN" ]; then
    success "  Primary domain: $PRIMARY_DOMAIN"
else
    warn "  No primary-domain found in cloudflared config — subdomain routing disabled"
fi

# Resolve the public domain for a site directory name
resolve_domain() {
    case "$1" in
        *.*) printf '%s' "$1"; return 0 ;;
        *)
            if [ -n "$PRIMARY_DOMAIN" ]; then
                printf '%s.%s' "$1" "$PRIMARY_DOMAIN"
                return 0
            fi
            return 1
            ;;
    esac
}

_conf_file="$(mktemp)"
_vhost_file="$(mktemp)"
_default_file="$(mktemp)"

for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"

    if [ -d "$_dir/.output" ]; then
        _output_dir="$_dir/.output"
        chmod -R o+r "$_output_dir" 2>/dev/null || true
        db_set_site "$_name" "static"

        # Path-based entry (always — for localhost dev access)
        render_template "$APACHE_TMPL_DIR/static-site.conf.tmpl" \
            "SITE_NAME=$_name" \
            "OUTPUT_DIR=$_output_dir" \
            "LOG_DIR=$APACHE_LOG_DIR" \
            >> "$_default_file"
        printf '\n' >> "$_default_file"

        # VirtualHost entry (domain or subdomain)
        _domain="$(resolve_domain "$_name")" || true
        if [ -n "$_domain" ]; then
            render_template "$APACHE_TMPL_DIR/static-vhost.conf.tmpl" \
                "SITE_NAME=$_name" \
                "DOMAIN=$_domain" \
                "OUTPUT_DIR=$_output_dir" \
                "LOG_DIR=$APACHE_LOG_DIR" \
                >> "$_vhost_file"
            printf '\n' >> "$_vhost_file"
            success "  $_domain → static ($_name)"
        else
            success "  localhost/$_name → static (path-based only)"
        fi

    elif [ -f "$_dir/.build/release/Application" ]; then
        _port="$(db_get_port "$_name")"
        db_set_site "$_name" "server"

        # Path-based entry (always — for localhost dev access)
        render_template "$APACHE_TMPL_DIR/server-site.conf.tmpl" \
            "SITE_NAME=$_name" \
            "PORT=$_port" \
            "LOG_DIR=$APACHE_LOG_DIR" \
            >> "$_default_file"
        printf '\n' >> "$_default_file"

        # VirtualHost entry (domain or subdomain)
        _domain="$(resolve_domain "$_name")" || true
        if [ -n "$_domain" ]; then
            render_template "$APACHE_TMPL_DIR/server-vhost.conf.tmpl" \
                "SITE_NAME=$_name" \
                "DOMAIN=$_domain" \
                "PORT=$_port" \
                "LOG_DIR=$APACHE_LOG_DIR" \
                >> "$_vhost_file"
            printf '\n' >> "$_vhost_file"
            success "  $_domain → proxy :$_port ($_name)"
        else
            success "  localhost/$_name → proxy :$_port (path-based only)"
        fi
    fi
done

# --- Assemble the final config ---
cat > "$_conf_file" <<APACHE_HEADER
# =============================================================================
#  Auto-generated by setup.sh — do not edit directly.
#  Regenerated by sites-watcher.sh when sites change.
#
#  Primary domain: ${PRIMARY_DOMAIN:-"(not configured)"}
#  Routing:
#    sites/maclong.dev/   → VirtualHost maclong.dev              (custom domain)
#    sites/api-thing/     → VirtualHost api-thing.${PRIMARY_DOMAIN:-"???"}  (subdomain)
#    All sites            → localhost/site-name/                  (path-based dev)
# =============================================================================

APACHE_HEADER

_has_vhosts=false
_has_defaults=false
[ -s "$_vhost_file" ] && _has_vhosts=true
[ -s "$_default_file" ] && _has_defaults=true

if [ "$_has_vhosts" = true ] || [ "$_has_defaults" = true ]; then

    # Default VirtualHost must come first (catches localhost + unmatched requests)
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

    # Domain / subdomain VirtualHosts
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
    success "  Wrote $CUSTOM_CONF (configtest passed)"
else
    warn "  New config failed configtest — rolling back"
    if [ -n "$_old_conf" ] && [ -f "$_old_conf" ]; then
        sudo cp "$_old_conf" "$CUSTOM_CONF"
        success "  Restored previous $CUSTOM_CONF"
    else
        sudo rm -f "$CUSTOM_CONF"
        warn "  Removed broken $CUSTOM_CONF (no previous config to restore)"
    fi
fi
rm -f "$_old_conf" 2>/dev/null

# =============================================================================
#  Step 9 — Initialise SQLite state database & assign server ports
# =============================================================================

info "Step 9/${TOTAL_STEPS}: Initialising state database & assigning ports"

db_init

# Migrate legacy flat files if they exist (first run after upgrade)
_legacy_ports="$STATE_DIR/port-assignments"
_legacy_state="$STATE_DIR/sites-state"

if [ -f "$_legacy_ports" ]; then
    db_import_port_assignments "$_legacy_ports"
    mv "$_legacy_ports" "${_legacy_ports}.migrated"
    success "  Migrated legacy port-assignments → database"
fi

if [ -f "$_legacy_state" ]; then
    db_import_sites_state "$_legacy_state"
    mv "$_legacy_state" "${_legacy_state}.migrated"
    success "  Migrated legacy sites-state → database"
fi

# Remove legacy PID directory and files (now tracked in the database)
if [ -d "$STATE_DIR/pids" ]; then
    rm -rf "$STATE_DIR/pids"
    success "  Removed legacy pids/ directory"
fi
rm -f "$STATE_DIR/server-manager.pid" "$STATE_DIR/restart-request" 2>/dev/null

# Ensure all discovered server sites have port assignments in the database
for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    _binary="$_dir/.build/release/Application"

    # Only server sites (have binary but no .output)
    [ -d "$_dir/.output" ] && continue
    [ ! -f "$_binary" ] && continue

    _port="$(db_get_port "$_name")"
    success "  Server: $_name → port $_port"
done

chmod +x "$SCRIPTS_DIR/restart-server.sh" 2>/dev/null || true
chmod +x "$SCRIPTS_DIR/server-manager.sh" 2>/dev/null || true
chmod +x "$SCRIPTS_DIR/sites-watcher.sh"  2>/dev/null || true
chmod +x "$SCRIPTS_DIR/backup.sh"         2>/dev/null || true

# =============================================================================
#  Step 10 — Configure Cloudflare tunnel (in-repo config, credentials off-repo)
# =============================================================================

info "Step 10/${TOTAL_STEPS}: Configuring Cloudflare tunnel"

mkdir -p "$HOME/.cloudflared"

_tunnel_config="$CLOUDFLARED_DIR/config.yml"

# Symlink ~/.cloudflared/config.yml → in-repo static config
if [ -L "$HOME/.cloudflared/config.yml" ] && \
   [ "$(readlink "$HOME/.cloudflared/config.yml")" = "$_tunnel_config" ]; then
    success "  ~/.cloudflared/config.yml already symlinked"
else
    if [ -e "$HOME/.cloudflared/config.yml" ] && [ ! -L "$HOME/.cloudflared/config.yml" ]; then
        mv "$HOME/.cloudflared/config.yml" "$HOME/.cloudflared/config.yml.bak.$(date +%Y%m%d%H%M%S)"
        warn "  Backed up existing ~/.cloudflared/config.yml"
    fi
    ln -sf "$_tunnel_config" "$HOME/.cloudflared/config.yml"
    success "  ~/.cloudflared/config.yml → $_tunnel_config"
fi

# Check if credentials are already in place
if [ -f "$HOME/.cloudflared/maclong.json" ]; then
    success "  Tunnel credentials found"
else
    warn "  No tunnel credentials at ~/.cloudflared/maclong.json"
    warn "  After setup, run:"
    warn "    cloudflared tunnel login"
    warn "    cloudflared tunnel create maclong --credentials-file ~/.cloudflared/maclong.json"
fi

# =============================================================================
#  Step 11 — Install log rotation (newsyslog)
# =============================================================================

info "Step 11/${TOTAL_STEPS}: Installing log rotation config"

_newsyslog_src="$NEWSYSLOG_DIR/com.mac9sb.conf"
_newsyslog_dest="/etc/newsyslog.d/com.mac9sb.conf"

if [ -f "$_newsyslog_src" ]; then
    sudo cp "$_newsyslog_src" "$_newsyslog_dest"
    sudo chown root:wheel "$_newsyslog_dest"
    sudo chmod 644 "$_newsyslog_dest"
    success "  Installed $_newsyslog_dest"
else
    warn "  newsyslog config not found at $_newsyslog_src"
fi

# =============================================================================
#  Step 12 — Symlink launchd agents
# =============================================================================

info "Step 12/${TOTAL_STEPS}: Symlinking launchd agents"

# All plists are static files with literal paths — symlinked for easy management.
# server-manager.plist  → supervises all server binaries (inferred from filesystem)
# sites-watcher.plist   → watches ~/Developer/sites and updates Apache config
# backup.plist          → daily SQLite backup to R2 at 03:00
# cloudflared.plist     → runs the Cloudflare tunnel (only if tunnel is configured)

_plist_list="server-manager.plist sites-watcher.plist backup.plist"

# Only install cloudflared agent if tunnel is configured
if [ -f "$HOME/.cloudflared/maclong.json" ]; then
    _plist_list="$_plist_list cloudflared.plist"
fi

for _plist_name in $_plist_list; do
    _src="$LAUNCHD_DIR/$_plist_name"

    if [ ! -f "$_src" ]; then
        warn "$_plist_name not found at $_src — skipping"
        continue
    fi

    _label="com.${GITHUB_USER}.${_plist_name%.plist}"
    _dest="$LAUNCH_AGENTS_DIR/${_label}.plist"

    # Unload if already running
    launchctl bootout "gui/${UID_NUM}/${_label}" 2>/dev/null || true

    # Symlink into LaunchAgents
    ln -sf "$_src" "$_dest"

    # Load the agent
    launchctl bootstrap "gui/${UID_NUM}" "$_dest" 2>/dev/null || launchctl load "$_dest" 2>/dev/null || true
    success "  $_label → symlinked and loaded"
done

# =============================================================================
#  Step 13 — Test & restart Apache
# =============================================================================

info "Step 13/${TOTAL_STEPS}: Testing and restarting Apache"

for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    if [ -d "$_dir/.output" ]; then
        chmod -R o+r "$_dir/.output" 2>/dev/null || true
        chmod o+x "$DEV_DIR" "$SITES_DIR" "$_dir" "$_dir/.output" 2>/dev/null || true
    fi
done

if sudo apachectl configtest 2>&1; then
    success "Apache configuration test passed"
    sudo apachectl restart
    success "Apache restarted"
else
    error "Apache configuration test failed — check $CUSTOM_CONF and $HTTPD_CONF"
fi

# =============================================================================
#  Step 14 — R2 backup credentials check
# =============================================================================

info "Step 14/${TOTAL_STEPS}: Checking backup prerequisites"

_r2_creds="$DEV_DIR/.env.local"
if [ -f "$_r2_creds" ]; then
    success "  R2 credentials found at $_r2_creds"
else
    warn "  R2 credentials not found at $_r2_creds"
    warn "  Daily backups will run but skip the R2 upload."
    warn "  To enable R2 uploads, create $_r2_creds with:"
    warn "    R2_ACCOUNT_ID=<account-id>"
    warn "    R2_ACCESS_KEY_ID=<access-key>"
    warn "    R2_SECRET_ACCESS_KEY=<secret-key>"
    warn "    R2_BUCKET=<bucket-name>"
fi

# =============================================================================
#  Summary
# =============================================================================

printf "\n"
printf "\033[1;32m=============================================================================\033[0m\n"
printf "\033[1;32m  Setup Complete!\033[0m\n"
printf "\033[1;32m=============================================================================\033[0m\n"
printf "\n"
printf "  \033[1mDotfiles:\033[0m        Symlinked from %s/\n" "$DOTFILES_DIR"
for _src in "$DOTFILES_DIR"/*; do
    [ ! -f "$_src" ] && continue
    _base="$(basename "$_src")"
    if [ "$_base" = "ssh_config" ]; then
        printf "    ~/.ssh/config → utilities/dotfiles/ssh_config\n"
    else
        printf "    ~/.%s → utilities/dotfiles/%s\n" "$_base" "$_base"
    fi
done
printf "\n"
printf "  \033[1mGit hooks:\033[0m       Installed from %s/\n" "$GITHOOKS_DIR"
printf "    pre-push → submodule hygiene check\n"
printf "\n"
printf "  \033[1mSites detected:\033[0m\n"

_any_sites=false
for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    _domain="$(resolve_domain "$_name")" || true
    if [ -d "$_dir/.output" ]; then
        if [ -n "$_domain" ]; then
            printf "    http://%s/  (static, VirtualHost)\n" "$_domain"
        else
            printf "    http://localhost/%s/  (static, path-based)\n" "$_name"
        fi
        _any_sites=true
    elif [ -f "$_dir/.build/release/Application" ]; then
        if [ -n "$_domain" ]; then
            printf "    http://%s/  (server → proxy, VirtualHost)\n" "$_domain"
        else
            printf "    http://localhost/%s/  (server → proxy, path-based)\n" "$_name"
        fi
        _any_sites=true
    else
        printf "    %s  (not yet built)\n" "$_name"
        _any_sites=true
    fi
done
if [ "$_any_sites" = false ]; then
    printf "    (none — add submodules under sites/)\n"
fi

printf "\n"
printf "  \033[1mTooling detected:\033[0m\n"
_any_tooling=false
for _dir in "$TOOLING_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    printf "    %s\n" "$_name"
    _any_tooling=true
done
if [ "$_any_tooling" = false ]; then
    printf "    (none — add submodules under tooling/)\n"
fi

printf "\n"
printf "  \033[1mLaunchd agents:\033[0m\n"
printf "    com.mac9sb.server-manager  — supervises all server binaries\n"
printf "    com.mac9sb.sites-watcher   — auto-detects new projects\n"
printf "    com.mac9sb.backup          — daily SQLite backup to R2 at 03:00\n"
if [ -f "$HOME/.cloudflared/maclong.json" ]; then
printf "    com.mac9sb.cloudflared     — Cloudflare tunnel (maclong)\n"
fi
printf "\n"
printf "  \033[1mLog rotation:\033[0m    newsyslog at /etc/newsyslog.d/com.mac9sb.conf\n"
printf "    Application logs: 5 × 1MB, bzip2 compressed\n"
printf "    Apache site logs: 5 × 1MB, bzip2 compressed\n"
printf "\n"
printf "  \033[1mPaths:\033[0m\n"
printf "    Apache logs:     %s/<site>-{error,access}.log\n" "$APACHE_LOG_DIR"
printf "    Server logs:     %s/<site>.{log,error.log}\n" "$LOG_DIR"
printf "    Apache config:   %s\n" "$CUSTOM_CONF"
printf "    HTTPD config:    %s\n" "$HTTPD_CONF"
printf "    Launchd agents:  %s/\n" "$LAUNCH_AGENTS_DIR"
printf "    State DB:        %s/state.db\n" "$STATE_DIR"
printf "    Backups:         %s/backups/\n" "$STATE_DIR"
printf "    Templates:       %s/\n" "$UTILITIES_DIR"
printf "\n"
printf "  \033[1mArchitecture:\033[0m\n"
printf "    Cloudflare Tunnel → Apache :80 → routes by domain/subdomain\n"
printf "    sites/maclong.dev/ (dot in name) → VirtualHost maclong.dev\n"
printf "    sites/api-thing/  (no dot)       → VirtualHost api-thing.%s\n" "$PRIMARY_DOMAIN"
printf "    All sites also accessible at localhost/site-name/ (dev)\n"
printf "    Static sites served directly from .output directories\n"
printf "    Server binaries reverse-proxied via mod_proxy\n"
printf "    WebSocket upgrades: handled via mod_proxy_wstunnel + mod_rewrite\n"
printf "    HTTPS terminated at Cloudflare edge, local traffic is HTTP\n"
printf "\n"
printf "  \033[1mCloudflare Tunnel:\033[0m  maclong\n"
printf "    Config:      %s/config.yml (in-repo, symlinked)\n" "$CLOUDFLARED_DIR"
if [ -f "$HOME/.cloudflared/maclong.json" ]; then
printf "    Credentials: ~/.cloudflared/maclong.json (off-repo)\n"
else
printf "    Credentials: not yet created\n"
printf "    Run: cloudflared tunnel login\n"
printf "         cloudflared tunnel create maclong --credentials-file ~/.cloudflared/maclong.json\n"
fi
printf "\n"
printf "  \033[1mSubmodules:\033[0m\n"
printf "    Repos are managed as git submodules — no config arrays needed.\n"
printf "    To add a new site:\n"
printf "      cd %s\n" "$DEV_DIR"
printf "      git submodule add https://github.com/%s/<repo>.git sites/<repo>\n" "$GITHUB_USER"
printf "    The sites-watcher will auto-detect and configure it.\n"
printf "\n"
printf "    To update submodules correctly:\n"
printf "      git submodule update --remote --merge\n"
printf "      git add sites/<name> && git commit\n"
printf "    Do NOT use 'git -C sites/<name> pull' — the pre-push hook will block it.\n"
printf "\n"
printf "  \033[1mNext steps:\033[0m\n"
_step=1
if [ ! -f "$HOME/.cloudflared/maclong.json" ]; then
printf "    %d. Set up Cloudflare tunnel (see above)\n" "$_step"
_step=$((_step + 1))
fi
if [ ! -f "$_r2_creds" ]; then
printf "    %d. Create %s for daily backup uploads\n" "$_step" "$_r2_creds"
_step=$((_step + 1))
fi
printf "    %d. Name site dirs as domains or subdomains (see README)\n" "$_step"
printf "\n"
printf "  \033[1mUseful commands:\033[0m\n"
printf "    sudo apachectl configtest && sudo apachectl restart\n"
printf "    launchctl list | grep %s\n" "$GITHUB_USER"
printf "    ~/Developer/utilities/scripts/restart-server.sh <server-name>\n"
printf "    tail -f %s/<site>.log\n" "$LOG_DIR"
printf "    git submodule status\n"
printf "    git submodule update --remote --merge\n"
printf "\n"
