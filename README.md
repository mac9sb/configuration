# Configuration Files

## Quick Start

```sh
git clone https://github.com/mac9sb/config.git ~/.config
~/.config/scripts/setup.sh
```

## Scheduled Tasks (launchd)

This repository includes several scripts that are scheduled to run automatically using `launchd` on macOS. These tasks are managed via `.plist` files located in `scripts/launchd/` and are installed/loaded by `scripts/setup.sh`.

### Installation and Management

To install or refresh the launchd agents, simply run:
```sh
~/.config/scripts/setup.sh
```
This will symlink the `.plist` files to `~/Library/LaunchAgents/` and load them.

### Task Details

#### 1. NFS Data Synchronization (`com.mac.nfs-data-sync.plist`)
*   **Purpose:** Keeps the `~/Work/nfs-data-mac` directory synchronized with a remote NFS share.
*   **Schedule:** Triggered by file system changes in `~/Work/nfs-data-mac` (throttled to run no more frequently than every 5 seconds).
*   **Script:** `scripts/sync.sh`
*   **Logs:** `/tmp/nfs-data-mac-sync.log`

#### 2. Daily Audit Completion (`com.user.audit-completion.plist`)
*   **Purpose:** Scans for `AUDIT.md` files with unchecked tasks across `~/Developer` projects and attempts to complete them using a single Claude instance. It then generates a summary.
*   **Schedule:** Daily at 16:00.
*   **Script:** `scripts/completion.sh`
*   **Logs:** `/tmp/com.user.audit-completion.log`

#### 3. Weekly Code Audit (`com.user.weekly-audit.plist`)
*   **Purpose:** Scans `~/Developer` projects for code smells, bugs, improvements, and possible next features, then creates or updates `AUDIT.md` files in relevant project directories.
*   **Schedule:** Every Wednesday at 11:00.
*   **Script:** `scripts/audit.sh`
*   **Logs:** `/tmp/com.user.weekly-audit.log`

#### 4. Weekly Orchestrator (`com.user.weekly-orchestrator.plist`)
*   **Purpose:** Orchestrates weekly maintenance tasks, including cleaning up `node_modules` and `dist` directories, updating Homebrew, and other general system maintenance.
*   **Schedule:** Every Wednesday at 16:00.
*   **Script:** `scripts/weekly.sh`
*   **Logs:** `/tmp/com.user.weekly-orchestrator.log`
