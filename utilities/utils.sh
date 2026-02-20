#!/bin/sh

# ── Logging helpers ─────────────────────────────────────────────────────────
# Lightweight wrappers for colored logging used throughout setup/uninstall
info() {
    printf "\033[1;34m[INFO]\033[0m  %s\n" "$1"
}

success() {
    printf "\033[1;32m[OK]\033[0m    %s\n" "$1"
}

warn() {
    printf "\033[1;33m[WARN]\033[0m  %s\n" "$1"
}

# Fatal error + exit
error() {
    printf "\033[1;31m[ERROR]\033[0m %s\n" "$1"
    exit 1
}

# Confirmation prompt (y/N)
confirm() {
    printf "\033[1;33m[CONFIRM]\033[0m  %s [y/N]: " "$1"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Git submodule checks ────────────────────────────────────────────────────
# Returns paths of submodules matching each check; used by the pre-push hook
check_dirty_submodules() {
    git submodule foreach --quiet '
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            printf "%s\n" "$sm_path"
        fi
    '
}

# Find modified files whose parent is a submodule
check_unstaged_submodules() {
    git diff --name-only --diff-filter=M 2>/dev/null | while IFS= read -r _file; do
        if git ls-files --stage "$_file" 2>/dev/null | grep -q '^160000'; then
            printf '%s\n' "$_file"
        fi
    done
}

# Detect detached HEADs in submodules where the parent expects a different commit
check_detached_submodules() {
    git submodule foreach --quiet '
        if ! git symbolic-ref -q HEAD >/dev/null 2>&1; then
            _parent_commit="$(cd "$toplevel" && git ls-tree HEAD "$sm_path" 2>/dev/null | awk "{print \\\$3}")"
            _current_commit="$(git rev-parse HEAD 2>/dev/null)"
            if [ "$_parent_commit" != "$_current_commit" ]; then
                printf "%s (parent expects %.7s, submodule at %.7s)\n" "$sm_path" "$_parent_commit" "$_current_commit"
            fi
        fi
    '
}

# ── Environment resolution ──────────────────────────────────────────────────
# Determine the real invoking user/home when scripts are run under sudo
resolve_paths() {
    REAL_USER="${SUDO_USER:-$(id -un)}"
    if [ "$REAL_USER" = "root" ]; then
        REAL_USER="$(/usr/bin/logname 2>/dev/null || /usr/bin/stat -f%Su /dev/console 2>/dev/null || echo root)"
    fi
    REAL_HOME="$(eval echo "~${REAL_USER}")"
    if [ "$REAL_USER" = "root" ] && [ -n "${HOME:-}" ] && [ "$HOME" != "$REAL_HOME" ] && [ -d "$HOME" ]; then
        REAL_HOME="$HOME"
        REAL_USER="$(/usr/bin/stat -f%Su "$REAL_HOME" 2>/dev/null || echo "$REAL_USER")"
    fi
    REAL_GROUP="$(id -gn "${REAL_USER}" 2>/dev/null || echo staff)"
    export REAL_USER REAL_HOME REAL_GROUP
}

# ── Task runner helper ──────────────────────────────────────────────────────
# `task "Name" check_fn apply_fn` prints the name, runs the check and (if
# needed) runs the apply function and reports result.
task() {
    _name="$1"
    _check_fn="$2"
    _apply_fn="$3"

    info "$_name"
    if "$_check_fn"; then
        success "  Already applied"
        return 0
    fi

    if "$_apply_fn"; then
        success "  Applied"
        return 0
    fi

    error "  Failed"
}

# ── CLI argument parsing ───────────────────────────────────────────────────
# Minimal parser supporting GNU-style `--flag`, `--key=value`, and short `-f`
parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --?*)
                varname="$(echo "${1#--}" | tr '[:lower:]-' '[:upper:]_')"
                eval "$varname=true"
                ;;
            -?*)
                shortflags="${1#-}"
                for ((i=0; i<${#shortflags}; i++)); do
                    varname="$(echo "${shortflags:$i:1}" | tr '[:lower:]' '[:upper:]')"
                    eval "$varname=true"
                done
                ;;
            --*=*)
                varname="$(echo "${1%%=*}" | sed 's/^--//' | tr '[:lower:]-' '[:upper:]_')"
                value="${1#*=}"
                eval "$varname=\"$value\""
                ;;
            --*)
                varname="$(echo "${1#--}" | tr '[:lower:]-' '[:upper:]_')"
                if [ -n "$2" ] && [[ ! "$2" =~ ^- ]]; then
                    eval "$varname=\"$2\""
                    shift
                else
                    eval "$varname=true"
                fi
                ;;
            *)
                ;;
        esac
        shift
    done
}

# ── Paths & defaults ───────────────────────────────────────────────────────
export USERNAME="mac9sb"
export DEV_DIR="$HOME/Developer"
export SITES_DIR="$DEV_DIR/sites"
export TOOLING_DIR="$DEV_DIR/tooling"
export UTILITIES_DIR="$DEV_DIR/utilities"
export DOTFILES_DIR="$UTILITIES_DIR/dotfiles"
export STATE_DIR="$HOME/Library/Application Support/com.$USERNAME"
export LOG_DIR="$HOME/Library/Logs/com.$USERNAME"
export LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
export HTTPD_CONF="/etc/apache2/httpd.conf"
export CUSTOM_CONF="/etc/apache2/extra/custom.conf"
export APACHE_LOG_DIR="/var/log/apache2/sites"
