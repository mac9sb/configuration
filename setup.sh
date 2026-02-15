#!/bin/sh
set -e

# =============================================================================
#  macOS Developer Environment Setup
#  Author: Mac (mac9sb)
#
#  This script sets up a complete development environment including:
#    - Touch ID for sudo
#    - Dotfiles (symlinked from utilities/dotfiles)
#    - SSH key generation
#    - Xcode CLI tools & Swift
#    - CLI tooling (cloudflared, gh, opencode)
#    - Git submodule initialization & hook installation
#    - Building Swift projects (with rollback preservation)
#    - Apache with mod_proxy/mod_rewrite/mod_headers
#    - Cloudflare tunnel config (in-repo config, credentials off-repo)
#    - Orchestrator daemon installation
#    - Launchd agents (backup, cloudflared)
#    - Log rotation via newsyslog
#
#  All runtime state is stored in a single SQLite database (WAL mode)
#  at ~/Library/Application Support/com.mac9sb/state.db — managed by
#  orchestrator for atomic, concurrent-safe access.
#
#  Repos are managed entirely as git submodules. No hardcoded arrays —
#  everything is derived from .gitmodules and filesystem state.
# =============================================================================

GITHUB_USER="mac9sb"
GIT_EMAIL="mac9sb@icloud.com"

PHASE=""
PLAN_MODE=0
DRY_RUN=0
RUN_USER_AFTER_ROOT="${RUN_USER_AFTER_ROOT:-0}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --phase=*)
            PHASE="${1#*=}"
            shift
            ;;
        --plan)
            PLAN_MODE=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

REAL_USER="${SUDO_USER:-$(id -un)}"
if [ "$REAL_USER" = "root" ]; then
    REAL_USER="$(/usr/bin/logname 2>/dev/null || /usr/bin/stat -f%Su /dev/console 2>/dev/null || echo root)"
fi
REAL_HOME="$(eval echo "~${REAL_USER}")"
if [ "$REAL_USER" = "root" ] && [ -n "${HOME:-}" ] && [ "$HOME" != "$REAL_HOME" ] && [ -d "$HOME" ]; then
    REAL_HOME="$HOME"
    REAL_USER="$(/usr/bin/stat -f%Su "$REAL_HOME" 2>/dev/null || echo "$REAL_USER")"
fi
REAL_GROUP="$(id -gn "${REAL_USER}" 2>/dev/null || echo staff)"

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

DEV_DIR="$REAL_HOME/Developer"
SITES_DIR="$DEV_DIR/sites"
TOOLING_DIR="$DEV_DIR/tooling"
UTILITIES_DIR="$DEV_DIR/utilities"
STATE_DIR="$REAL_HOME/Library/Application Support/com.mac9sb"
LOG_DIR="$REAL_HOME/Library/Logs/com.mac9sb"

HTTPD_CONF="/etc/apache2/httpd.conf"
CUSTOM_CONF="/etc/apache2/extra/custom.conf"
APACHE_LOG_DIR="/var/log/apache2/sites"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# --- Utility directories ---
DOTFILES_DIR="$UTILITIES_DIR/dotfiles"
GITHOOKS_DIR="$UTILITIES_DIR/githooks"
ORCH_RESOURCES="$TOOLING_DIR/orchestrator/Sources/OrchestratorCLI/Resources"
ORCH_LAUNCHD_DIR="$ORCH_RESOURCES/launchd"
ORCH_SCRIPTS_DIR="$ORCH_RESOURCES/scripts"
ORCH_CLOUDFLARED_DIR="$ORCH_RESOURCES/cloudflared"
ORCH_NEWSYSLOG_DIR="$ORCH_RESOURCES/newsyslog"

UID_NUM="$(id -u)"

# =============================================================================
#  Utility Functions
# =============================================================================

