#!/bin/sh
set -eu
# ─────────────────────────────────────────────
# Monthly Creative Build
# Runs on the 1st of each month at 09:00 via launchd
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/utils.sh"

WORK_DIR="$HOME/Work/claude"
BUILD_DIR="$WORK_DIR/$(date +%Y-%m)"
LOG_DIR="/tmp"
PROMPT_FILE="$HOME/.config/scripts/prompts/new.md"

total_start

# ——— Step: Setup directories ———
setup_dirs() {
  step "Setting up directories"
  mkdir -p "$BUILD_DIR"
  step_done
}

# ——— Step: Write prompt ———
write_prompt() {
  step "Writing prompt file"
  _prompt_src="$SCRIPT_DIR/prompts/weekly.md"
  if [ ! -f "$_prompt_src" ]; then
    die "Weekly prompt file not found: $_prompt_src"
  fi
  cp "$_prompt_src" "$PROMPT_FILE"
  step_done
}

# ——— Step: Run Claude Code ———
run_claude() {
  step "Running Claude Code session"
  cd "$BUILD_DIR"
  claude \
    --model claude-opus-4-6 \
    --max-turns 500 \
    --allowedTools "Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch" \
    --print \
    < "$PROMPT_FILE"
  step_done
}

# ——— Step: Notify ———
notify() {
  step "Sending notification"
  osascript <<APPLESCRIPT
display notification "Your new project is ready" with title "Claude Weekly Build"
delay 1
tell application "Zed"
  activate
  open POSIX file "$WORK_DIR"
end tell
APPLESCRIPT
  step_done
}

# ——— Main sequence ———
log "Starting monthly Claude build"

setup_dirs
write_prompt
run_claude
notify

total_done
log "Done"
