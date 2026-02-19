#!/bin/sh

# ── Developer Environment Teardown ─────────────────────────────────────────
# Removes agents, state, configs, and selected files created by `setup.sh`.
set -e

UTILITIES_DIR="${UTILITIES_DIR:-$HOME/Developer/utilities}"
UTILS="$UTILITIES_DIR/utils.sh"
if [ -f "$UTILS" ]; then
    . "$UTILS"
else
    echo "[ERROR] Utility script not found: $UTILS"
    exit 1
fi

parse_args "$@"

REMOVE_TOOLS="${ALL:-false}"

resolve_paths

printf '\n\033[1;31m───────────────────────────────────────────────────────────────────────────────\033[0m\n'
printf '\033[1;31m  Developer Environment Teardown\033[0m\n'
printf '\033[1;31m───────────────────────────────────────────────────────────────────────────────\033[0m\n'

cat <<EOF

  This will:
    - Stop orchestrator and unload legacy launchd agents
    - Unload and remove all symlinked launchd agents
      (legacy agents + backup, cloudflared)
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
[ "$REMOVE_TOOLS" = true ] && printf '    - Remove Homebrew CLI tools (cloudflared, gh, opencode)\n'

cat <<'EOF'

  This will NOT:
    - Delete submodule source code (sites/, tooling/)
    - Delete orchestrator resource templates/scripts (tooling/orchestrator/Sources/OrchestratorCLI/Resources/)
    - Delete SSH keys (~/.ssh/id_ed25519)
    - Delete R2 credentials (.env.local)
    - Modify the git repository itself

EOF

if ! confirm "Proceed with teardown?"; then
    info "Teardown cancelled."
    exit 0
fi

printf "\n"

info "Step 1/8: Removing launchd agents"

# Remove known user LaunchAgents and any matching legacy plists
for _agent_name in server-manager sites-watcher backup cloudflared; do
    _label="com.${GITHUB_USER}.${_agent_name}"
    _plist="${LAUNCH_AGENTS_DIR}/${_label}.plist"
    if [ -f "$_plist" ] || [ -L "$_plist" ]; then
        launchctl bootout "gui/${UID_NUM}/${_label}" 2>/dev/null || true
        rm -f "$_plist"
        success "Stopped and removed ${_agent_name} agent"
    fi
done

for _plist in "${LAUNCH_AGENTS_DIR}"/com.${GITHUB_USER}.*.plist; do
    [ ! -f "$_plist" ] && [ ! -L "$_plist" ] && continue
    _label="$(basename "$_plist" .plist)"
    launchctl bootout "gui/${UID_NUM}/${_label}" 2>/dev/null || true
    rm -f "$_plist"
    success "  Removed legacy agent: $_label"
done

success "All launchd agents removed"

# Remove system daemon and binary if present
if [ -f "/Library/LaunchDaemons/com.mac9sb.orchestrator.plist" ]; then
    sudo launchctl bootout system /Library/LaunchDaemons/com.mac9sb.orchestrator.plist 2>/dev/null || true
    sudo rm -f /Library/LaunchDaemons/com.mac9sb.orchestrator.plist
    success "Stopped and removed orchestrator daemon"
fi

if [ -f "/usr/local/bin/orchestrator" ]; then
    sudo rm -f /usr/local/bin/orchestrator
    success "Removed /usr/local/bin/orchestrator"
fi

task "Removing launchd agents" check_launch_agents apply_launch_agents

info "Step 2/8: Removing state database, backups, and logs"

if [ -d "$STATE_DIR" ]; then
    rm -f "$STATE_DIR/state.db" "$STATE_DIR/state.db-wal" "$STATE_DIR/state.db-shm"
    rm -f "$STATE_DIR/port-assignments" "$STATE_DIR/port-assignments.migrated"
    rm -f "$STATE_DIR/sites-state" "$STATE_DIR/sites-state.migrated"
    rm -f "$STATE_DIR/server-manager.pid" "$STATE_DIR/restart-request"
    rm -rf "$STATE_DIR/pids"
    rm -rf "$STATE_DIR/backups"
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

info "Step 3/8: Removing Apache custom configuration"

if [ -f "$CUSTOM_CONF" ]; then
    sudo rm -f "$CUSTOM_CONF"
    success "Removed $CUSTOM_CONF"
fi

if grep -q "extra/custom.conf" "$HTTPD_CONF" 2>/dev/null || \
   grep -q "^ServerName localhost" "$HTTPD_CONF" 2>/dev/null; then
    sudo cp "$HTTPD_CONF" "${HTTPD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    sudo sed -i '' '/# Developer custom site configuration/d' "$HTTPD_CONF"
    sudo sed -i '' '/Include.*extra\/custom\.conf/d' "$HTTPD_CONF"
    success "Removed custom.conf Include from httpd.conf"

    if grep -q "^ServerName localhost" "$HTTPD_CONF"; then
        sudo sed -i '' 's|^ServerName localhost|#ServerName www.example.com:80|' "$HTTPD_CONF"
        success "Reverted ServerName to default"
    fi

    for _mod in mod_proxy.so mod_proxy_http.so mod_rewrite.so mod_proxy_wstunnel.so mod_headers.so; do
        if grep -q "^LoadModule.*${_mod}" "$HTTPD_CONF"; then
            sudo sed -i '' "s|^\(LoadModule.*${_mod}\)|#\1|" "$HTTPD_CONF"
        fi
    done
    success "Re-commented proxy/rewrite/headers modules"
