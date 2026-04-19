#!/bin/sh
set -e

MACOS=false
[ "$(uname)" = "Darwin" ] && MACOS=true

# Remove symlinks
for dir in git mise nvim ssh vim zed zsh; do
    rm -f "$HOME/.config/$dir"
done
rm -f "$HOME/.ssh/config"

# Restore backups
for dir in git mise nvim ssh vim zed zsh; do
    [ -e "$HOME/.config/$dir.bak" ] && mv "$HOME/.config/$dir.bak" "$HOME/.config/$dir"
done
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
    brew bundle cleanup --file="$HOME/Developer/configuration/Brewfile" --force
fi

# Remove cloned repository
rm -rf "$HOME/Developer/configuration"

if [ "$MACOS" = true ]; then
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

    killall ControlCenter 2>/dev/null || true
    killall SystemUIServer 2>/dev/null || true

    # Revert window manager and trackpad settings
    defaults write com.apple.WindowManager GloballyEnabled -bool false
    defaults write com.apple.WindowManager EnableTiledWindowMargins -bool false
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool false
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool false
    defaults delete NSGlobalDomain com.apple.springing.enabled 2>/dev/null || true
    defaults delete NSGlobalDomain com.apple.springing.delay 2>/dev/null || true
fi
