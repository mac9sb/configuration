#!/bin/sh
# ─────────────────────────────────────────────
# Weekly Maintenance
# Runs every Sunday at 03:00 via cron
# Cleans caches, build artefacts, and temp files
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/utils.sh"

total_start

# ——— Step: Maintenance ———
maintenance() {
  step "Running weekly maintenance"

  # macOS caches and logs
  rm -rf "$HOME/Library/Caches/"* 2>/dev/null || true
  rm -rf "$HOME/Library/Logs/"* 2>/dev/null || true
  rm -rf "$HOME/Library/Developer/Xcode/DerivedData/"* 2>/dev/null || true
  rm -rf "$HOME/Library/Developer/Xcode/Archives/"* 2>/dev/null || true
  rm -rf "$HOME/Library/Developer/CoreSimulator/Caches/"* 2>/dev/null || true

  # Homebrew cleanup
  if command -v brew >/dev/null 2>&1; then
    brew cleanup --prune=7 -s 2>/dev/null || true
    brew autoremove 2>/dev/null || true
  fi

  # Rust build artefacts
  if command -v cargo >/dev/null 2>&1; then
    cargo cache -a 2>/dev/null || true
  fi
  find "$HOME/Developer" -maxdepth 4 -name "target" -type d -path "*/target" -exec rm -rf {} + 2>/dev/null || true

  # Node artefacts
  find "$HOME/Developer" -maxdepth 4 -name "node_modules" -type d -exec rm -rf {} + 2>/dev/null || true
  find "$HOME/Developer" -maxdepth 4 -name ".next" -type d -exec rm -rf {} + 2>/dev/null || true
  pnpm store prune 2>/dev/null || true

  # Trash and temp files
  rm -rf "$HOME/.Trash/"* 2>/dev/null || true
  rm -rf /tmp/com.apple.* 2>/dev/null || true

  step_done
}

# ——— Main sequence ———
log "Starting weekly maintenance"

maintenance

total_done
log "Done"
