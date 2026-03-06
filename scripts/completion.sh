#!/bin/sh
set -eu
# ─────────────────────────────────────────────
# Monthly Audit Completion
# Runs on the 3rd of each month at 11:00 via launchd
# Finds all AUDIT.md files, completes tasks, generates summary
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/utils.sh"

log "PATH=$PATH"

DEVELOPER_DIR="$HOME/Developer"
LOG_DIR="/tmp"
PROMPT_FILE="$HOME/.claude-audit-completion/prompt.md"

total_start

# ——— Step: Setup ———
setup() {
  step "Setting up audit completion runner"
  mkdir -p "$(dirname "$PROMPT_FILE")"
  step_done
}

# ——— Step: Write prompt ———
write_prompt() {
  step "Writing audit task prompt"
  _prompt_src="$SCRIPT_DIR/prompts/completion.md"
  if [ ! -f "$_prompt_src" ]; then
    die "Completion prompt file not found: $_prompt_src"
  fi
  cp "$_prompt_src" "$PROMPT_FILE"
  step_done
}

# ——— Step: Run single Claude instance to process all AUDIT.md files ———
scan_and_run() {
  step "Finding AUDIT.md files and preparing prompt for Claude"

  _audit_list_for_prompt=$(mktemp)
  _audit_files_list=$(mktemp)

  # Find AUDIT.md files and filter for those with unchecked tasks
  find "$DEVELOPER_DIR" -maxdepth 4 -name "AUDIT.md" -not -path '*/.*' | sort > "$_audit_files_list"
  while IFS= read -r _audit_file; do
    if grep -q '^\- \[ \]' "$_audit_file" 2>/dev/null; then
      _rel_path="${_audit_file#"$DEVELOPER_DIR"/}"
      echo "- $_rel_path" >> "$_audit_list_for_prompt"
    fi
  done < "$_audit_files_list"
  rm -f "$_audit_files_list"

  _audit_files_found=0
  if [ -s "$_audit_list_for_prompt" ]; then
    _audit_files_found=$(wc -l < "$_audit_list_for_prompt" | tr -d ' ')
  fi

  if [ "$_audit_files_found" -eq 0 ]; then
    log "No AUDIT.md files with unchecked tasks found. Skipping Claude session."
    rm -f "$_audit_list_for_prompt"
    step_done
    return 0
  fi

  # Append the list of files to the prompt
  echo -e "\\nAUDIT.md Files to process (relative to '\$HOME/Developer'):" >> "$PROMPT_FILE"
  cat "$_audit_list_for_prompt" >> "$PROMPT_FILE"
  rm -f "$_audit_list_for_prompt"

  _log="$LOG_DIR/audit-completion-all.log"

  log "Launching Claude for $_audit_files_found audit tasks"
  (cd "$DEVELOPER_DIR" && claude \
    --model claude-opus-4-6 \
    --max-turns 500 \
    --allowedTools "Bash,Read,Write,Edit,Glob,Grep" \
    --print \
    < "$PROMPT_FILE" \
    > "$_log" 2>&1) || warn "Claude session failed for audit completion"
  log "Finished single Claude session for audit tasks"

  step_done
}

# ——— Main sequence ———
log "Starting monthly audit completion"

setup
write_prompt
scan_and_run

total_done
log "Done"
