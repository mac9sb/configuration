#!/bin/zsh
set -e

if [ "$(uname)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    printf '%s\n' "This configuration supports only Apple Silicon macOS." >&2
    exit 1
fi

# Install Xcode Command Line Tools
if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install 2>&1 || true
    printf '%s\n' "Waiting for Xcode Command Line Tools..."
    while ! xcode-select -p >/dev/null 2>&1; do
        sleep 5
    done
    printf '%s\n' "Xcode Command Line Tools installed."
fi

# Resolve Configuration Repository
SCRIPT_DIR=${0:A:h}
REPO=${SCRIPT_DIR:h}

# Create a symlink, backing up any existing target first
make_link() {
    local src="$1" target="$2" backup

    [ "$(readlink "$target" 2>/dev/null)" = "$src" ] && return

    mkdir -p "${target:h}"
    if [ -e "$target" ] || [ -L "$target" ]; then
        backup="$target.bak"
        [ -e "$backup" ] || [ -L "$backup" ] && backup="$target.bak.$(date +%Y%m%d%H%M%S)"
        mv "$target" "$backup"
    fi

    ln -sfn "$src" "$target"
}

install_launch_agent() {
    local label="$1" plist_path="$2" script_path="$3" log_dir="$4"

    mkdir -p "${plist_path:h}" "$log_dir"
    cat >"$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${script_path}</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>1</integer>
        <key>Hour</key>
        <integer>16</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${log_dir}/${label}.out.log</string>
    <key>StandardErrorPath</key>
    <string>${log_dir}/${label}.err.log</string>
</dict>
</plist>
EOF

    launchctl bootout "gui/$(id -u)" "$plist_path" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist_path"
}

# Create Symbolic Links to Configuration Files
mkdir -p "$HOME/.config"
for dir in ghostty git mise nvim ssh vim zed zsh; do
    make_link "$REPO/$dir" "$HOME/.config/$dir"
done

# Point ZSH to Custom Configuration Location
grep -q ZDOTDIR "$HOME/.zshenv" 2>/dev/null || {
    [ -f "$HOME/.zshenv" ] && cp "$HOME/.zshenv" "$HOME/.zshenv.bak"
    echo "export ZDOTDIR=\"$HOME/.config/zsh\"" >> "$HOME/.zshenv"
}

# Create Symlink for Pi Agent Home Directory
make_link "$REPO/pi" "$HOME/.pi"

# Generate an SSH Key
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "maclong9@icloud.com" \
        -f "$HOME/.ssh/id_ed25519" -N ""
fi
make_link "$HOME/.config/ssh/config" "$HOME/.ssh/config"

# Install Homebrew and packages
if [ ! -x /opt/homebrew/bin/brew ]; then
    printf '%s\n' "Homebrew is required at /opt/homebrew/bin/brew." >&2
    exit 1
fi

eval "$(/opt/homebrew/bin/brew shellenv)"
brew bundle --file="$REPO/Brewfile"

# Install project-level tools via mise
mise trust "$REPO/mise/config.toml" && mise install

# Install scheduled maintenance LaunchAgent
install_launch_agent \
    "com.mac.configuration.maintenance" \
    "$HOME/Library/LaunchAgents/com.mac.configuration.maintenance.plist" \
    "$REPO/scripts/maintenance.sh" \
    "$HOME/Library/Logs"

# Apply macOS Interface Customisation
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
defaults write com.apple.dock mru-spaces -bool false
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

defaults write com.apple.WindowManager GloballyEnabled -bool true
defaults write com.apple.WindowManager EnableTiledWindowMargins -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true
defaults write NSGlobalDomain com.apple.springing.enabled -bool true
defaults write NSGlobalDomain com.apple.springing.delay -float 0
