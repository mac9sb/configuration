#!/bin/sh
set -eu

log() {
  level="${2:-INFO}"
  printf "%s [%s] %s\n" "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$level" "$1"
}

die() {
  log "$*" "ERROR"
  exit 1
}

warn() {
  log "$*" "WARN"
}

[ "$(uname -s)" = "Darwin" ] || die "This script is macOS-only."

CONFIG_REPO_URL="https://github.com/mac9sb/config.git"
CONFIG_DIR="$HOME/.config"

# ——— Config Repository ———
ensure_config_repo() {
  if [ -d "$CONFIG_DIR/.git" ]; then
    log "Config repo: already present at $CONFIG_DIR"
    return 0
  fi

  if [ -e "$CONFIG_DIR" ]; then
    die "Config path already exists and is not a git repo: $CONFIG_DIR"
  fi

  log "Cloning config repo into $CONFIG_DIR"
  git clone "$CONFIG_REPO_URL" "$CONFIG_DIR"
}

# ——— Link Configuration Files ———
symlink_home_dotfiles() {
  for file in "$CONFIG_DIR"/.*; do
    [ -f "$file" ] || continue
    filename="$(basename "$file")"
    case "$filename" in
    . | ..) continue ;;
    .git) continue ;;
    *) ln -sf "$file" "$HOME/$filename" ;;
    esac
  done
}

# ——— Xcode Command Line Tools ———
install_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log "Xcode Command Line Tools: already installed"
    return 0
  fi

  log "Installing Xcode Command Line Tools (a GUI prompt will appear)..."
  xcode-select --install >/dev/null 2>&1 || true
  log "Re-run this script after the CLT installation finishes."
  exit 0
}

# ——— Touch ID for sudo via sudo_local ———
enable_touchid_for_sudo() {
  template="/etc/pam.d/sudo_local.template"
  target="/etc/pam.d/sudo_local"

  if [ ! -f "$template" ]; then
    log "Touch ID: $template not found; skipping"
    return 0
  fi

  if [ -f "$target" ] && grep -q '^[[:space:]]*auth[[:space:]]\+sufficient[[:space:]]\+pam_tid\.so' "$target" 2>/dev/null; then
    log "Touch ID: already enabled (sudo_local)"
    return 0
  fi

  log "Enabling Touch ID for sudo (requires sudo)..."
  if sudo cp "$template" "$target" &&
    sudo sed -i "" "s/^[[:space:]]*#auth[[:space:]]\\+sufficient[[:space:]]\\+pam_tid\\.so/auth       sufficient     pam_tid.so/" "$target"; then
    log "Touch ID: enabled successfully"
  else
    warn "Touch ID modification failed (continuing)"
  fi
}

# ——— Homebrew Installation ———
install_brew_if_missing() {
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew: already installed"
    return 0
  fi

  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://brew.sh/install)"
}

# ——— Homebrew Bundle ———
brew_bundle() {
  cd "$CONFIG_DIR"
  if [ ! -f "./Brewfile" ]; then
    warn "Brewfile not found in current directory: $(pwd)"
    log "Skipping brew bundle."
    return 0
  fi

  log "Running: brew bundle"

  eval "$(/opt/homebrew/bin/brew shellenv)" && brew bundle

  # Other tooling configuration
  /opt/homebrew/bin/rustup default stable
}

# ——— main ———
log "Starting macOS setup"
ensure_config_repo
symlink_home_dotfiles
install_xcode_clt
enable_touchid_for_sudo
install_brew_if_missing
brew_bundle
log "Done ✅"
