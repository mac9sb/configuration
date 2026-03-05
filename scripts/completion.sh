#!/bin/sh
# ─────────────────────────────────────────────
# Weekly Audit Completion
# Runs every Wednesday at 16:00 via cron
# Finds all AUDIT.md files, completes tasks, generates summary
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/utils.sh"

log "PATH=$PATH"

DEVELOPER_DIR="$HOME/Developer"
LOG_DIR="/tmp"
SUMMARY_FILE="$DEVELOPER_DIR/SUMMARY.md"
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
  cat > "$PROMPT_FILE" <<'PROMPT'
You are a senior staff engineer working in the '~/Developer' directory.

## Your Task

Your primary responsibility is to complete tasks in the 'AUDIT.md' files that will be provided to you. For each file:

1.  Change to the directory containing the 'AUDIT.md' file (e.g., `cd $(dirname /path/to/AUDIT.md)`).
2.  Check if it contains any unchecked tasks (`- [ ]`). If not, skip it.
3.  Read the 'AUDIT.md' file.
4.  For every unchecked task ('- [ ]'), attempt to complete it by reading referenced file(s), understanding the issue, and making the fix or improvement described.
5.  Mark the checkbox as done ('- [x]') in the 'AUDIT.md' file once the task is complete.

Important: Do NOT generate any summary file or final report. The main shell script will handle the overall summary generation.

## Rules

- Only attempt tasks you can confidently complete correctly.
- If a task is ambiguous or risky (e.g. "delete all X"), skip it and leave it unchecked.
- Do not introduce new bugs. Run any available tests after making changes.
- Do not modify AUDIT.md beyond checking off completed items.
- Be conservative — a skipped task is better than a broken codebase.
PROMPT
  step_done
}

# ——— Step: Count completed tasks in an AUDIT.md ———
count_tasks() {
  _file=$1
  _total=$(grep -c '^\- \[.\]' "$_file" 2>/dev/null) || _total=0
  _done=$(grep -c '^\- \[x\]' "$_file" 2>/dev/null) || _done=0
  _remaining=$((_total - _done))
  echo "$_done $_remaining $_total"
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
    --max-turns 100 \
    --allowedTools "Bash,Read,Write,Edit,Glob,Grep" \
    --print \
    < "$PROMPT_FILE" \
    > "$_log" 2>&1) || warn "Claude session failed for audit completion"
  log "Finished single Claude session for audit tasks"

  step_done
}

# ——— Step: Generate summary ———
generate_summary() {
  step "Generating summary at $SUMMARY_FILE"

  _date=$(date +%Y-%m-%d)
  _audit_list=$(mktemp)
  find "$DEVELOPER_DIR" -maxdepth 4 -name "AUDIT.md" -not -path '*/.*' | sort > "$_audit_list"

  cat > "$SUMMARY_FILE" <<EOF
# Audit Summary
> Generated: $_date

EOF

  _total_done=0
  _total_remaining=0

  while IFS= read -r _audit_file; do
    _dir=$(dirname "$_audit_file")
    _name=$(basename "$_dir")
    _rel_path="${_audit_file#"$DEVELOPER_DIR"/}"

    _counts=$(count_tasks "$_audit_file")
    _done=$(echo "$_counts" | cut -d' ' -f1)
    _remaining=$(echo "$_counts" | cut -d' ' -f2)
    _total=$(echo "$_counts" | cut -d' ' -f3)

    _total_done=$((_total_done + _done))
    _total_remaining=$((_total_remaining + _remaining))

    printf '## [%s](%s)\n' "$_name" "$_rel_path" >> "$SUMMARY_FILE"
    printf '- **%s/%s** tasks completed' "$_done" "$_total" >> "$SUMMARY_FILE"
    if [ "$_remaining" -gt 0 ]; then
      printf ' (%s remaining)' "$_remaining" >> "$SUMMARY_FILE"
    fi
    printf '\n\n' >> "$SUMMARY_FILE"

    # List completed tasks
    if [ "$_done" -gt 0 ]; then
      grep '^\- \[x\]' "$_audit_file" >> "$SUMMARY_FILE" 2>/dev/null || true
      printf '\n' >> "$SUMMARY_FILE"
    fi
  done < "$_audit_list"

  rm -f "$_audit_list"

  # Prepend totals to summary section
  _summary_line="**Totals:** $_total_done completed, $_total_remaining remaining"
  sed -i '' "s/^> Generated: $_date$/> Generated: $_date\\
\\
$_summary_line/" "$SUMMARY_FILE"

  log "Summary written: $_total_done completed, $_total_remaining remaining"
  step_done
}

# ——— Main sequence ———
log "Starting weekly audit completion"

setup
write_prompt
scan_and_run
generate_summary

total_done
log "Done"
