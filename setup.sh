#!/bin/sh
# ——— Source utils ———
. ./utils.sh

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
  /bin/bash -c "$(curl -fsSL https://brew.sh/install)"
  step_done
}

# ——— Step: Brew bundle (can run in bg) ———
brew_bundle() {
  step "Running brew bundle"
  cd "$CONFIG_DIR"
  if [ ! -f "./Brewfile" ]; then
    warn "Brewfile not found"
    step_done
    return 0
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)" && brew bundle
  /opt/homebrew/bin/rustup default stable
  step_done
}

# ——— Step: Symlink dotfiles ———
symlink_home_dotfiles() {
  step "Linking dotfiles from $CONFIG_DIR"
  for file in "$CONFIG_DIR"/.*; do
    [ -f "$file" ] || continue
    filename="$(basename "$file")"
    case "$filename" in
      .|..|.git) continue ;;
      *) ln -sf "$file" "$HOME/$filename" ;;
    esac
  done
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

# ——— Main sequence ———
log "Starting macOS setup"

# Sequential steps
install_xcode_clt
install_brew_if_missing

# Start brew_bundle in background
parallel_step "Brew bundle" brew_bundle

# Sequential, independent steps
symlink_home_dotfiles
enable_touchid_for_sudo

# Wait for brew_bundle to finish
wait_parallel_steps

total_done
log "Setup complete ✅"
