#!/bin/zsh
set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
    printf '%s\n' "This maintenance script supports only macOS." >&2
    exit 1
fi

DRY_RUN=0
AGGRESSIVE=0

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            ;;
        --aggressive)
            AGGRESSIVE=1
            ;;
        *)
            printf '%s\n' "Usage: $0 [--dry-run] [--aggressive]" >&2
            exit 1
            ;;
    esac
done

run_cmd() {
    printf '\n==> %s\n' "$*"
    if [ "$DRY_RUN" -eq 0 ]; then
        "$@"
    fi
}

prune_dir() {
    local dir="$1" days="$2" label="$3"

    if [ ! -d "$dir" ]; then
        return
    fi

    printf '\n==> %s (%s, older than %s days)\n' "$label" "$dir" "$days"
    if [ "$DRY_RUN" -eq 1 ]; then
        find "$dir" -mindepth 1 -mtime +"$days" -print 2>/dev/null || true
    else
        find "$dir" -mindepth 1 -mtime +"$days" -exec rm -rf -- {} + 2>/dev/null || true
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

prune_dir "$HOME/.Trash" 7 "Empty stale Trash items"
prune_dir "$HOME/.cache" 14 "Prune stale XDG cache files"
prune_dir "$HOME/Library/Caches" 14 "Prune stale macOS cache files"
prune_dir "$HOME/Library/Logs" 30 "Prune old log files"
prune_dir "$HOME/Library/Developer/Xcode/DerivedData" 7 "Prune old Xcode DerivedData"
prune_dir "$HOME/Library/Developer/CoreSimulator/Caches" 7 "Prune old CoreSimulator caches"

if [ "$AGGRESSIVE" -eq 1 ]; then
    clear_dir_contents "$HOME/.Trash"
    clear_dir_contents "$HOME/.cache"
    clear_dir_contents "$HOME/Library/Caches"
    clear_dir_contents "$HOME/Library/Developer/Xcode/DerivedData"
    clear_dir_contents "$HOME/Library/Developer/CoreSimulator/Caches"
fi

run_cmd rm -f -- "$HOME/.config/zsh/.zcompdump" "$HOME/.config/zsh/.zshrc.zwc"

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
