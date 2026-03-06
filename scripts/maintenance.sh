#!/bin/sh
set -eu
# ─────────────────────────────────────────────
# Weekly Maintenance
# Runs every Sunday at 03:00 via cron
# Cleans caches, build artefacts, and temp files
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/utils.sh"

DRY_RUN=false
for _arg in "$@"; do
  case "$_arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

# Helper: execute or preview a command depending on DRY_RUN
run() {
  if $DRY_RUN; then
    log "[dry-run] $*"
  else
    "$@"
  fi
}

total_start

# ——— Step: Maintenance ———
maintenance() {
  step "Running weekly maintenance"

  if $DRY_RUN; then
    log "Running in dry-run mode — no files will be deleted"
  fi

  # macOS caches and logs
  run rm -rf "$HOME/Library/Caches/"* 2>/dev/null || true
  run rm -rf "$HOME/Library/Logs/"* 2>/dev/null || true
  run rm -rf "$HOME/Library/Developer/Xcode/DerivedData/"* 2>/dev/null || true
  run rm -rf "$HOME/Library/Developer/Xcode/Archives/"* 2>/dev/null || true
  run rm -rf "$HOME/Library/Developer/CoreSimulator/Caches/"* 2>/dev/null || true

  # Homebrew cleanup
  if command -v brew >/dev/null 2>&1; then
    run brew cleanup --prune=7 -s 2>/dev/null || true
    run brew autoremove 2>/dev/null || true
  fi

  # Rust build artefacts
  if command -v cargo >/dev/null 2>&1; then
    run cargo cache -a 2>/dev/null || true
  fi
  if $DRY_RUN; then
    log "[dry-run] Would delete Rust target/ directories under ~/Developer"
  else
    find "$HOME/Developer" -maxdepth 4 -name "target" -type d -path "*/target" -exec rm -rf {} + 2>/dev/null || true
  fi

  # Node artefacts — only delete node_modules that are not in use by running processes
  warn "Cleaning node_modules — running dev servers may need 'npm install' afterwards"
  _nm_list=$(mktemp)
  find "$HOME/Developer" -maxdepth 4 -name "node_modules" -type d > "$_nm_list" 2>/dev/null || true
  while IFS= read -r _nm_dir; do
    [ -n "$_nm_dir" ] || continue
    _project_dir=$(dirname "$_nm_dir")
    # Check if any node process has files open in this project directory
    if lsof +D "$_project_dir" 2>/dev/null | grep -q node 2>/dev/null; then
      warn "Skipping $_nm_dir — node process is using this project"
    else
      run rm -rf "$_nm_dir"
    fi
  done < "$_nm_list"
  rm -f "$_nm_list"

  if $DRY_RUN; then
    log "[dry-run] Would delete .next/ directories under ~/Developer"
  else
    find "$HOME/Developer" -maxdepth 4 -name ".next" -type d -exec rm -rf {} + 2>/dev/null || true
  fi
  run pnpm store prune 2>/dev/null || true

  # Trash and temp files
  run rm -rf "$HOME/.Trash/"* 2>/dev/null || true
  run rm -rf /tmp/com.apple.* 2>/dev/null || true

  step_done
}

# ——— Main sequence ———
log "Starting weekly maintenance"

maintenance

total_done
log "Done"
