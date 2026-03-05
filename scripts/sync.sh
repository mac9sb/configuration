#!/bin/sh
set -eu
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

LOCKFILE="/tmp/nfs-data-mac-sync.pid"
if [ -f "$LOCKFILE" ]; then
  old_pid=$(cat "$LOCKFILE")
  if kill -0 "$old_pid" 2>/dev/null; then
    echo "Sync already running (pid $old_pid), skipping"
    exit 0
  fi
  rm -f "$LOCKFILE"
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT INT TERM HUP

BASE_DIR="/Users/mac/Work/nfs-data-mac"
REMOTE="mac@dav.internal:/nfs/data/mac"

rsync -az --mkpath --itemize-changes --exclude-from=- \
  "$BASE_DIR/" "$REMOTE/" <<EOF
.DS_Store
.git/
.claude/
.vscode/
.ruff_cache/
.mypy_cache/
.basedpyright/
__pycache__/
*.pyc
*.pyo
*.egg-info/
.venv/
dist/
build/
*.swp
*~
data/extract/
data/transform/
output/
rejects/
backups/
logs/
input/
*.tar.gz
EOF

echo "Sync complete"
