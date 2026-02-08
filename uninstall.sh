#!/bin/sh
set -e

# =============================================================================
#  macOS Developer Environment Teardown
#  Author: Mac (maclong9)
#
#  This script reverses the setup performed by setup.sh:
#    - Stops server-manager and unloads all symlinked launchd agents
#    - Removes Apache custom config and restores httpd.conf backup
#    - Removes SQLite state database, backups, and logs from ~/Library/
#    - Removes dotfile symlinks (preserves source files in utilities/)
#    - Removes Cloudflare tunnel directory (~/.cloudflared)
#    - Removes log rotation config (newsyslog)
#    - Removes git hooks
#    - Optionally removes installed CLI tools (cloudflared)
#
#  Usage: sudo ./uninstall.sh [--all]
#    --all    Also remove cloudflared and Xcode CLI tools
# =============================================================================

GITHUB_USER="mac9sb"
DEV_DIR="$HOME/Developer"
SITES_DIR="$DEV_DIR/sites"
UTILITIES_DIR="$DEV_DIR/utilities"
SCRIPTS_DIR="$UTILITIES_DIR/scripts"
DOTFILES_DIR="$UTILITIES_DIR/dotfiles"
STATE_DIR="$HOME/Library/Application Support/com.mac9sb"
APP_LOG_DIR="$HOME/Library/Logs/com.mac9sb"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
HTTPD_CONF="/etc/apache2/httpd.conf"
CUSTOM_CONF="/etc/apache2/extra/custom.conf"
APACHE_LOG_DIR="/var/log/apache2/sites"

# Source shared helpers for get_exec_name()
. "$SCRIPTS_DIR/db.sh"

UID_NUM="$(id -u)"
REMOVE_TOOLS=false

for _arg in "$@"; do
    case "$_arg" in
        --all) REMOVE_TOOLS=true ;;
    esac
done

# =============================================================================
#  Utility Functions
# =============================================================================

info()    { printf "\033[1;34m[INFO]\033[0m  %s\n" "$1"; }
success() { printf "\033[1;32m[OK]\033[0m    %s\n" "$1"; }
warn()    { printf "\033[1;33m[WARN]\033[0m  %s\n" "$1"; }