info()    { printf "\033[1;34m[INFO]\033[0m  %s\n" "$1"; }
success() { printf "\033[1;32m[OK]\033[0m    %s\n" "$1"; }
warn()    { printf "\033[1;33m[WARN]\033[0m  %s\n" "$1"; }
error()   { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1"; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

task() {
    _name="$1"
    _check_fn="$2"
    _apply_fn="$3"

    info "$_name"
    if "$_check_fn"; then
        success "  Already configured"
        return 0
    fi

    if [ "$PLAN_MODE" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
        warn "  Pending (plan mode)"
        return 0
    fi

    if "$_apply_fn"; then
        success "  Applied"
        return 0
    fi

    error "  Failed"
}

# Renders a template file by replacing {{KEY}} placeholders with values.
# Usage: render_template <template_file> KEY=value KEY2=value2 ...
# Output is written to stdout.
escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\\/&|]/\\&/g'
}

is_safe_identifier() {
    case "$1" in
        *[!A-Za-z0-9._-]*|'') return 1 ;;
        *) return 0 ;;
    esac
}

render_template() {
    _tmpl_file="$1"
    shift

    if [ ! -f "$_tmpl_file" ]; then
        error "Template not found: $_tmpl_file"
    fi

    _cmd="cat \"$_tmpl_file\""
    for _pair in "$@"; do
        _key="${_pair%%=*}"
        _val="${_pair#*=}"
        _val="$(escape_sed_replacement "$_val")"
        _cmd="$_cmd | perl -pe 's/\\Q{{${_key}}}\\E/${_val}/g'"
    done
    eval "$_cmd"
}

check_touch_id() {
    [ -f /etc/pam.d/sudo_local ] && grep -q "pam_tid.so" /etc/pam.d/sudo_local 2>/dev/null
}

apply_touch_id() {
    if [ ! -f /etc/pam.d/sudo_local ]; then
        cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
    fi
    sed -i '' 's/^#auth/auth/' /etc/pam.d/sudo_local
}

check_apache_system() {
    for _mod in mod_proxy.so mod_proxy_http.so mod_rewrite.so mod_proxy_wstunnel.so mod_headers.so; do
        grep -q "^LoadModule.*${_mod}" "$HTTPD_CONF" 2>/dev/null || return 1
    done

    grep -q "^ServerName localhost" "$HTTPD_CONF" 2>/dev/null || return 1
    grep -q "extra/custom.conf" "$HTTPD_CONF" 2>/dev/null || return 1
    [ -f "$CUSTOM_CONF" ] || return 1
    [ -d "$APACHE_LOG_DIR" ] || return 1
    [ -f "/etc/sudoers.d/mac9sb" ] || return 1
    return 0
}

apply_apache_system() {
    enable_module() {
        _mod="$1"
        if grep -q "^#.*${_mod}" "$HTTPD_CONF"; then
            sed -i '' "s|^#\\(.*$_mod\\)|\\1|" "$HTTPD_CONF"
        fi
    }

    cp "$HTTPD_CONF" "${HTTPD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    for _mod in mod_proxy.so mod_proxy_http.so mod_rewrite.so mod_proxy_wstunnel.so mod_headers.so; do
        enable_module "$_mod"
    done

    if grep -q "^#ServerName" "$HTTPD_CONF"; then
        sed -i '' 's|^#ServerName.*|ServerName localhost|' "$HTTPD_CONF"
    fi

    if ! grep -q "extra/custom.conf" "$HTTPD_CONF"; then
        printf "\n# Developer custom site configuration\nInclude /private/etc/apache2/extra/custom.conf\n" \
            >> "$HTTPD_CONF"
    fi

    mkdir -p "$APACHE_LOG_DIR"
    chown "${REAL_USER}:${REAL_GROUP}" "$APACHE_LOG_DIR"

    if [ ! -f "$CUSTOM_CONF" ]; then
        touch "$CUSTOM_CONF"
    fi
    chown "${REAL_USER}:${REAL_GROUP}" "$CUSTOM_CONF"

    _sudoers="/etc/sudoers.d/mac9sb"
    if [ ! -f "$_sudoers" ]; then
        printf '%s ALL=(root) NOPASSWD: /usr/sbin/apachectl configtest, /usr/sbin/apachectl restart\n' "${REAL_USER}" \
            > "$_sudoers"
        chmod 0440 "$_sudoers"
    fi
}

