# Copilot Instructions

## Build, Test, Lint
- **Setup (full integration run):** `sudo ./setup.sh`
- **Teardown:** `sudo ./uninstall.sh` (add `--all` to remove installed tools)
- **Targeted checks (used in CI/README):**
  - Apache config validation: `sudo apachectl configtest`
  - Rebuild a site binary: `cd ~/Developer/sites/<name> && swift build -c release`
- **CI reference:** `.github/workflows/test-setup.yml` runs `sudo -E ./setup.sh` and then verifies installed tools/configs.  
There is no separate lint or unit-test runner at the repo root.

## High-level Architecture
- This repo is a macOS dev environment manager. `setup.sh` installs dotfiles, tools, Apache config, cloudflared config, launchd agents, and initializes a shared SQLite state DB at `~/Library/Application Support/com.mac9sb/state.db`.
- `sites/` and `tooling/` are Git submodules; submodule directories are the source of truth for what gets configured.
- Runtime is coordinated by two long-running scripts:
  - `utilities/scripts/sites-watcher.sh` scans `~/Developer/sites` and classifies each site as **static** (`.output/`) or **server** (Swift release binary).
  - `utilities/scripts/server-manager.sh` supervises server binaries, runs them from `<exec>.run`, keeps `<exec>.bak` for rollback, performs health checks, and persists PIDs/ports to SQLite.
- Apache routing is generated from templates in `utilities/apache/` and uses virtual hosts + path-based routing for local dev. Cloudflare ingress is synced from `utilities/cloudflared/config.yml` between `# sites-watcher:BEGIN/END` markers.

## Key Conventions
- **Site naming drives routing:**
  - Directory with a dot (e.g., `sites/cool-app.com/`) → custom domain.
  - Directory without a dot (e.g., `sites/api/`) → subdomain of the primary domain.
  - The primary domain is read from the `# primary-domain: ...` comment in `utilities/cloudflared/config.yml`.
- **Site classification:**
  - `.output/` present → static site.
  - `.build/release/<exec>` or `.build/<triple>/release/<exec>` present → server site.
  - Executable name comes from the first `.executableTarget` in `Package.swift` (see `db.sh` helpers).
- **Shared state:** all watchers/managers use `utilities/scripts/db.sh` and the single SQLite DB (WAL mode) for atomic coordination.
- **Server restarts:** `utilities/scripts/restart-server.sh <name>` queues a restart in SQLite and signals `server-manager` (SIGUSR1).
- **Template rendering:** `render_template` replaces `{{KEY}}` placeholders via `sed` (used across setup and watcher scripts).
- **Submodules:** avoid `git -C sites/<name> pull`; use `git submodule update --remote --merge` to keep submodule tracking intact.
