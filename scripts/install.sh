#!/bin/zsh
set -e

MACOS=false
[ "$(uname)" = "Darwin" ] && MACOS=true

# Install Xcode Command Line Tools
if [ "$MACOS" = true ]; then
    if ! xcode-select -p >/dev/null 2>&1; then
        xcode-select --install 2>&1 || true
        printf '%s\n' "Waiting for Xcode Command Line Tools..."
        while ! xcode-select -p >/dev/null 2>&1; do
            sleep 5
        done
        printf '%s\n' "Xcode Command Line Tools installed."
    fi
fi

# Clone Configuration Repository
REPO="$HOME/Developer/configuration"
mkdir -p "$HOME/Developer"
if [ ! -d "$REPO" ]; then
    git clone --single-branch https://github.com/mac9sb/configuration "$REPO"
fi

# Create Symbolic Links to Configuration Files
mkdir -p "$HOME/.config"
for dir in ghostty git mise nvim ssh vim zed zsh; do
    target="$HOME/.config/$dir"
    src="$REPO/$dir"
    if [ "$(readlink "$target" 2>/dev/null)" = "$src" ]; then
        continue
    fi
    [ -e "$target" ] && mv "$target" "$target.bak"
    ln -sn "$src" "$target"
done

# Point ZSH to Custom Configuration Location
grep -q ZDOTDIR "$HOME/.zshenv" 2>/dev/null || {
    [ -f "$HOME/.zshenv" ] && cp "$HOME/.zshenv" "$HOME/.zshenv.bak"
    echo "export ZDOTDIR=\"$HOME/.config/zsh\"" >> "$HOME/.zshenv"
}

# Create Symbolic Link for Pi Models
mkdir -p "$HOME/.pi/agent"
pi_models_target="$REPO/pi/models.json"
pi_models_link="$HOME/.pi/agent/models.json"
if [ "$(readlink "$pi_models_link" 2>/dev/null)" != "$pi_models_target" ]; then
    [ -e "$pi_models_link" ] && mv "$pi_models_link" "$pi_models_link.bak"
    ln -sn "$pi_models_target" "$pi_models_link"
fi

# Generate an SSH Key
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "maclong9@icloud.com" \
        -f "$HOME/.ssh/id_ed25519" -N ""
fi
ln -sf "$HOME/.config/ssh/config" "$HOME/.ssh/config"

# Install Homebrew and packages (macOS only)
if [ "$MACOS" = true ]; then
    if ! command -v brew >/dev/null 2>&1; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Load brew into PATH (Apple Silicon or Intel)
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
            eval "$("$candidate" shellenv)"
            break
        fi
    done

    brew bundle --file="$REPO/Brewfile"
else
    # Install mise directly on Linux
    if ! command -v mise >/dev/null 2>&1; then
        curl https://mise.run | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
fi

# Install project-level tools via mise
mise trust "$REPO/mise/config.toml" && mise install

# Claude Code configuration
mkdir -p "$HOME/.claude"
for file in CLAUDE.md settings.json; do
    target="$HOME/.claude/$file"
    src="$REPO/claude/$file"
    if [ "$(readlink "$target" 2>/dev/null)" != "$src" ]; then
        [ -e "$target" ] && mv "$target" "$target.bak"
        ln -sn "$src" "$target"
    fi
done

# Install enabled Claude plugins
if command -v claude >/dev/null 2>&1; then
    if claude plugins list >/dev/null 2>&1; then
        python3 -c "
import json
with open('$REPO/claude/settings.json') as f:
    s = json.load(f)
for k, v in s.get('enabledPlugins', {}).items():
    if v: print(k)
" | while IFS= read -r plugin; do
            claude plugins install "\$plugin" 2>/dev/null || true
        done
    else
        printf '%s\n' "Claude not authenticated — run 'claude /login' then re-run this script to install plugins"
    fi
fi

# Setup GitHub CLI Tool (only if available)
if command -v gh >/dev/null 2>&1; then
    gh auth status >/dev/null 2>&1 || gh auth login -s admin:ssh_signing_key
    if ! gh ssh-key list --json key,title 2>/dev/null | grep -Fq "$(cat "$HOME/.ssh/id_ed25519.pub")"; then
        gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$(hostname)" --type signing
    fi
fi

# Apply macOS Interface Customisation
if [ "$MACOS" = true ]; then
    sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
    sudo sed -i '' 's/^#auth/auth/' /etc/pam.d/sudo_local

    defaults write com.apple.dock persistent-apps -array
    for app in \
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app" \
        "/System/Applications/Messages.app" \
        "/System/Applications/Mail.app" \
        "/System/Applications/Calendar.app" \
        "/System/Applications/Reminders.app" \
        "/System/Applications/Notes.app" \
        "/System/Applications/Music.app" \
        "/System/Applications/Books.app"; do
        defaults write com.apple.dock persistent-apps -array-add \
            "<dict><key>tile-data</key><dict><key>file-data</key><dict>\
<key>_CFURLString</key><string>file://${app}/</string>\
<key>_CFURLStringType</key><integer>15</integer>\
</dict></dict></dict>"
    done
    defaults write com.apple.dock persistent-others -array \
        "<dict><key>tile-data</key><dict>\
<key>arrangement</key><integer>2</integer>\
<key>showas</key><integer>1</integer>\
<key>file-data</key><dict>\
<key>_CFURLString</key><string>file://${HOME}/Downloads/</string>\
<key>_CFURLStringType</key><integer>15</integer>\
</dict></dict><key>tile-type</key><string>directory-tile</string></dict>"
    defaults write com.apple.dock tilesize -int 54
    defaults write com.apple.dock magnification -bool true
    defaults write com.apple.dock largesize -int 73
    killall Dock

    defaults write com.apple.menuextra.clock ShowDate -int 0
    defaults write com.apple.menuextra.clock ShowDayOfWeek -bool true

    defaults write com.apple.controlcenter "NSStatusItem VisibleCC Battery" -bool true
    defaults write com.apple.controlcenter "NSStatusItem VisibleCC WiFi" -bool true
    defaults write com.apple.controlcenter "NSStatusItem VisibleCC NowPlaying" -bool true
    defaults write com.apple.controlcenter "NSStatusItem VisibleCC Clock" -bool true
    defaults write com.apple.controlcenter "NSStatusItem VisibleCC BentoBox-0" -bool true
    defaults write com.apple.controlcenter "NSStatusItem VisibleCC Spotlight" -bool false

    killall ControlCenter 2>/dev/null || true
    killall SystemUIServer 2>/dev/null || true

    defaults write com.apple.dock mru-spaces -bool false
    defaults write com.apple.WindowManager GloballyEnabled -bool true
    defaults write com.apple.WindowManager EnableTiledWindowMargins -bool true
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true
    defaults write NSGlobalDomain com.apple.springing.enabled -bool true
    defaults write NSGlobalDomain com.apple.springing.delay -float 0
fi
