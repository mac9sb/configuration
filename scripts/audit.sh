#!/bin/sh
# ─────────────────────────────────────────────
# Weekly Code Audit
# Runs every Wednesday at 11:00 via cron
# Scans ~/Developer projects and creates AUDIT.md
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/utils.sh"

DEVELOPER_DIR="$HOME/Developer"
LOG_DIR="/tmp"
PROMPT_FILE="$HOME/.claude-weekly/prompt.md"
STALE_DAYS=14

total_start

# ——— Step: Setup ———
setup() {
  step "Setting up weekly audit"
  mkdir -p "$(dirname "$PROMPT_FILE")"
  step_done
}

# ——— Step: Write prompt ———
write_prompt() {
  step "Writing audit prompt"
  cat > "$PROMPT_FILE" <<'PROMPT'
You are a senior staff engineer performing a thorough code audit.

## Your Task

You will be provided with a list of project directories. For each project in the list:

1.  Navigate to the project directory (e.g., `cd /path/to/project`).
2.  Audit the code in that directory.
3.  Produce a structured AUDIT.md file in that project directory.

## What to Look For

### Code Smells
- Duplicated logic, dead code, overly complex functions
- Poor naming, magic numbers, deeply nested conditionals
- Missing or inconsistent error handling
- Tight coupling, god objects, feature envy

### Possible Bugs
- Race conditions, off-by-one errors, null/undefined handling
- Resource leaks (file handles, connections, memory)
- Incorrect boundary conditions, unvalidated inputs
- Security vulnerabilities (injection, XSS, hardcoded secrets)

### Improvements
- Performance bottlenecks and unnecessary allocations
- Missing tests or low-coverage areas
- Outdated dependencies with known issues
- Opportunities to simplify or reduce complexity

### Possible Next Features
- Natural extensions based on the existing codebase
- Missing integrations that would add clear value
- Developer experience improvements

## Output Format

Write AUDIT.md with this structure:

```markdown
# Code Audit — <project name>
> Generated: <date>

## Summary
<2-3 sentence overview of project health>

## Code Smells
- [ ] <description> — `path/to/file:line`
- [ ] ...

## Possible Bugs
- [ ] <description> — `path/to/file:line`
- [ ] ...

## Improvements
- [ ] <description> — `path/to/file:line`
- [ ] ...

## Possible Next Features
- [ ] <description>
- [ ] ...
```

Use checkbox format (`- [ ]`) so items can be checked off as addressed.
Be specific — always reference file paths and line numbers where applicable.
Prioritise findings by severity within each section.
Only report genuine issues, not style nitpicks.
PROMPT
  step_done
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
  _age_seconds=$(( $(date +%s) - $(stat -f %m "$_audit") ))
  _stale_seconds=$(( STALE_DAYS * 86400 ))

  if [ "$_age_seconds" -gt "$_stale_seconds" ]; then
    warn "Stale AUDIT.md in $(basename "$_dir") ($((_age_seconds / 86400)) days old)"
    osascript -e "display notification \"AUDIT.md in $(basename "$_dir") is $((_age_seconds / 86400)) days old and unreviewed\" with title \"Weekly Audit\" subtitle \"Please review\""
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

    if needs_audit "$dir"; then
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
  echo -e "\\nProjects to audit (absolute paths):" >> "$PROMPT_FILE"
  cat "$_project_list_for_prompt" >> "$PROMPT_FILE"
  rm -f "$_project_list_for_prompt"

  _log="$LOG_DIR/weekly-audit-all.log"

  log "Launching Claude for $_projects_to_audit projects"
  (cd "$DEVELOPER_DIR" && claude \
    --model claude-opus-4-6 \
    --max-turns 100 \
    --allowedTools "Bash,Read,Write,Edit,Glob,Grep" \
    --print \
    < "$PROMPT_FILE" \
    > "$_log" 2>&1) || warn "Claude session failed for audit completion"
  log "Finished single Claude session for all project audits"

  log "Audited: $_projects_to_audit | Skipped: $_projects_skipped"
  step_done
}

# ——— Main sequence ———
log "Starting weekly code audit"

setup
write_prompt
scan_projects

total_done
log "Done"
