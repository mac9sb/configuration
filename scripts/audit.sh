#!/bin/sh
set -eu
# ─────────────────────────────────────────────
# Monthly Code Audit
# Runs on the 2nd of each month at 11:00 via launchd
# Scans ~/Developer projects and creates AUDIT.md
# Skips projects marked as "Maintenance" in TRACKER.md
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/utils.sh"

DEVELOPER_DIR="$HOME/Developer"
LOG_DIR="/tmp"
PROMPT_FILE="$HOME/.claude-weekly/prompt.md"
STALE_DAYS=45
TRACKER_FILE="$DEVELOPER_DIR/TRACKER.md"

total_start

# ——— Step: Setup ———
setup() {
  step "Setting up monthly audit"
  mkdir -p "$(dirname "$PROMPT_FILE")"
  step_done
}

# ——— Step: Write prompt ———
write_prompt() {
  step "Writing audit prompt"
  _prompt_src="$SCRIPT_DIR/prompts/audit.md"
  if [ ! -f "$_prompt_src" ]; then
    die "Audit prompt file not found: $_prompt_src"
  fi
  cp "$_prompt_src" "$PROMPT_FILE"
  step_done
}

# ——— Get file modification time (portable) ———
file_mtime() {
  if stat -f %m "$1" >/dev/null 2>&1; then
    # macOS / BSD stat
    stat -f %m "$1"
  else
    # GNU stat (Linux)
    stat -c %Y "$1"
  fi
}

# ——— Check if AUDIT.md needs work ———
# Returns 0 (true) if directory should be audited
needs_audit() {
  _dir=$1
  _audit="$_dir/AUDIT.md"

  # No AUDIT.md — needs audit
  if [ ! -f "$_audit" ]; then
    return 0
  fi

  # Check if any checkboxes have been ticked (edited)
  if grep -q '\- \[x\]' "$_audit" 2>/dev/null; then
    # User has engaged with it — re-audit
    return 0
  fi

  # AUDIT.md exists and is unedited — skip
  # But check if it's stale (older than STALE_DAYS)
  _age_seconds=$(( $(date +%s) - $(file_mtime "$_audit") ))
  _stale_seconds=$(( STALE_DAYS * 86400 ))

  if [ "$_age_seconds" -gt "$_stale_seconds" ]; then
    warn "Stale AUDIT.md in $(basename "$_dir") ($((_age_seconds / 86400)) days old)"
    osascript -e "display notification \"AUDIT.md in $(basename "$_dir") is $((_age_seconds / 86400)) days old and unreviewed\" with title \"Weekly Audit\" subtitle \"Please review\"" 2>/dev/null || true
  fi

  return 1
}

# ——— Check if project is marked as Maintenance in TRACKER.md ———
# Returns 0 (true) if project should be skipped
is_maintenance() {
  _dir=$1
  _basename=$(basename "$_dir")

  if [ ! -f "$TRACKER_FILE" ]; then
    return 1
  fi

  # Check if the project row in TRACKER.md contains "Maintenance"
  if grep -i "|\s*\[${_basename}\]" "$TRACKER_FILE" 2>/dev/null | grep -qi "maintenance"; then
    return 0
  fi

  # Also check for "Maintenance" in the detail section header
  if grep -qi "Phase.*Maintenance" "$TRACKER_FILE" 2>/dev/null; then
    # More targeted: check if the basename appears near a Maintenance marker
    if grep -B5 -i "maintenance" "$TRACKER_FILE" 2>/dev/null | grep -qi "$_basename"; then
      return 0
    fi
  fi

  return 1
}

# ——— Check if directory is a project ———
is_project() {
  _d=$1
  [ -d "$_d/.git" ] && return 0
  for _f in package.json Cargo.toml go.mod pyproject.toml Makefile \
            Package.swift Brewfile Gemfile build.gradle pom.xml \
            composer.json mix.exs deno.json Justfile CMakeLists.txt \
            flake.nix CLAUDE.md; do
    [ -f "$_d/$_f" ] && return 0
  done
  return 1
}

