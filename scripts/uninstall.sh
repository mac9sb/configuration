#!/bin/sh
set -e

if [ "$(uname)" != "Darwin" ]; then
    printf '%s\n' "This configuration supports only macOS." >&2
    exit 1
fi

REPO="$HOME/Developer/configuration"
MAINTENANCE_LABEL="com.mac.configuration.maintenance"
MAINTENANCE_PLIST="$HOME/Library/LaunchAgents/${MAINTENANCE_LABEL}.plist"

# Remove symlinks and restore backups
for dir in ghostty git mise nvim ssh vim zed zsh; do
    rm -f "$HOME/.config/$dir"
    [ -e "$HOME/.config/$dir.bak" ] && mv "$HOME/.config/$dir.bak" "$HOME/.config/$dir"
done
rm -f "$HOME/.ssh/config"

[ -f "$HOME/.zshenv.bak" ] && mv "$HOME/.zshenv.bak" "$HOME/.zshenv" ||
    {
        if [ -f "$HOME/.zshenv" ]; then
            tmp_file="$(mktemp "${TMPDIR:-/tmp}/zshenv.XXXXXX")"
            grep -v 'ZDOTDIR' "$HOME/.zshenv" >"$tmp_file" || true
            mv "$tmp_file" "$HOME/.zshenv"
        fi
    }

# Optionally clean up brew-managed packages before the Brewfile disappears
if [ "${UNINSTALL_BREW:-0}" = "1" ] && command -v brew >/dev/null 2>&1; then
    brew bundle cleanup --file="$REPO/Brewfile" --force
fi

# Remove scheduled maintenance LaunchAgent
launchctl bootout "gui/$(id -u)" "$MAINTENANCE_PLIST" 2>/dev/null || true
rm -f "$MAINTENANCE_PLIST"

# Optionally remove cloned repository
if [ "${REMOVE_REPO:-0}" = "1" ]; then
    rm -rf "$REPO"
fi

# Revert TouchID for sudo
sudo rm -f /etc/pam.d/sudo_local

# Revert Dock and macOS defaults
defaults delete com.apple.dock persistent-apps
defaults delete com.apple.dock persistent-others
defaults delete com.apple.dock tilesize
defaults delete com.apple.dock magnification
defaults delete com.apple.dock largesize
defaults write com.apple.dock mru-spaces -bool true
killall Dock

# Revert Menu Bar clock
defaults delete com.apple.menuextra.clock ShowDate 2>/dev/null || true
defaults delete com.apple.menuextra.clock ShowDayOfWeek 2>/dev/null || true

# Revert Menu Bar visible items
defaults delete com.apple.controlcenter "NSStatusItem VisibleCC Battery" 2>/dev/null || true
defaults delete com.apple.controlcenter "NSStatusItem VisibleCC WiFi" 2>/dev/null || true
defaults delete com.apple.controlcenter "NSStatusItem VisibleCC NowPlaying" 2>/dev/null || true
defaults delete com.apple.controlcenter "NSStatusItem VisibleCC Clock" 2>/dev/null || true
defaults delete com.apple.controlcenter "NSStatusItem VisibleCC BentoBox-0" 2>/dev/null || true
defaults delete com.apple.controlcenter "NSStatusItem VisibleCC Spotlight" 2>/dev/null || true

killall ControlCenter 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

# Revert window manager and trackpad settings
defaults write com.apple.WindowManager GloballyEnabled -bool false
defaults write com.apple.WindowManager EnableTiledWindowMargins -bool false
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool false
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool false
defaults delete NSGlobalDomain com.apple.springing.enabled 2>/dev/null || true
defaults delete NSGlobalDomain com.apple.springing.delay 2>/dev/null || true