confirm() {
    printf "\033[1;33m%s [y/N] \033[0m" "$1"
    read -r _answer
    case "$_answer" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# =============================================================================
#  Confirmation
# =============================================================================

printf '\n\033[1;31m=============================================================================\033[0m\n'
printf '\033[1;31m  Developer Environment Teardown\033[0m\n'
printf '\033[1;31m=============================================================================\033[0m\n'

cat <<EOF

  This will:
    - Stop server-manager and all managed server processes
    - Unload and remove all symlinked launchd agents
      (server-manager, sites-watcher, backup, cloudflared)
    - Remove Apache custom site configuration
    - Remove SQLite state database ($STATE_DIR/state.db)
    - Remove local backups ($STATE_DIR/backups/)
    - Remove application logs ($APP_LOG_DIR)
    - Remove dotfile symlinks (~/.zshrc, ~/.vimrc, ~/.config/zed/settings.json, etc.)
    - Remove Cloudflare tunnel directory (~/.cloudflared)
    - Remove passwordless sudo for apachectl (/etc/sudoers.d/mac9sb)
    - Remove log rotation config (/etc/newsyslog.d/com.mac9sb.conf)
    - Remove git hooks (.git/hooks/pre-push)
    - Remove Apache site log directory ($APACHE_LOG_DIR)
EOF
[ "$REMOVE_TOOLS" = true ] && printf '    - Remove cloudflared from /usr/local/bin\n'

cat <<'EOF'

  This will NOT:
    - Delete submodule source code (sites/, tooling/)
    - Delete template/script files (utilities/)
    - Delete SSH keys (~/.ssh/id_ed25519)
    - Delete R2 credentials (.env.local)
    - Modify the git repository itself

EOF

if ! confirm "Proceed with teardown?"; then
    info "Teardown cancelled."
    exit 0
fi

printf "\n"

# =============================================================================
#  Step 1 — Unload and remove launchd agents
# =============================================================================

info "Step 1/8: Removing launchd agents"

# Stop the server-manager first (it will SIGTERM all child server processes)
for _agent_name in server-manager sites-watcher backup cloudflared; do
    _label="com.${GITHUB_USER}.${_agent_name}"
    _plist="${LAUNCH_AGENTS_DIR}/${_label}.plist"
    if [ -f "$_plist" ] || [ -L "$_plist" ]; then
        launchctl bootout "gui/${UID_NUM}/${_label}" 2>/dev/null || true
        rm -f "$_plist"
        success "Stopped and removed ${_agent_name} agent"
    fi
done

# Remove any leftover per-site agents from previous installs
for _plist in "${LAUNCH_AGENTS_DIR}"/com.${GITHUB_USER}.*.plist; do
    [ ! -f "$_plist" ] && [ ! -L "$_plist" ] && continue
    _label="$(basename "$_plist" .plist)"
    launchctl bootout "gui/${UID_NUM}/${_label}" 2>/dev/null || true
    rm -f "$_plist"
    success "  Removed legacy agent: $_label"
done

success "All launchd agents removed"

# =============================================================================
#  Step 2 — Remove watcher runtime state and backups
# =============================================================================

info "Step 2/8: Removing state database, backups, and logs"

if [ -d "$STATE_DIR" ]; then
    # Remove SQLite database and any WAL/SHM files
    rm -f "$STATE_DIR/state.db" "$STATE_DIR/state.db-wal" "$STATE_DIR/state.db-shm"
    # Remove any legacy flat files and migrated backups
    rm -f "$STATE_DIR/port-assignments" "$STATE_DIR/port-assignments.migrated"
    rm -f "$STATE_DIR/sites-state" "$STATE_DIR/sites-state.migrated"
    rm -f "$STATE_DIR/server-manager.pid" "$STATE_DIR/restart-request"
    rm -rf "$STATE_DIR/pids"
    # Remove backup archives
    rm -rf "$STATE_DIR/backups"
    # Remove the directory if empty
    rmdir "$STATE_DIR" 2>/dev/null || rm -rf "$STATE_DIR"
    success "Removed $STATE_DIR"
else
    success "No state database to remove"
fi

if [ -d "$APP_LOG_DIR" ]; then
    rm -rf "$APP_LOG_DIR"
    success "Removed $APP_LOG_DIR"
else
    success "No application logs to remove"
fi

# =============================================================================
#  Step 3 — Remove Apache custom configuration
# =============================================================================

info "Step 3/8: Removing Apache custom configuration"

# Remove the custom.conf file
if [ -f "$CUSTOM_CONF" ]; then
    sudo rm -f "$CUSTOM_CONF"
    success "Removed $CUSTOM_CONF"
fi

# Remove the Include line and revert httpd.conf modifications
if grep -q "extra/custom.conf" "$HTTPD_CONF" 2>/dev/null || \
   grep -q "^ServerName localhost" "$HTTPD_CONF" 2>/dev/null; then
    sudo cp "$HTTPD_CONF" "${HTTPD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    sudo sed -i '' '/# Developer custom site configuration/d' "$HTTPD_CONF"
    sudo sed -i '' '/Include.*extra\/custom\.conf/d' "$HTTPD_CONF"
    success "Removed custom.conf Include from httpd.conf"

    # Revert ServerName to commented default
    if grep -q "^ServerName localhost" "$HTTPD_CONF"; then
        sudo sed -i '' 's|^ServerName localhost|#ServerName www.example.com:80|' "$HTTPD_CONF"
        success "Reverted ServerName to default"
    fi

    # Re-comment proxy/rewrite/headers modules enabled by setup
    for _mod in mod_proxy.so mod_proxy_http.so mod_rewrite.so mod_proxy_wstunnel.so mod_headers.so; do
        if grep -q "^LoadModule.*${_mod}" "$HTTPD_CONF"; then
            sudo sed -i '' "s|^\(LoadModule.*${_mod}\)|#\1|" "$HTTPD_CONF"
        fi
    done
    success "Re-commented proxy/rewrite/headers modules"
fi

# Remove site log directory
if [ -d "$APACHE_LOG_DIR" ]; then
    sudo rm -rf "$APACHE_LOG_DIR"
    success "Removed $APACHE_LOG_DIR"
fi

# Test and restart Apache to apply changes
if sudo apachectl configtest >/dev/null 2>&1; then
    sudo apachectl restart
    success "Apache restarted with clean configuration"
else
    warn "Apache config test failed after cleanup — may need manual fix"
fi

# =============================================================================
#  Step 4 — Remove dotfile symlinks
# =============================================================================

info "Step 4/8: Removing dotfile symlinks"

for _dotfile in zshrc vimrc gitignore gitconfig; do
    _src="$DOTFILES_DIR/$_dotfile"
    _dest="$HOME/.${_dotfile}"

    if [ -L "$_dest" ] && [ "$(readlink "$_dest")" = "$_src" ]; then
        rm -f "$_dest"
        success "  Removed ~/.${_dotfile} symlink"

        # Restore backup if one exists (find most recent)
        _backup=""
        for _bak in "${_dest}".bak.*; do
            [ -f "$_bak" ] && _backup="$_bak"
        done
        if [ -n "$_backup" ]; then
            mv "$_backup" "$_dest"
            success "  Restored ~/.${_dotfile} from backup"
        fi
    elif [ -L "$_dest" ]; then
        warn "  ~/.${_dotfile} is a symlink but points elsewhere — skipping"
    else
        success "  ~/.${_dotfile} is not our symlink — skipping"
    fi
done

# SSH config
_ssh_config_src="$DOTFILES_DIR/ssh_config"
_ssh_config_dest="$HOME/.ssh/config"
if [ -L "$_ssh_config_dest" ] && [ "$(readlink "$_ssh_config_dest")" = "$_ssh_config_src" ]; then
    rm -f "$_ssh_config_dest"
    success "  Removed ~/.ssh/config symlink"

    _backup=""
    for _bak in "${_ssh_config_dest}".bak.*; do
        [ -f "$_bak" ] && _backup="$_bak"
    done
    if [ -n "$_backup" ]; then
        mv "$_backup" "$_ssh_config_dest"
        success "  Restored ~/.ssh/config from backup"
    fi
elif [ -L "$_ssh_config_dest" ]; then
    warn "  ~/.ssh/config is a symlink but points elsewhere — skipping"
else
    success "  ~/.ssh/config is not our symlink — skipping"
fi

# Zed editor settings
_zed_settings_src="$DOTFILES_DIR/settings.json"
_zed_settings_dest="$HOME/.config/zed/settings.json"
if [ -L "$_zed_settings_dest" ] && [ "$(readlink "$_zed_settings_dest")" = "$_zed_settings_src" ]; then
    rm -f "$_zed_settings_dest"
    success "  Removed ~/.config/zed/settings.json symlink"

    _backup=""
    for _bak in "${_zed_settings_dest}".bak.*; do
        [ -f "$_bak" ] && _backup="$_bak"
    done
    if [ -n "$_backup" ]; then
        mv "$_backup" "$_zed_settings_dest"
        success "  Restored ~/.config/zed/settings.json from backup"
    fi
elif [ -L "$_zed_settings_dest" ]; then
    warn "  ~/.config/zed/settings.json is a symlink but points elsewhere — skipping"
else
    success "  ~/.config/zed/settings.json is not our symlink — skipping"
fi

# =============================================================================
#  Step 5 — Remove Cloudflare tunnel config symlink & log rotation & git hooks
# =============================================================================

info "Step 5/8: Removing tunnel config, log rotation, and git hooks"

# Cloudflare tunnel directory (credentials, config, cert)
if [ -d "$HOME/.cloudflared" ]; then
    rm -rf "$HOME/.cloudflared"
    success "  Removed ~/.cloudflared (config, credentials, cert)"
else
    success "  No ~/.cloudflared directory to remove"
fi

# Passwordless sudo for apachectl
_sudoers="/etc/sudoers.d/mac9sb"
if [ -f "$_sudoers" ]; then
    sudo rm -f "$_sudoers"
    success "  Removed $_sudoers"
else
    success "  No sudoers config to remove"
fi

# Log rotation (newsyslog)
_newsyslog="/etc/newsyslog.d/com.mac9sb.conf"
if [ -f "$_newsyslog" ]; then
    sudo rm -f "$_newsyslog"
    success "  Removed $_newsyslog"
else
    success "  No newsyslog config to remove"
fi

# Git hooks
_hooks_dir="$DEV_DIR/.git/hooks"
for _hook_name in pre-push; do
    _hook_file="$_hooks_dir/$_hook_name"
    if [ -f "$_hook_file" ]; then
        rm -f "$_hook_file"
        success "  Removed git hook: $_hook_name"
    fi
done

# =============================================================================
#  Step 6 — Remove Touch ID for sudo (optional)
# =============================================================================

info "Step 6/8: Touch ID for sudo"

if [ -f /etc/pam.d/sudo_local ] && grep -q "pam_tid.so" /etc/pam.d/sudo_local 2>/dev/null; then
    if confirm "  Remove Touch ID for sudo?"; then
        sudo rm -f /etc/pam.d/sudo_local
        success "  Touch ID for sudo removed"
    else
        success "  Touch ID for sudo kept"
    fi
else
    success "  Touch ID for sudo not configured — nothing to remove"
fi

# =============================================================================
#  Step 7 — Remove last-known-good binaries
# =============================================================================

info "Step 7/8: Cleaning up rollback binaries"

_cleaned_binaries=0
for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _exec_name="$(get_exec_name "$_dir")" || true
    [ -z "$_exec_name" ] && continue
    for _suffix in .run .bak .last-good; do
        for _file in \
            "$_dir/.build/release/${_exec_name}${_suffix}" \
            "$_dir"/.build/*/release/"${_exec_name}${_suffix}"; do
            if [ -f "$_file" ]; then
                rm -f "$_file"
                _cleaned_binaries=$((_cleaned_binaries + 1))
            fi
        done
    done
done

if [ "$_cleaned_binaries" -gt 0 ]; then
    success "  Removed $_cleaned_binaries rollback/run binary file(s)"
else
    success "  No rollback binaries to remove"
fi

# =============================================================================
#  Step 8 — Remove CLI tools (only with --all)
# =============================================================================

info "Step 8/8: CLI tools"

if [ "$REMOVE_TOOLS" = true ]; then
    if [ -f /usr/local/bin/cloudflared ]; then
        sudo rm -f /usr/local/bin/cloudflared
        success "  Removed cloudflared"
    fi

    success "CLI tools removed"
else
    info "  Skipping CLI tool removal (use --all to include)"
fi

# =============================================================================
#  Summary
# =============================================================================

printf '\n\033[1;32m=============================================================================\033[0m\n'
printf '\033[1;32m  Teardown Complete\033[0m\n'
printf '\033[1;32m=============================================================================\033[0m\n'

printf '\n  \033[1mRemoved:\033[0m\n'
cat <<EOF
    - launchd agents from $LAUNCH_AGENTS_DIR/
      (server-manager, sites-watcher, backup, cloudflared)
    - Application state from $STATE_DIR/
    - Local backup archives from $STATE_DIR/backups/
    - Application logs from $APP_LOG_DIR/
    - Apache config ($CUSTOM_CONF)
    - Dotfile symlinks
    - Cloudflare tunnel directory (~/.cloudflared)
    - Passwordless sudo for apachectl (/etc/sudoers.d/mac9sb)
    - Log rotation config (/etc/newsyslog.d/com.mac9sb.conf)
    - Git hooks (pre-push)
    - Rollback binaries (*.run, *.bak)
EOF
[ "$REMOVE_TOOLS" = true ] && printf '    - CLI tools (cloudflared)\n'

printf '\n  \033[1mPreserved:\033[0m\n'
cat <<EOF
    - Source code in sites/, tooling/
    - Templates and scripts in utilities/
    - Dotfile sources in utilities/dotfiles/
    - SSH keys in ~/.ssh/
    - R2 credentials (.env.local)
    - Git repository and submodule configuration

  To re-setup: sudo ./setup.sh
  To fully remove: rm -rf $DEV_DIR

EOF