check_newsyslog() {
    [ -f "/etc/newsyslog.d/com.mac9sb.conf" ]
}

apply_newsyslog() {
    _newsyslog_src="$ORCH_NEWSYSLOG_DIR/com.mac9sb.conf"
    _newsyslog_dest="/etc/newsyslog.d/com.mac9sb.conf"

    if [ ! -f "$_newsyslog_src" ]; then
        warn "  newsyslog config not found at $_newsyslog_src"
        return 1
    fi

    render_template "$_newsyslog_src" \
        "HOME=$REAL_HOME" \
        "USER=$REAL_USER" \
        | sudo tee "$_newsyslog_dest" >/dev/null
    chown root:wheel "$_newsyslog_dest"
    chmod 644 "$_newsyslog_dest"
}

check_brew_bundle() {
    command_exists brew || return 1
    [ -f "$DEV_DIR/Brewfile" ] || return 1
    brew bundle check --file "$DEV_DIR/Brewfile" >/dev/null 2>&1
}

apply_brew_bundle() {
    if ! command_exists brew; then
        info "  Installing Homebrew (this may prompt for password)"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    if [ ! -f "$DEV_DIR/Brewfile" ]; then
        warn "  Brewfile not found at $DEV_DIR/Brewfile"
        return 1
    fi

    if ! brew bundle --file "$DEV_DIR/Brewfile"; then
        warn "  Brew bundle had errors; continuing"
        return 0
    fi
}

check_launch_agents() {
    _plist_list="backup.plist cloudflared.plist"
    for _plist_name in $_plist_list; do
        _label="com.${GITHUB_USER}.${_plist_name%.plist}"
        if ! launchctl list 2>/dev/null | grep -q "${_label}"; then
            return 1
        fi
    done
    return 0
}

apply_launch_agents() {
    _plist_list="backup.plist cloudflared.plist"
    for _plist_name in $_plist_list; do
        _label="com.${GITHUB_USER}.${_plist_name%.plist}"
        _dest="$LAUNCH_AGENTS_DIR/${_label}.plist"
        if [ ! -f "$_dest" ]; then
            warn "  Missing launch agent: $_dest"
            return 1
        fi

        if launchctl bootout "gui/${UID_NUM}/${_label}" 2>/dev/null; then
            success "  Stopped $_label"
        else
            warn "  $_label not loaded"
        fi

        if launchctl bootstrap "gui/${UID_NUM}" "$_dest" 2>/dev/null; then
            success "  Loaded $_label"
        else
            return 1
        fi
    done
}

check_orchestrator_daemon() {
    [ -f /Library/LaunchDaemons/com.mac9sb.orchestrator.plist ] || return 1
    launchctl list 2>/dev/null | grep -q "com.mac9sb.orchestrator"
}

apply_orchestrator_daemon() {
    [ -d "$TOOLING_DIR/orchestrator" ] || return 1
    _bin_path="$(cd "$TOOLING_DIR/orchestrator" && swift build -c release --show-bin-path)"
    if [ -z "$_bin_path" ] || [ ! -x "$_bin_path/orchestrator" ]; then
        warn "  orchestrator binary not found"
        return 1
    fi
    sudo -E HOME="$REAL_HOME" "$_bin_path/orchestrator" install-daemon --replace-legacy
}

check_apache_restart() {
    return 1
}

apply_apache_restart() {
    if sudo apachectl configtest >/dev/null 2>&1; then
        sudo apachectl restart
        return 0
    fi
    printf '\033[1;31m[FATAL]\033[0m Apache configtest failed — check %s and %s\n' "$CUSTOM_CONF" "$HTTPD_CONF" >&2
    return 1
}

run_root_phase() {
    # =============================================================================
    #  Step 1 — Touch ID for sudo
    # =============================================================================

    task "Touch ID for sudo" \
        check_touch_id \
        apply_touch_id

    # =============================================================================
    #  Step 8a — Configure Apache system settings
    # =============================================================================

    task "Apache system config" \
        check_apache_system \
        apply_apache_system

    # Log rotation is installed in the user phase (after submodules are available).
}

