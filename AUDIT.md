# Code Audit — configuration
> Generated: 2026-03-05

## Summary
A macOS dotfiles and automation repo with a setup script, nightly audit runner, and weekly creative build orchestrator. The shell scripts are well-structured with shared utilities, but contain several bugs in parallelisation logic, unsafe cleanup operations, and missing error handling that could cause data loss or silent failures.

## Code Smells
- [ ] `write_prompt` duplicates the entire audit prompt as a heredoc inside the script rather than shipping it as a standalone file — `scripts/nightly.sh:27-93`
- [ ] `write_prompt` in weekly script similarly embeds a 100-line prompt as a heredoc — `scripts/weekly.sh:25-128`
- [ ] `PARALLEL_PIDS`, `PARALLEL_NAMES`, `PARALLEL_STARTS` use string-delimited lists with different separators (space vs `|`) making the logic fragile and hard to follow — `scripts/utils.sh:36-49`
- [x] `README.md` contains an unrelated "python hello world" section that appears to be leftover test content — `README.md:10-13`
- [ ] `step_done` relies on global `STEP_NAME` and `STEP_START` variables, which break when `parallel_step` runs functions that call `step`/`step_done` in subshells — `scripts/utils.sh:14-24`

## Possible Bugs
- [ ] **Off-by-one in `wait_parallel_steps`**: `_i` starts at 1 then increments to 2 before the first `cut`, so the first parallel step name/start is never retrieved (field 1 is always empty due to leading `|`/space) — `scripts/utils.sh:53-56`
- [ ] **`parallel_step` runs functions in subshells but `brew_bundle` calls `step`/`step_done`** which set global variables — these writes are lost in the subshell, and `step_done` in the background job uses stale `STEP_START` from the parent — `scripts/setup.sh:37-47` + `scripts/utils.sh:40-50`
- [x] **Homebrew install URL is wrong**: `https://brew.sh/install` is not the raw install script; the correct URL is `https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh` — `scripts/setup.sh:32`
- [ ] **`hidutil` key remap doesn't persist across reboots** — the `configure_macos_defaults` function sets it at runtime but provides no LaunchAgent to re-apply it — `scripts/setup.sh:99`
- [x] **`maintenance` deletes `dist/` directories unconditionally** — this will destroy production build outputs in projects that use `dist/` as a tracked output directory (e.g. npm packages) — `scripts/weekly.sh:170`
- [ ] **`maintenance` deletes all `node_modules/`** under `~/Developer` — running projects or dev servers will break silently — `scripts/weekly.sh:168`
- [ ] **`needs_audit` uses `stat -f %m`** which is macOS-specific and returns modification time in seconds since epoch, but will fail on GNU/Linux `stat` — `scripts/nightly.sh:115`
- [ ] **`nightly.sh` uses `cd "$_dir"` inside `audit_project`** which changes the working directory for the main shell process; subsequent loop iterations may be affected — `scripts/nightly.sh:134`
- [x] **`bootstrap_zshenv` overwrites `~/.zshenv`** entirely if `ZDOTDIR` is not found, destroying any existing content — `scripts/setup.sh:57`
- [x] **Weekly `run_claude` uses `--allowedTools "...Search..."`** but `Search` is not a valid Claude Code tool name (should be `Grep` or `Glob`) — `scripts/weekly.sh:138`

## Improvements
- [ ] Add `set -eu` to `setup.sh`, `nightly.sh`, and `weekly.sh` — only `utils.sh` has it, and sourcing it doesn't propagate `set -e` to scripts that use `#!/bin/sh` without it — `scripts/setup.sh:1`, `scripts/nightly.sh:1`, `scripts/weekly.sh:1`
- [ ] Replace the string-delimited parallel tracking with indexed temporary files or arrays to avoid fragile `cut`-based parsing — `scripts/utils.sh:36-69`
- [ ] Add a `--dry-run` flag to `maintenance` so users can preview what will be deleted before running destructively — `scripts/weekly.sh:145-189`
- [x] Add `bat` to the Brewfile — `.zshrc` aliases `cat` to `bat` but `bat` is not installed via Brewfile — `Brewfile` / `zsh/.zshrc:8`
- [x] The `WORK_DIR` path in `weekly.sh` (`~/Work/claude`) differs from the prompt's stated output path (`~/Developer/Work/claude/`) — should be the latter — `scripts/weekly.sh:10` vs `scripts/weekly.sh:114`
- [ ] `nightly.sh` doesn't capture or report Claude's exit code — a failing audit silently continues — `scripts/nightly.sh:134-141`
- [x] `.zshrc` hardcodes the Rust toolchain path `stable-aarch64-apple-darwin` — this breaks on x86 Macs or if the toolchain triple changes — `zsh/.zshrc:1` ensure it uses `rustup default` or similar to resolve the path dynamically, cargo doesn't actually have any bin files in it.
- [ ] Remove all docker related code from `weekly.sh` — `scripts/weekly.sh:176`
- [x] No cron/launchd configuration files exist in the repo despite comments referencing them, ensure all scripts have proper launchd files, keep in `scripts/launchd/` — `scripts/nightly.sh:4`, `scripts/weekly.sh:4`.
- [ ] `setup.sh` says launchd filess are installed but running `launchctl list` shows just `nfs-data-sync`.

## Possible Next Features
- [x] Add LaunchAgent plist files for nightly, weekly, and afternoon scripts, with an install step in `setup.sh`
- [x] Add LaunchAgent plist for `scripts/afternoon.sh` — runs daily at 16:00, finds all AUDIT.md files, completes tasks, generates `~/Developer/SUMMARY.md`. Label: `com.user.afternoon-audit`, plist at `~/Library/LaunchAgents/com.user.afternoon-audit.plist`
- [ ] Add a `teardown.sh` or `uninstall.sh` to reverse what `setup.sh` does
- [ ] Add shellcheck CI (GitHub Action) to catch shell script bugs automatically
- [ ] Add a notification/summary report at the end of the nightly audit (e.g. how many projects audited, any failures) place at `~/Developer/AUDIT.md` include links to other `AUDIT.md` files for more details.