# ——— Check if dir is inside an already-found project ———
is_nested_project() {
  _candidate=$1
  _found_file=$2
  while IFS= read -r _parent; do
    case "$_candidate" in
      "$_parent"/*) return 0 ;;
    esac
  done < "$_found_file"
  return 1
}

# ——— Step: Scan and audit projects with a single Claude instance ———
scan_projects() {
  step "Scanning projects in $DEVELOPER_DIR and preparing prompt for Claude"

  _project_list_for_prompt=$(mktemp)
  _projects_to_audit=0
  _projects_skipped=0
  _claude_exit=0

  _dirlist=$(mktemp)
  _found_projects=$(mktemp) # Stores top-level projects to avoid auditing nested ones
  : > "$_found_projects"

  find "$DEVELOPER_DIR" -maxdepth 4 -type d -not -path '*/.*' | sort > "$_dirlist"
  while IFS= read -r dir; do
    is_project "$dir" || continue

    if is_nested_project "$dir" "$_found_projects"; then
      continue
    fi

    printf '%s\n' "$dir" >> "$_found_projects"

    if is_maintenance "$dir"; then
      log "Skipping maintenance project: $(basename "$dir")"
      _projects_skipped=$((_projects_skipped + 1))
    elif needs_audit "$dir"; then
      echo "- $dir" >> "$_project_list_for_prompt"
      _projects_to_audit=$((_projects_to_audit + 1))
    else
      _projects_skipped=$((_projects_skipped + 1))
    fi
  done < "$_dirlist"
  rm -f "$_dirlist" "$_found_projects"

  if [ "$_projects_to_audit" -eq 0 ]; then
    log "No projects requiring audit found. Skipping Claude session."
    rm -f "$_project_list_for_prompt"
    step_done
    return 0
  fi

  # Append the list of projects to the prompt
  printf '\nProjects to audit (absolute paths):\n' >> "$PROMPT_FILE"
  cat "$_project_list_for_prompt" >> "$PROMPT_FILE"
  rm -f "$_project_list_for_prompt"

  _log="$LOG_DIR/weekly-audit-all.log"

  log "Launching Claude for $_projects_to_audit projects"
  # Run Claude in a subshell to avoid cd affecting the parent process
  if (cd "$DEVELOPER_DIR" && claude \
    --model claude-opus-4-6 \
    --max-turns 100 \
    --allowedTools "Bash,Read,Write,Edit,Glob,Grep" \
    --print \
    < "$PROMPT_FILE" \
    > "$_log" 2>&1); then
    log "Claude session completed successfully"
  else
    _claude_exit=$?
    warn "Claude session failed with exit code $_claude_exit"
  fi
  log "Finished single Claude session for all project audits"

  # Generate summary report
  _summary="$DEVELOPER_DIR/AUDIT.md"
  _audit_count=0
  _failure_count=0
  _audit_report=$(mktemp)

  find "$DEVELOPER_DIR" -maxdepth 4 -name "AUDIT.md" -not -path '*/.*' | sort > "$_audit_report.list" 2>/dev/null || true
  while IFS= read -r _af; do
    [ -n "$_af" ] || continue
    _project_name=$(basename "$(dirname "$_af")")
    _total_tasks=$(grep -c '^\- \[' "$_af" 2>/dev/null || echo "0")
    _done_tasks=$(grep -c '^\- \[x\]' "$_af" 2>/dev/null || echo "0")
    _remaining=$((_total_tasks - _done_tasks))
    printf '- [%s](%s): %s/%s completed, %s remaining\n' \
      "$_project_name" "$_af" "$_done_tasks" "$_total_tasks" "$_remaining" >> "$_audit_report"
    _audit_count=$((_audit_count + 1))
  done < "$_audit_report.list"
  rm -f "$_audit_report.list"

  if [ "$_audit_count" -gt 0 ]; then
    {
      printf '# Audit Summary\n'
      printf '> Generated: %s\n\n' "$(date +%Y-%m-%d)"
      printf '## Results\n\n'
      printf 'Audited: %s | Skipped: %s | Claude exit: %s\n\n' \
        "$_projects_to_audit" "$_projects_skipped" "$_claude_exit"
      printf '## Projects\n\n'
      cat "$_audit_report"
    } > "$_summary"
    log "Summary written to $_summary"
  fi
  rm -f "$_audit_report"

  if [ "$_claude_exit" -ne 0 ]; then
    _failure_count=$((_failure_count + 1))
  fi

  log "Audited: $_projects_to_audit | Skipped: $_projects_skipped | Failures: $_failure_count"

  # Send notification
  osascript -e "display notification \"Audited $_projects_to_audit projects, skipped $_projects_skipped\" with title \"Monthly Audit Complete\"" 2>/dev/null || true

  step_done
}

# ——— Main sequence ———
log "Starting monthly code audit"

setup
write_prompt
scan_projects

total_done
log "Done"