run_user_phase() {
    # =============================================================================
    #  Step 2 — Symlink Dotfiles
    # =============================================================================

    info "Symlinking dotfiles"

for _src in "$DOTFILES_DIR"/*; do
    [ ! -f "$_src" ] && continue
    _base="$(basename "$_src")"
    # ssh_config and settings.json are handled separately (nested directories)
    [ "$_base" = "ssh_config" ] && continue
    [ "$_base" = "settings.json" ] && continue
    _dest="$HOME/.${_base}"

    if [ -L "$_dest" ] && [ "$(readlink "$_dest")" = "$_src" ]; then
        success "  ~/.${_base} already symlinked"
    else
        if [ -e "$_dest" ] && [ ! -L "$_dest" ]; then
            mv "$_dest" "${_dest}.bak.$(date +%Y%m%d%H%M%S)"
            warn "  Backed up existing ~/.${_base}"
        fi
        ln -sf "$_src" "$_dest"
        success "  ~/.${_base} -> $_src"
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
        success "  ~/.ssh/config -> $_ssh_config_src"
    fi
fi

# =============================================================================
#  Step 3 — SSH key
# =============================================================================

info "SSH key"
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

info "Xcode Command Line Tools & Swift"
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

task "Homebrew bundle" \
    check_brew_bundle \
    apply_brew_bundle

# =============================================================================
#  Step 8 — Initialize git submodules & install hooks
# =============================================================================

info "Initializing git submodules & installing hooks"
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
    if [ "$UID_NUM" -eq 0 ]; then
        sudo -u "$REAL_USER" mkdir -p "$_hooks_dest"
        if ! chown -R "${REAL_USER}:${REAL_GROUP}" "$_hooks_dest" 2>/dev/null; then
            warn "  Could not chown $_hooks_dest to ${REAL_USER}:${REAL_GROUP}"
        fi
    else
        mkdir -p "$_hooks_dest"
    fi
    for _hook in "$GITHOOKS_DIR"/*; do
        [ ! -f "$_hook" ] && continue
        _hook_name="$(basename "$_hook")"
        if [ "$UID_NUM" -eq 0 ]; then
            if ! sudo -u "$REAL_USER" cp "$_hook" "$_hooks_dest/$_hook_name"; then
                warn "  Failed to install git hook: $_hook_name"
                continue
            fi
            sudo -u "$REAL_USER" chmod +x "$_hooks_dest/$_hook_name"
        else
            cp "$_hook" "$_hooks_dest/$_hook_name"
            chmod +x "$_hooks_dest/$_hook_name"
        fi
        success "  Installed git hook: $_hook_name"
    done
else
    warn "No githooks directory found at $GITHOOKS_DIR"
fi

# =============================================================================
#  Step 9 — Install log rotation (newsyslog)
# =============================================================================

task "Installing log rotation config" \
    check_newsyslog \
    apply_newsyslog

# =============================================================================
#  Step 10 — Build Swift projects (with rollback preservation)
# =============================================================================

info "Building Swift projects"

# Build any Swift package found under tooling/
for _dir in "$TOOLING_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    if [ -f "$_dir/Package.swift" ]; then
        info "  Building tooling: $_name..."
        _build_log="$(mktemp)"
        if (cd "$_dir" && swift build -c release > "$_build_log" 2>&1); then
            tail -1 "$_build_log"
            success "  $_name built (release)"
        else
            tail -5 "$_build_log"
            warn "  $_name build failed"
        fi
        rm -f "$_build_log"
    fi
done

# Build any Swift package found under sites/
# All sites are built in release mode. After building, the binary is run
# with a timeout to classify:
#   - Exits cleanly and produces .output -> static site
#   - Does not exit within the timeout   -> server (launchd will manage)
for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    if ! is_safe_identifier "$_name"; then
        warn "  $_name: invalid site name — skipping"
        continue
    fi
    if [ -f "$_dir/Package.swift" ]; then
        info "  Building site: $_name (release)..."
        _build_log="$(mktemp)"
        if (cd "$_dir" && swift build -c release > "$_build_log" 2>&1); then
            tail -1 "$_build_log"
            success "  $_name built (release)"
        else
            tail -5 "$_build_log"
            warn "  $_name build failed"
        fi
        rm -f "$_build_log"
    fi
done

# =============================================================================
#  Step 11 — Prepare Apache placeholder (orchestrator manages config)
# =============================================================================

info "Preparing Apache config placeholder"

mkdir -p "$STATE_DIR" "$LOG_DIR"
chown -R "${REAL_USER}:${REAL_GROUP}" "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true

cat > "$CUSTOM_CONF" <<'APACHE_HEADER'
# =============================================================================
#  Auto-generated by setup.sh — orchestrator will populate this file.
# =============================================================================
APACHE_HEADER

success "  Wrote $CUSTOM_CONF"

chmod +x "$ORCH_SCRIPTS_DIR/backup.sh" 2>/dev/null || true

# =============================================================================
#  Step 12 — Configure Cloudflare tunnel (in-repo config, credentials off-repo)
# =============================================================================

info "Configuring Cloudflare tunnel"

mkdir -p "$HOME/.cloudflared"

_tunnel_config="$ORCH_CLOUDFLARED_DIR/config.yml"
_tunnel_dest="$HOME/.cloudflared/config.yml"

# Render ~/.cloudflared/config.yml from in-repo template
if [ -L "$_tunnel_dest" ]; then
    rm -f "$_tunnel_dest"
fi
if [ -e "$_tunnel_dest" ] && [ ! -L "$_tunnel_dest" ]; then
    mv "$_tunnel_dest" "$_tunnel_dest.bak.$(date +%Y%m%d%H%M%S)"
    warn "  Backed up existing ~/.cloudflared/config.yml"
fi
render_template "$_tunnel_config" "HOME=$HOME" > "$_tunnel_dest"
success "  Wrote $_tunnel_dest from template"

# Ensure ~/.cloudflared and ~/.ssh are owned by the real user (setup runs as sudo)
chown -R "${REAL_USER}:${REAL_GROUP}" "$HOME/.cloudflared"
[ -d "$HOME/.ssh" ] && chown -R "${REAL_USER}:${REAL_GROUP}" "$HOME/.ssh"

# Check if credentials are already in place
if [ -f "$HOME/.cloudflared/maclong.json" ]; then
    success "  Tunnel credentials found"
    
    # Configure DNS routes for the tunnel
    if command_exists cloudflared; then
        # Extract primary domain from config
        _primary_domain="$(grep "^# primary-domain:" "$_tunnel_config" 2>/dev/null | awk '{print $3}')"
        CLOUDFLARED_AUTO_DNS="${CLOUDFLARED_AUTO_DNS:-1}"
        if [ -n "$_primary_domain" ] && [ "$CLOUDFLARED_AUTO_DNS" != "0" ]; then
            # Add root domain route
            if cloudflared tunnel route dns -f maclong "${_primary_domain}" 2>/dev/null; then
                success "  Added DNS route: ${_primary_domain}"
            else
                true
            fi
            # Add wildcard route (covers all subdomains)
            if cloudflared tunnel route dns -f maclong "*.${_primary_domain}" 2>/dev/null; then
                success "  Added DNS route: *.${_primary_domain}"
            else
                true
            fi
            
            # Add route for each custom domain site (non-subdomain sites)
            for _dir in "$SITES_DIR"/*/; do
                [ ! -d "$_dir" ] && continue
                _name="$(basename "$_dir")"
                _domain="$(resolve_domain "$_name")" || continue
                
                # Skip if it's a subdomain (covered by wildcard)
                if ! echo "$_domain" | grep -q "\.${_primary_domain}\$"; then
                    if cloudflared tunnel route dns -f maclong "$_domain" 2>/dev/null; then
                        success "  Added DNS route: $_domain"
                    else
                        true
                    fi
                fi
            done
        elif [ "$CLOUDFLARED_AUTO_DNS" = "0" ]; then
            warn "  Skipping DNS route updates (CLOUDFLARED_AUTO_DNS=0)"
        fi
    fi
else
    warn "  No tunnel credentials at ~/.cloudflared/maclong.json"
    warn "  New tunnel:"
    warn "    cloudflared tunnel login"
    warn "    cloudflared tunnel create --credentials-file ~/.cloudflared/maclong.json maclong"
    warn "  Existing tunnel:"
    warn "    cloudflared tunnel login"
    warn "    cloudflared tunnel token --cred-file ~/.cloudflared/maclong.json maclong"
fi

# =============================================================================
#  Step 13 — Render launchd agents (loaded in Phase C)
# =============================================================================

info "Rendering launchd agents"

# All plists are templates with literal paths — rendered per-user into LaunchAgents.
# backup.plist      -> daily SQLite backup to R2 at 03:00
# cloudflared.plist -> runs the Cloudflare tunnel (only if tunnel is configured)

_plist_list="backup.plist cloudflared.plist"

for _plist_name in $_plist_list; do
    _src="$ORCH_LAUNCHD_DIR/$_plist_name"

    if [ ! -f "$_src" ]; then
        warn "$_plist_name not found at $_src — skipping"
        continue
    fi

    _label="com.${GITHUB_USER}.${_plist_name%.plist}"
    _dest="$LAUNCH_AGENTS_DIR/${_label}.plist"

    # Render into LaunchAgents
    render_template "$_src" \
        "HOME=$HOME" \
        "USER=${REAL_USER}" \
        > "$_dest"

    success "  $_label -> rendered"
done

# =============================================================================
#  Step 14 — Test & restart Apache
# =============================================================================

info "Fixing directory permissions for Apache"

# Apache (_www user) needs execute permission on parent directories to access site files
_user_home="$(dirname "$DEV_DIR")"
if [ ! -x "$_user_home" ] || [ ! -x "$DEV_DIR" ]; then
    chmod +x "$_user_home" 2>/dev/null || true
    chmod +x "$DEV_DIR" 2>/dev/null || true
    success "  Fixed execute permissions on $_user_home and $DEV_DIR"
fi

# Fix ownership of .build directories (might be owned by root from sudo builds)
for _dir in "$SITES_DIR"/*/ "$TOOLING_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    if [ -d "$_dir/.build" ]; then
        _owner="$(stat -f '%Su' "$_dir/.build" 2>/dev/null || echo 'unknown')"
        if [ "$_owner" = "root" ]; then
            sudo chown -R "${REAL_USER}:${REAL_GROUP}" "$_dir/.build" 2>/dev/null || true
            success "  Fixed ownership of $_dir/.build (was root)"
        fi
    fi
done

# Ensure .output directories are readable by Apache
for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    if [ -d "$_dir/.output" ]; then
        _owner="$(stat -f '%Su' "$_dir/.output" 2>/dev/null || echo 'unknown')"
        if [ "$_owner" = "root" ]; then
            sudo chown -R "${REAL_USER}:${REAL_GROUP}" "$_dir/.output" 2>/dev/null || true
        fi
        chmod -R o+rX "$_dir/.output" 2>/dev/null || true
        chmod o+x "$SITES_DIR" "$_dir" "$_dir/.output" 2>/dev/null || true
    fi
done
success "  Directory permissions configured for Apache access"

# =============================================================================
#  Step 15 — R2 backup credentials check
# =============================================================================

info "Checking backup prerequisites"

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

}

run_services_phase() {
    # =============================================================================
    #  Phase C — Start/restart services
    # =============================================================================

    task "Installing orchestrator daemon" \
        check_orchestrator_daemon \
        apply_orchestrator_daemon

    task "Loading launchd agents" \
        check_launch_agents \
        apply_launch_agents

    task "Testing and restarting Apache" \
        check_apache_restart \
        apply_apache_restart
}

run_summary() {
    # =============================================================================
    #  Summary
    # =============================================================================

    printf "\n"
    printf "\033[1;32m=============================================================================\033[0m\n"
    printf "\033[1;32m  Setup Complete!\033[0m\n"
    printf "\033[1;32m=============================================================================\033[0m\n"
    printf "\n"
    printf "  \033[1mSites:\033[0m\n"

_any_sites=false
_primary_domain=""
if [ -f "$ORCH_CLOUDFLARED_DIR/config.yml" ]; then
    _primary_domain="$(sed -n 's/^# *primary-domain: *//p' "$ORCH_CLOUDFLARED_DIR/config.yml" | head -1 | tr -d '[:space:]')"
fi
for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    _domain=""
    case "$_name" in
        *.*) _domain="$_name" ;;
        *) [ -n "$_primary_domain" ] && _domain="${_name}.${_primary_domain}" ;;
    esac
    if [ -d "$_dir/.output" ]; then
        if [ -n "$_domain" ]; then
            printf "    ✓ %s -> static (http://%s/)\n" "$_name" "$_domain"
        else
            printf "    ✓ %s -> static (http://localhost/%s/)\n" "$_name" "$_name"
        fi
        _any_sites=true
    elif [ -f "$_dir/Package.swift" ]; then
        if [ -n "$_domain" ]; then
            printf "    ✓ %s -> server (http://%s/)\n" "$_name" "$_domain"
        else
            printf "    ✓ %s -> server (http://localhost/%s/)\n" "$_name" "$_name"
        fi
        _any_sites=true
    else
        printf "    ✗ %s (not yet built)\n" "$_name"
        _any_sites=true
    fi
