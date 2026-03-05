#!/bin/sh
# ——— Source utils ———
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"
. "$SCRIPT_DIR/utils.sh"

[ "$(uname -s)" = "Darwin" ] || die "This script is macOS-only."

total_start

# ——— Step: Xcode Command Line Tools ———
install_xcode_clt() {
  step "Installing Xcode Command Line Tools"
  if xcode-select -p >/dev/null 2>&1; then
    log "Already installed"
    step_done
    return 0
  fi
  xcode-select --install >/dev/null 2>&1 || true
  log "Re-run this script after CLT installation finishes"
  exit 0
}

# ——— Step: Homebrew ———
install_brew_if_missing() {
  step "Installing Homebrew if missing"
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew already installed"
    step_done
    return 0
  fi
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  step_done
}

# ——— Step: Brew bundle (can run in bg) ———
brew_bundle() {
  step "Running brew bundle"
  if [ ! -f "$CONFIG_DIR/Brewfile" ]; then
    warn "Brewfile not found"
    step_done
    return 0
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)" && brew bundle --file="$CONFIG_DIR/Brewfile"
  /opt/homebrew/bin/rustup default stable
  step_done
}

# ——— Step: Bootstrap shell environment ———
bootstrap_zshenv() {
  step "Bootstrapping ~/.zshenv"
  target="$HOME/.zshenv"
  content='export ZDOTDIR="$HOME/.config/zsh"'
  if [ -f "$target" ] && grep -qF 'ZDOTDIR' "$target" 2>/dev/null; then
    log "Already configured"
  else
    echo "$content" >> "$target"
    log "Created $target"
  fi
  step_done
}

# ——— Step: Touch ID ———
enable_touchid_for_sudo() {
  step "Enabling Touch ID for sudo"
  template="/etc/pam.d/sudo_local.template"
  target="/etc/pam.d/sudo_local"

  if [ ! -f "$template" ]; then
    log "Template not found; skipping"
    step_done
    return 0
  fi

  if [ -f "$target" ] && grep -q '^[[:space:]]*auth[[:space:]]\+sufficient[[:space:]]\+pam_tid\.so' "$target" 2>/dev/null; then
    log "Already enabled"
    step_done
    return 0
  fi

  if sudo cp "$template" "$target" &&
     sudo sed -i "" "s/^[[:space:]]*#auth[[:space:]]\\+sufficient[[:space:]]\\+pam_tid\\.so/auth       sufficient     pam_tid.so/" "$target"; then
    log "Touch ID enabled successfully"
  else
    warn "Touch ID modification failed (continuing)"
  fi
  step_done
}

# ——— Step: macOS defaults ———
configure_macos_defaults() {
  step "Configuring macOS defaults"

  # Three-finger drag
  defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true

  # Caps Lock → Control (built-in keyboard, vendor 0, product 0)
  hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E0}]}' >/dev/null

  log "Three-finger drag and Caps Lock → Control configured"
  step_done
}

# ——— Step: Load LaunchAgents ———
load_launch_agents() {
  step "Loading LaunchAgents"
  _launchd_dir="$CONFIG_DIR/scripts/launchd"
  if [ ! -d "$_launchd_dir" ]; then
    warn "LaunchD directory not found: $_launchd_dir"
    step_done
    return 0
  fi

  for plist_file in "$_launchd_dir"/*.plist; do
    if [ -f "$plist_file" ]; then
      log "Loading $(basename "$plist_file")"
      launchctl unload -w "$HOME/Library/LaunchAgents/$(basename "$plist_file")" >/dev/null 2>&1 || true
      ln -sf "$plist_file" "$HOME/Library/LaunchAgents/"
      launchctl load -w "$HOME/Library/LaunchAgents/$(basename "$plist_file")" || warn "Failed to load $(basename "$plist_file")"
    fi
  done
  step_done
}

# ——— Main sequence ———
log "Starting macOS setup"

# Sequential steps
install_xcode_clt
install_brew_if_missing

# Start brew_bundle in background
parallel_step "Brew bundle" brew_bundle

# Sequential, independent steps
bootstrap_zshenv
enable_touchid_for_sudo
configure_macos_defaults
load_launch_agents

# Wait for brew_bundle to finish
wait_parallel_steps

total_done
log "Setup complete ✅"