fi

if [ -d "$APACHE_LOG_DIR" ]; then
    sudo rm -rf "$APACHE_LOG_DIR"
    success "Removed $APACHE_LOG_DIR"
fi

if sudo apachectl configtest >/dev/null 2>&1; then
    sudo apachectl restart
    success "Apache restarted with clean configuration"
else
    warn "Apache config test failed after cleanup — may need manual fix"
fi

info "Step 4/8: Removing dotfile symlinks"

for _dotfile in zshrc vimrc gitignore gitconfig; do
    _src="$DOTFILES_DIR/$_dotfile"
    _dest="$HOME/.${_dotfile}"

    if [ -L "$_dest" ] && [ "$(readlink "$_dest")" = "$_src" ]; then
        rm -f "$_dest"
        success "  Removed ~/.${_dotfile} symlink"

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

# Pi configuration (extensions, skills, themes, settings)
_pi_base="$DOTFILES_DIR/pi/agent"
_pi_dest="$HOME/.pi/agent"
if [ -d "$_pi_base" ]; then
    for _item in AGENTS.md settings.json extensions skills themes; do
        _src="$_pi_base/$_item"
        _dest="$_pi_dest/$_item"
        if [ -L "$_dest" ] && [ "$(readlink "$_dest")" = "$_src" ]; then
            rm -f "$_dest"
            success "  Removed $_dest symlink"

            _backup=""
            for _bak in "${_dest}".bak.*; do
                [ -f "$_bak" ] && _backup="$_bak"
            done
            if [ -n "$_backup" ]; then
                mv "$_backup" "$_dest"
                success "  Restored $_dest from backup"
            fi
        elif [ -L "$_dest" ]; then
            warn "  $_dest is a symlink but points elsewhere — skipping"
        else
            success "  $_dest is not our symlink — skipping"
        fi
    done
fi

info "Step 5/8: Removing tunnel config, log rotation, and git hooks"

if [ -d "$HOME/.cloudflared" ]; then
    rm -rf "$HOME/.cloudflared"
    success "  Removed ~/.cloudflared (config, credentials, cert)"
else
    success "  No ~/.cloudflared directory to remove"
fi

_sudoers="/etc/sudoers.d/mac9sb"
if [ -f "$_sudoers" ]; then
    sudo rm -f "$_sudoers"
    success "  Removed $_sudoers"
else
    success "  No sudoers config to remove"
fi

_newsyslog="/etc/newsyslog.d/com.mac9sb.conf"
if [ -f "$_newsyslog" ]; then
    sudo rm -f "$_newsyslog"
    success "  Removed $_newsyslog"
else
    success "  No newsyslog config to remove"
fi

_hooks_dir="$DEV_DIR/.git/hooks"
for _hook_name in pre-push; do
    _hook_file="$_hooks_dir/$_hook_name"
    if [ -f "$_hook_file" ]; then
        rm -f "$_hook_file"
        success "  Removed git hook: $_hook_name"
    fi
done

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

info "Step 7/8: Cleaning up rollback binaries"

_cleaned_binaries=0
while IFS= read -r _file; do
    [ -z "$_file" ] && continue
    rm -f "$_file"
    _cleaned_binaries=$((_cleaned_binaries + 1))
done <<EOF
$(find "$SITES_DIR" -type f \( -name "*.run" -o -name "*.bak" -o -name "*.last-good" \) 2>/dev/null)
EOF

if [ "$_cleaned_binaries" -gt 0 ]; then
    success "  Removed $_cleaned_binaries rollback/run binary file(s)"
else
    success "  No rollback binaries to remove"
fi

info "Step 8/8: CLI tools"

if [ "$REMOVE_TOOLS" = true ]; then
    if command -v brew >/dev/null 2>&1; then
        for _tool in cloudflared gh opencode; do
            if brew list --formula "$_tool" >/dev/null 2>&1; then
                brew uninstall "$_tool"
                success "  Removed $_tool"
            fi
        done
        success "CLI tools removed"
    else
        warn "  Homebrew not found; skipping CLI tool removal"
    fi
else
    info "  Skipping CLI tool removal (use --all to include)"
fi

printf '\n\033[1;32m# ──────────────────────────────────────────\033[0m\n'
printf '\033[1;32m  Teardown Complete\033[0m\n'
printf '\033[1;32m# ──────────────────────────────────────────\033[0m\n'

printf '\n  \033[1mRemoved:\033[0m\n'
cat <<EOF
    - launchd agents from $LAUNCH_AGENTS_DIR/
      (legacy agents + backup, cloudflared)
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
[ "$REMOVE_TOOLS" = true ] && printf '    - CLI tools (cloudflared, gh, opencode)\n'

printf '\n  \033[1mPreserved:\033[0m\n'
cat <<EOF
    - Source code in sites/, tooling/
    - Templates and scripts in tooling/orchestrator/Sources/OrchestratorCLI/Resources/
    - Dotfile sources in utilities/dotfiles/
    - SSH keys in ~/.ssh/
    - R2 credentials (.env.local)
    - Git repository and submodule configuration

  To re-setup: ./setup.sh
  To fully remove: rm -rf $DEV_DIR

EOF