done
if [ "$_any_sites" = false ]; then
    printf "    (none — add submodules under sites/)\n"
fi

printf "\n"

}

phase_args=""
[ "$PLAN_MODE" -eq 1 ] && phase_args="$phase_args --plan"
[ "$DRY_RUN" -eq 1 ] && phase_args="$phase_args --dry-run"

if [ -z "$PHASE" ]; then
    if [ "$UID_NUM" -eq 0 ]; then
        run_root_phase
        sudo -u "$REAL_USER" -H "$0" --phase user $phase_args
        exit 0
    fi

    RUN_USER_AFTER_ROOT=1 sudo -E "$0" --phase root $phase_args
    exit $?
fi

case "$PHASE" in
    root)
        if [ "$UID_NUM" -ne 0 ]; then
            error "Root phase requires sudo."
        fi
        run_root_phase
        if [ "$RUN_USER_AFTER_ROOT" = "1" ]; then
            sudo -u "$REAL_USER" -H "$0" --phase user $phase_args
        fi
        ;;
    user)
        if [ "$UID_NUM" -eq 0 ]; then
            error "User phase must not run as root."
        fi
        run_user_phase
        run_services_phase
        run_summary
        ;;
    *)
        error "Unknown phase: $PHASE"
        ;;
esac
printf "  \033[1mTooling:\033[0m\n"
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

# --- Action items (only print sections that need attention) ---
_has_actions=false

if [ ! -f "$HOME/.cloudflared/maclong.json" ]; then
    if [ "$_has_actions" = false ]; then
        printf "\n"
        printf "  \033[1mAction required:\033[0m\n"
        _has_actions=true
    fi
    cat <<'EOF'
    • Set up Cloudflare tunnel:
      New tunnel:
        cloudflared tunnel login
        cloudflared tunnel create --credentials-file ~/.cloudflared/maclong.json maclong
      Existing tunnel:
        cloudflared tunnel login
        cloudflared tunnel token --cred-file ~/.cloudflared/maclong.json maclong
EOF
fi

if [ ! -f "$_r2_creds" ]; then
    if [ "$_has_actions" = false ]; then
        printf "\n"
        printf "  \033[1mAction required:\033[0m\n"
        _has_actions=true
    fi
    printf "    • Create %s for daily R2 backups\n" "$_r2_creds"
fi

printf "\n"
