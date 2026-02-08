#!/bin/sh
set -e

# =============================================================================
#  macOS Developer Environment Teardown
#  Author: Mac (maclong9)
#
#  This script reverses the setup performed by setup.sh:
#    - Unloads and removes launchd agents
#    - Removes Apache custom config and restores httpd.conf backup
#    - Removes watcher runtime state
#    - Removes dotfile symlinks (preserves source files in utilities/)
#    - Optionally removes installed CLI tools (cloudflared, gh)
#
#  Usage: sudo ./uninstall.sh [--all]
#    --all    Also remove cloudflared, gh, and Xcode CLI tools
# =============================================================================

GITHUB_USER="mac9sb"
DEV_DIR="$HOME/Developer"
SITES_DIR="$DEV_DIR/sites"
UTILITIES_DIR="$DEV_DIR/utilities"
DOTFILES_DIR="$UTILITIES_DIR/dotfiles"
WATCHER_DIR="$DEV_DIR/.watchers"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
HTTPD_CONF="/etc/apache2/httpd.conf"
CUSTOM_CONF="/etc/apache2/extra/custom.conf"
LOG_DIR="/var/log/apache2/sites"

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

printf "\n"
printf "\033[1;31m=============================================================================\033[0m\n"
printf "\033[1;31m  Developer Environment Teardown\033[0m\n"
printf "\033[1;31m=============================================================================\033[0m\n"
printf "\n"
printf "  This will:\n"
printf "    - Unload and remove all %s.* launchd agents\n" "$GITHUB_USER"
printf "    - Remove Apache custom site configuration\n"
printf "    - Remove watcher runtime state (.watchers/)\n"
printf "    - Remove dotfile symlinks (~/.zshrc, ~/.vimrc, etc.)\n"
printf "    - Remove site log directory (%s)\n" "$LOG_DIR"
if [ "$REMOVE_TOOLS" = true ]; then
    printf "    - Remove cloudflared and gh CLI from /usr/local/bin\n"
fi
printf "\n"
printf "  This will NOT:\n"
printf "    - Delete submodule source code (sites/, tooling/, tsx/)\n"
printf "    - Delete template files (utilities/)\n"
printf "    - Delete SSH keys (~/.ssh/id_ed25519)\n"
printf "    - Modify the git repository itself\n"
printf "\n"

if ! confirm "Proceed with teardown?"; then
    info "Teardown cancelled."
    exit 0
fi

printf "\n"

# =============================================================================
#  Step 1 — Unload and remove launchd agents
# =============================================================================

info "Step 1/6: Removing launchd agents"

# Remove the sites watcher agent
_sites_watcher_label="com.${GITHUB_USER}.sites-watcher"
_sites_watcher_plist="${LAUNCH_AGENTS_DIR}/${_sites_watcher_label}.plist"
if [ -f "$_sites_watcher_plist" ]; then
    launchctl bootout "gui/${UID_NUM}/${_sites_watcher_label}" 2>/dev/null || true
    rm -f "$_sites_watcher_plist"
    success "Removed sites-watcher agent"
fi

# Remove all per-site agents (server + watcher pairs)
for _plist in "${LAUNCH_AGENTS_DIR}"/com.${GITHUB_USER}.*.plist; do
    [ ! -f "$_plist" ] && continue
    _label="$(basename "$_plist" .plist)"
    launchctl bootout "gui/${UID_NUM}/${_label}" 2>/dev/null || true
    rm -f "$_plist"
    success "  Removed agent: $_label"
done

success "All launchd agents removed"

# =============================================================================
#  Step 2 — Remove watcher runtime state
# =============================================================================

info "Step 2/6: Removing watcher state"

if [ -d "$WATCHER_DIR" ]; then
    rm -rf "$WATCHER_DIR"
    success "Removed $WATCHER_DIR"
else
    success "No watcher state to remove"
fi

# =============================================================================
#  Step 3 — Remove Apache custom configuration
# =============================================================================

info "Step 3/6: Removing Apache custom configuration"

# Remove the custom.conf file
if [ -f "$CUSTOM_CONF" ]; then
    sudo rm -f "$CUSTOM_CONF"
    success "Removed $CUSTOM_CONF"
fi

# Remove the Include line from httpd.conf
if grep -q "extra/custom.conf" "$HTTPD_CONF" 2>/dev/null; then
    sudo cp "$HTTPD_CONF" "${HTTPD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    sudo sed -i '' '/# Developer custom site configuration/d' "$HTTPD_CONF"
    sudo sed -i '' '/Include.*extra\/custom\.conf/d' "$HTTPD_CONF"
    success "Removed custom.conf Include from httpd.conf"
fi

# Remove site log directory
if [ -d "$LOG_DIR" ]; then
    sudo rm -rf "$LOG_DIR"
    success "Removed $LOG_DIR"
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

info "Step 4/6: Removing dotfile symlinks"

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

# =============================================================================
#  Step 5 — Remove Touch ID for sudo (optional)
# =============================================================================

info "Step 5/6: Touch ID for sudo"

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
#  Step 6 — Remove CLI tools (only with --all)
# =============================================================================

info "Step 6/6: CLI tools"

if [ "$REMOVE_TOOLS" = true ]; then
    if [ -f /usr/local/bin/cloudflared ]; then
        sudo rm -f /usr/local/bin/cloudflared
        success "  Removed cloudflared"
    fi

    if [ -f /usr/local/bin/gh ]; then
        sudo rm -f /usr/local/bin/gh
        success "  Removed gh"
    fi

    success "CLI tools removed"
else
    info "  Skipping CLI tool removal (use --all to include)"
fi

# =============================================================================
#  Summary
# =============================================================================

printf "\n"
printf "\033[1;32m=============================================================================\033[0m\n"
printf "\033[1;32m  Teardown Complete\033[0m\n"
printf "\033[1;32m=============================================================================\033[0m\n"
printf "\n"
printf "  \033[1mRemoved:\033[0m\n"
printf "    - launchd agents from %s/\n" "$LAUNCH_AGENTS_DIR"
printf "    - Watcher state from %s/\n" "$WATCHER_DIR"
printf "    - Apache config (%s)\n" "$CUSTOM_CONF"
printf "    - Dotfile symlinks\n"
if [ "$REMOVE_TOOLS" = true ]; then
    printf "    - CLI tools (cloudflared, gh)\n"
fi
printf "\n"
printf "  \033[1mPreserved:\033[0m\n"
printf "    - Source code in sites/, tooling/, tsx/\n"
printf "    - Templates in utilities/\n"
printf "    - Dotfile sources in utilities/dotfiles/\n"
printf "    - SSH keys in ~/.ssh/\n"
printf "    - Git repository and submodule configuration\n"
printf "\n"
printf "  To re-setup: sudo ./setup.sh\n"
printf "  To fully remove: rm -rf %s\n" "$DEV_DIR"
printf "\n"
