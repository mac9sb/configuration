#!/bin/zsh
set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
    printf '%s\n' "This maintenance script supports only macOS." >&2
    exit 1
fi

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

run_cmd() {
    printf '\n==> %s\n' "$*"
    if [ "$DRY_RUN" -eq 0 ]; then
        "$@"
    fi
}

clear_dir_contents() {
    local dir="$1"
    local -a entries

    if [ ! -d "$dir" ]; then
        return
    fi

    entries=("$dir"/*(N) "$dir"/.[!.]*(N) "$dir"/..?*(N))
    if [ "${#entries[@]}" -eq 0 ]; then
        return
    fi

    printf '\n==> Clearing %s\n' "$dir"
    if [ "$DRY_RUN" -eq 0 ]; then
        rm -rf -- "${entries[@]}"
    fi
}

if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "Starting maintenance (dry run)..."
else
    printf '%s\n' "Starting maintenance..."
fi

for dir in \
    "$HOME/.Trash" \
    "$HOME/.cache" \
    "$HOME/Library/Caches" \
    "$HOME/Library/Logs" \
    "$HOME/Library/Developer/Xcode/DerivedData" \
    "$HOME/Library/Developer/CoreSimulator/Caches"
do
    clear_dir_contents "$dir"
done

if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if command -v mise >/dev/null 2>&1; then
    run_cmd mise upgrade
    run_cmd mise prune -y
else
    printf '\n%s\n' "Skipping mise: command not found."
fi

if command -v brew >/dev/null 2>&1; then
    run_cmd brew update
    run_cmd brew upgrade
    run_cmd brew autoremove
    run_cmd brew cleanup --prune=all -s
else
    printf '\n%s\n' "Skipping Homebrew: command not found."
fi

printf '\n%s\n' "Maintenance complete."
