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

## Rules

- Only attempt tasks you can confidently complete correctly.
- If a task is ambiguous or risky (e.g. "delete all X"), skip it and leave it unchecked.
- Do not introduce new bugs. Run any available tests after making changes.
- Do not modify AUDIT.md beyond checking off completed items.
- Be conservative — a skipped task is better than a broken codebase.

## Summary Generation

After completing all audit tasks, generate a summary file at '~/Developer/SUMMARY.md'.

The summary should be a detailed, logical report — not just a list of checkboxes. For each project with an AUDIT.md:

1. State the project name and path
2. Report how many tasks were completed vs remaining (e.g. "7/10 completed, 3 remaining")
3. For completed tasks: write a brief sentence explaining what was fixed and why it matters
4. For skipped tasks: explain why they were skipped (ambiguous, risky, requires external action, etc.)
5. Include an overall summary at the top with totals and a high-level narrative of what was accomplished

Format the file as clean Markdown with a date header. Keep it concise but informative — someone reading it should understand what changed and what still needs attention without having to read each AUDIT.md individually.

## Project Tracker Update

After generating the summary, update '~/Developer/PROJECT_TRACKER.md':

1. Update the '> Last updated:' date to today
2. Scan all project directories under '~/Developer' for any new projects not yet listed — add them following the existing format (overview table row + detail section with phase, stack, deployment, repo link, README link)
3. Update phase/progress percentages if audit work meaningfully advanced a project
4. If a project has a new README, repo, or deployment since the last update, add the link
5. Do not remove or reorder existing entries — only add and update
PROMPT
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
    --max-turns 100 \
    --allowedTools "Bash,Read,Write,Edit,Glob,Grep" \
    --print \
    < "$PROMPT_FILE" \
    > "$_log" 2>&1) || warn "Claude session failed for audit completion"
  log "Finished single Claude session for audit tasks"

  step_done
}

# ——— Main sequence ———
log "Starting weekly audit completion"

setup
write_prompt
scan_and_run

total_done
log "Done"
