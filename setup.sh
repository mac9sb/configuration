#!/bin/sh
set -e

# =============================================================================
#  macOS Developer Environment Setup
#  Author: Mac (maclong9)
#
#  This script sets up a complete development environment including:
#    - Touch ID for sudo
#    - Dotfiles (symlinked from utilities/dotfiles)
#    - SSH key generation
#    - Swift (via Xcode CLI tools)
#    - CLI tooling (cloudflared, gh)
#    - Git submodule initialization
#    - Building Swift projects
#    - Apache with mod_proxy/mod_rewrite + per-site config
#    - launchd agents for server binaries (with crash retry + notification)
#    - File watchers to restart servers on binary rebuild
#    - Sites watcher launchd agent for auto-detection
#    - Cloudflare tunnel integration
#
#  Repos are managed entirely as git submodules. No hardcoded arrays —
#  everything is derived from .gitmodules and filesystem state.
# =============================================================================

GITHUB_USER="mac9sb"
GIT_EMAIL="maclong9@icloud.com"

DEV_DIR="$HOME/Developer"
SITES_DIR="$DEV_DIR/sites"
TOOLING_DIR="$DEV_DIR/tooling"
UTILITIES_DIR="$DEV_DIR/utilities"
WATCHER_DIR="$DEV_DIR/.watchers"

HTTPD_CONF="/etc/apache2/httpd.conf"
CUSTOM_CONF="/etc/apache2/extra/custom.conf"
LOG_DIR="/var/log/apache2/sites"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# --- Template directories ---
APACHE_TMPL_DIR="$UTILITIES_DIR/apache"
LAUNCHD_TMPL_DIR="$UTILITIES_DIR/launchd"
SCRIPTS_TMPL_DIR="$UTILITIES_DIR/scripts"
DOTFILES_DIR="$UTILITIES_DIR/dotfiles"

# --- Port allocation ----------------------------------------------------------
SERVER_PORT_START=8000

UID_NUM="$(id -u)"
TOTAL_STEPS=12

# =============================================================================
#  Utility Functions
# =============================================================================

info()    { printf "\033[1;34m[INFO]\033[0m  %s\n" "$1"; }
success() { printf "\033[1;32m[OK]\033[0m    %s\n" "$1"; }
warn()    { printf "\033[1;33m[WARN]\033[0m  %s\n" "$1"; }
error()   { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1"; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Renders a template file by replacing {{KEY}} placeholders with values.
# Usage: render_template <template_file> KEY=value KEY2=value2 ...
# Output is written to stdout.
render_template() {
    _tmpl_file="$1"
    shift

    if [ ! -f "$_tmpl_file" ]; then
        error "Template not found: $_tmpl_file"
    fi

    _rendered="$(cat "$_tmpl_file")"
    for _pair in "$@"; do
        _key="${_pair%%=*}"
        _val="${_pair#*=}"
        _rendered="$(printf '%s' "$_rendered" | sed "s|{{${_key}}}|${_val}|g")"
    done
    printf '%s\n' "$_rendered"
}

# =============================================================================
#  Step 1 — Touch ID for sudo
# =============================================================================

info "Step 1/${TOTAL_STEPS}: Touch ID for sudo (requires password once)"
if [ ! -f /etc/pam.d/sudo_local ] || ! grep -q "pam_tid.so" /etc/pam.d/sudo_local 2>/dev/null; then
    sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
    sudo sed -i '' 's/^#auth/auth/' /etc/pam.d/sudo_local
    success "Touch ID enabled for sudo"
else
    success "Touch ID already configured"
fi

# =============================================================================
#  Step 2 — Symlink Dotfiles
# =============================================================================

info "Step 2/${TOTAL_STEPS}: Symlinking dotfiles"

for _dotfile in zshrc vimrc gitignore gitconfig; do
    _src="$DOTFILES_DIR/$_dotfile"
    _dest="$HOME/.${_dotfile}"

    if [ ! -f "$_src" ]; then
        warn "  Dotfile source missing: $_src — skipping"
        continue
    fi

    if [ -L "$_dest" ] && [ "$(readlink "$_dest")" = "$_src" ]; then
        success "  ~/.${_dotfile} already symlinked"
    else
        if [ -e "$_dest" ] && [ ! -L "$_dest" ]; then
            mv "$_dest" "${_dest}.bak.$(date +%Y%m%d%H%M%S)"
            warn "  Backed up existing ~/.${_dotfile}"
        fi
        ln -sf "$_src" "$_dest"
        success "  ~/.${_dotfile} → $_src"
    fi
done

# SSH config is a special case (nested directory)
_ssh_config_src="$DOTFILES_DIR/ssh_config"
_ssh_config_dest="$HOME/.ssh/config"
if [ -f "$_ssh_config_src" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    if [ -L "$_ssh_config_dest" ] && [ "$(readlink "$_ssh_config_dest")" = "$_ssh_config_src" ]; then
        success "  ~/.ssh/config already symlinked"
    else
        if [ -e "$_ssh_config_dest" ] && [ ! -L "$_ssh_config_dest" ]; then
            mv "$_ssh_config_dest" "${_ssh_config_dest}.bak.$(date +%Y%m%d%H%M%S)"
            warn "  Backed up existing ~/.ssh/config"
        fi
        ln -sf "$_ssh_config_src" "$_ssh_config_dest"
        success "  ~/.ssh/config → $_ssh_config_src"
    fi
fi

# =============================================================================
#  Step 3 — SSH key
# =============================================================================

info "Step 3/${TOTAL_STEPS}: SSH key"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$HOME/.ssh/id_ed25519" -N ""
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" 2>/dev/null || ssh-add "$HOME/.ssh/id_ed25519"
    success "SSH key generated at ~/.ssh/id_ed25519"
    warn "Add this public key to GitHub:"
    cat "$HOME/.ssh/id_ed25519.pub"
    printf "\n"
else
    success "SSH key already exists"
fi

# =============================================================================
#  Step 4 — Xcode CLI Tools & Swift
# =============================================================================

info "Step 4/${TOTAL_STEPS}: Xcode Command Line Tools & Swift"
if ! xcode-select -p >/dev/null 2>&1; then
    info "Installing Xcode Command Line Tools (this may take a while)..."
    xcode-select --install 2>/dev/null || true
    until xcode-select -p >/dev/null 2>&1; do
        sleep 5
    done
    success "Xcode CLI Tools installed"
else
    success "Xcode CLI Tools already installed"
fi

if command_exists swift; then
    success "Swift available: $(swift --version 2>&1 | head -1)"
else
    error "Swift not found after Xcode CLI tools install. Install Xcode or Xcode CLI tools manually."
fi

# =============================================================================
#  Step 5 — Install cloudflared
# =============================================================================

info "Step 5/${TOTAL_STEPS}: Installing cloudflared"
if ! command_exists cloudflared; then
    CF_LATEST=$(curl -sL -o /dev/null -w '%{url_effective}' https://github.com/cloudflare/cloudflared/releases/latest | sed 's|.*/||')
    CF_PKG_URL="https://github.com/cloudflare/cloudflared/releases/download/${CF_LATEST}/cloudflared-darwin-arm64.pkg"
    info "Downloading cloudflared ${CF_LATEST}..."
    TMPDIR_CF="$(mktemp -d)"
    curl -sL "$CF_PKG_URL" -o "$TMPDIR_CF/cloudflared.pkg"
    sudo installer -pkg "$TMPDIR_CF/cloudflared.pkg" -target / >/dev/null 2>&1
    rm -rf "$TMPDIR_CF"
    if command_exists cloudflared; then
        success "cloudflared installed: $(cloudflared --version 2>&1 | head -1)"
    else
        warn "cloudflared pkg installed but binary not found on PATH — check /usr/local/bin"
    fi
else
    success "cloudflared already installed: $(cloudflared --version 2>&1 | head -1)"
fi

# =============================================================================
#  Step 6 — Install gh CLI
# =============================================================================

info "Step 6/${TOTAL_STEPS}: Installing gh CLI"
if ! command_exists gh; then
    GH_LATEST=$(curl -sL -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest | sed 's|.*/v||')
    GH_ARCHIVE="gh_${GH_LATEST}_macOS_arm64.zip"
    GH_URL="https://github.com/cli/cli/releases/download/v${GH_LATEST}/${GH_ARCHIVE}"
    info "Downloading gh ${GH_LATEST}..."
    TMPDIR_GH="$(mktemp -d)"
    curl -sL "$GH_URL" -o "$TMPDIR_GH/$GH_ARCHIVE"
    unzip -qo "$TMPDIR_GH/$GH_ARCHIVE" -d "$TMPDIR_GH"
    GH_EXTRACTED=""
    for _d in "$TMPDIR_GH"/gh_*/; do
        if [ -d "$_d" ]; then
            GH_EXTRACTED="$_d"
            break
        fi
    done
    if [ -n "$GH_EXTRACTED" ] && [ -f "$GH_EXTRACTED/bin/gh" ]; then
        sudo cp "$GH_EXTRACTED/bin/gh" /usr/local/bin/gh
        sudo chmod +x /usr/local/bin/gh
        if [ -d "$GH_EXTRACTED/share/man" ]; then
            sudo cp -R "$GH_EXTRACTED/share/man/"* /usr/local/share/man/ 2>/dev/null || true
        fi
    fi
    rm -rf "$TMPDIR_GH"
    if command_exists gh; then
        success "gh installed: $(gh --version 2>&1 | head -1)"
    else
        warn "gh extraction failed — install manually"
    fi
else
    success "gh already installed: $(gh --version 2>&1 | head -1)"
fi

if command_exists gh && ! gh auth status >/dev/null 2>&1; then
    warn "gh is not authenticated. Run 'gh auth login' after setup to enable GitHub operations."
fi

# =============================================================================
#  Step 7 — Initialize git submodules
# =============================================================================

info "Step 7/${TOTAL_STEPS}: Initializing git submodules"
mkdir -p "$SITES_DIR" "$TOOLING_DIR" "$WATCHER_DIR" "$LAUNCH_AGENTS_DIR"

cd "$DEV_DIR"

if [ -f "$DEV_DIR/.gitmodules" ]; then
    git submodule update --init --recursive 2>/dev/null
    success "All submodules initialized"

    # Report what was found
    git submodule foreach --quiet 'printf "  %s\n" "$sm_path"' | while read -r _path; do
        success "$_path"
    done
else
    warn "No .gitmodules found — add submodules with 'git submodule add'"
fi

# =============================================================================
#  Step 8 — Build Swift projects
# =============================================================================

info "Step 8/${TOTAL_STEPS}: Building Swift projects"

# Build any Swift package found under tooling/
for _dir in "$TOOLING_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    if [ -f "$_dir/Package.swift" ]; then
        info "  Building tooling: $_name..."
        (cd "$_dir" && swift build -c release 2>&1 | tail -1)
        success "  $_name built"
    fi
done

# Build any Swift package found under sites/
# After building, determine type by running the binary once — if it exits
# cleanly and produces .output, it's static. Otherwise it's a server that
# launchd will manage.
for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    if [ -f "$_dir/Package.swift" ]; then
        info "  Building site: $_name..."
        (cd "$_dir" && swift build -c release 2>&1 | tail -1)
        success "  $_name built"

        # If no .output exists yet but the binary is present, try running it
        # once to see if it generates static output (exits quickly).
        _binary="$_dir/.build/release/Application"
        if [ ! -d "$_dir/.output" ] && [ -f "$_binary" ]; then
            info "  Running $_name to check for static output..."
            (cd "$_dir" && .build/release/Application 2>/dev/null) || true
        fi

        if [ -d "$_dir/.output" ]; then
            success "  $_name → static site (.output generated)"
        elif [ -f "$_binary" ]; then
            success "  $_name → server binary (launchd will manage)"
        fi
    fi
done

# =============================================================================
#  Step 9 — Configure Apache
# =============================================================================

info "Step 9/${TOTAL_STEPS}: Configuring Apache"

enable_module() {
    _mod="$1"
    if grep -q "^#.*$_mod" "$HTTPD_CONF"; then
        sudo sed -i '' "s|^#\\(.*$_mod\\)|\\1|" "$HTTPD_CONF"
        success "  Enabled $_mod"
    else
        success "  $_mod already enabled"
    fi
}

sudo cp "$HTTPD_CONF" "${HTTPD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
enable_module "mod_proxy.so"
enable_module "mod_proxy_http.so"
enable_module "mod_rewrite.so"
enable_module "mod_proxy_wstunnel.so"

if ! grep -q "extra/custom.conf" "$HTTPD_CONF"; then
    printf "\n# Developer custom site configuration\nInclude /private/etc/apache2/extra/custom.conf\n" \
        | sudo tee -a "$HTTPD_CONF" >/dev/null
    success "  Added custom.conf Include to httpd.conf"
else
    success "  custom.conf Include already in httpd.conf"
fi

sudo mkdir -p "$LOG_DIR"
sudo chown root:wheel "$LOG_DIR"

# Build custom.conf by scanning sites/ for static (.output) and server
# (.build/release/Application) projects — no hardcoded arrays.
server_port=$SERVER_PORT_START

_conf_file="$(mktemp)"
printf 'ProxyPreserveHost On\nProxyRequests Off\n\n' > "$_conf_file"

for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"

    if [ -d "$_dir/.output" ]; then
        _output_dir="$_dir/.output"
        render_template "$APACHE_TMPL_DIR/static-site.conf.tmpl" \
            "SITE_NAME=$_name" \
            "OUTPUT_DIR=$_output_dir" \
            "LOG_DIR=$LOG_DIR" \
            >> "$_conf_file"
        printf '\n' >> "$_conf_file"
        chmod -R o+r "$_output_dir" 2>/dev/null || true
        success "  Configured static site: /$_name → $_output_dir"

    elif [ -f "$_dir/.build/release/Application" ]; then
        render_template "$APACHE_TMPL_DIR/server-site.conf.tmpl" \
            "SITE_NAME=$_name" \
            "PORT=$server_port" \
            "LOG_DIR=$LOG_DIR" \
            >> "$_conf_file"
        printf '\n' >> "$_conf_file"
        success "  Configured proxy site: /$_name → http://127.0.0.1:$server_port"
        server_port=$((server_port + 1))
    fi
done

sudo cp "$_conf_file" "$CUSTOM_CONF"
rm -f "$_conf_file"
success "  Wrote $CUSTOM_CONF"

# =============================================================================
#  Step 10 — launchd agents + file watchers for server binaries
# =============================================================================

info "Step 10/${TOTAL_STEPS}: Creating launchd agents and file watchers for server binaries"

# launchd handles crash restarts natively via KeepAlive + ThrottleInterval.
# The server-agent plist runs the binary directly (no wrapper script).
# A shared restart-server.sh handles all binary-rebuild restarts.

_restart_script="$SCRIPTS_TMPL_DIR/restart-server.sh"
chmod +x "$_restart_script" 2>/dev/null || true

server_port=$SERVER_PORT_START

for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    _binary="$_dir/.build/release/Application"

    # Only server sites (have binary but no .output)
    [ -d "$_dir/.output" ] && continue
    [ ! -f "$_binary" ] && continue

    _label="com.${GITHUB_USER}.${_name}"
    _watcher_label="${_label}.watcher"

    # Server agent — runs the binary directly, launchd manages restarts
    _plist="${LAUNCH_AGENTS_DIR}/${_label}.plist"
    render_template "$LAUNCHD_TMPL_DIR/server-agent.plist.tmpl" \
        "LABEL=$_label" \
        "BINARY_PATH=$_binary" \
        "WORKING_DIR=$_dir" \
        "PORT=$server_port" \
        "LOG_FILE=$WATCHER_DIR/${_name}.log" \
        "ERROR_LOG_FILE=$WATCHER_DIR/${_name}.error.log" \
        > "$_plist"

    launchctl bootout "gui/${UID_NUM}/${_label}" 2>/dev/null || true
    launchctl bootstrap "gui/${UID_NUM}" "$_plist" 2>/dev/null || launchctl load "$_plist" 2>/dev/null || true
    success "  Server agent: $_label (port $server_port)"

    # Watcher agent — calls shared restart-server.sh with label as $1
    _watcher_plist="${LAUNCH_AGENTS_DIR}/${_watcher_label}.plist"
    render_template "$LAUNCHD_TMPL_DIR/watcher-agent.plist.tmpl" \
        "LABEL=$_watcher_label" \
        "RESTART_SCRIPT=$_restart_script" \
        "SERVER_LABEL=$_label" \
        "BINARY_PATH=$_binary" \
        "LOG_FILE=$WATCHER_DIR/${_name}-watcher.log" \
        "ERROR_LOG_FILE=$WATCHER_DIR/${_name}-watcher.error.log" \
        > "$_watcher_plist"

    launchctl bootout "gui/${UID_NUM}/${_watcher_label}" 2>/dev/null || true
    launchctl bootstrap "gui/${UID_NUM}" "$_watcher_plist" 2>/dev/null || launchctl load "$_watcher_plist" 2>/dev/null || true
    success "  Watcher agent: $_watcher_label → watches $_binary"

    server_port=$((server_port + 1))
done

# =============================================================================
#  Step 11 — Sites watcher launchd agent
# =============================================================================

info "Step 11/${TOTAL_STEPS}: Installing sites-watcher launchd agent"

_sites_watcher_script="$SCRIPTS_TMPL_DIR/sites-watcher.sh"
_sites_watcher_label="com.${GITHUB_USER}.sites-watcher"
_sites_watcher_plist="${LAUNCH_AGENTS_DIR}/${_sites_watcher_label}.plist"

if [ -f "$_sites_watcher_script" ]; then
    chmod +x "$_sites_watcher_script"

    render_template "$LAUNCHD_TMPL_DIR/sites-watcher-agent.plist.tmpl" \
        "LABEL=$_sites_watcher_label" \
        "WATCHER_SCRIPT=$_sites_watcher_script" \
        "SITES_DIR=$SITES_DIR" \
        "LOG_FILE=$WATCHER_DIR/sites-watcher.stdout.log" \
        "ERROR_LOG_FILE=$WATCHER_DIR/sites-watcher.stderr.log" \
        > "$_sites_watcher_plist"

    launchctl bootout "gui/${UID_NUM}/${_sites_watcher_label}" 2>/dev/null || true
    launchctl bootstrap "gui/${UID_NUM}" "$_sites_watcher_plist" 2>/dev/null || launchctl load "$_sites_watcher_plist" 2>/dev/null || true
    success "Sites watcher agent installed: $_sites_watcher_label"
    success "  Watches: $SITES_DIR (+ polls every 30s)"
else
    warn "sites-watcher.sh not found at $_sites_watcher_script — skipping"
fi

# =============================================================================
#  Step 12 — Test & restart Apache
# =============================================================================

info "Step 12/${TOTAL_STEPS}: Testing and restarting Apache"

# Set permissions on all static site output directories
for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    if [ -d "$_dir/.output" ]; then
        chmod -R o+r "$_dir/.output" 2>/dev/null || true
        chmod o+x "$DEV_DIR" "$SITES_DIR" "$_dir" "$_dir/.output" 2>/dev/null || true
    fi
done

if sudo apachectl configtest 2>&1; then
    success "Apache configuration test passed"
    sudo apachectl restart
    success "Apache restarted"
else
    error "Apache configuration test failed — check $CUSTOM_CONF and $HTTPD_CONF"
fi

# =============================================================================
#  Summary
# =============================================================================

printf "\n"
printf "\033[1;32m=============================================================================\033[0m\n"
printf "\033[1;32m  Setup Complete!\033[0m\n"
printf "\033[1;32m=============================================================================\033[0m\n"
printf "\n"
printf "  \033[1mDotfiles:\033[0m        Symlinked from %s/\n" "$DOTFILES_DIR"
printf "    ~/.zshrc → utilities/dotfiles/zshrc\n"
printf "    ~/.vimrc → utilities/dotfiles/vimrc\n"
printf "    ~/.gitconfig → utilities/dotfiles/gitconfig\n"
printf "    ~/.gitignore → utilities/dotfiles/gitignore\n"
printf "    ~/.ssh/config → utilities/dotfiles/ssh_config\n"
printf "\n"
printf "  \033[1mSites detected:\033[0m\n"

_any_sites=false
for _dir in "$SITES_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    if [ -d "$_dir/.output" ]; then
        printf "    http://localhost/%s/  (static)\n" "$_name"
        _any_sites=true
    elif [ -f "$_dir/.build/release/Application" ]; then
        printf "    http://localhost/%s/  (server → proxy)\n" "$_name"
        _any_sites=true
    else
        printf "    %s  (not yet built)\n" "$_name"
        _any_sites=true
    fi
done
if [ "$_any_sites" = false ]; then
    printf "    (none — add submodules under sites/)\n"
fi

printf "\n"
printf "  \033[1mTooling detected:\033[0m\n"
_any_tooling=false
for _dir in "$TOOLING_DIR"/*/; do
    [ ! -d "$_dir" ] && continue
    _name="$(basename "$_dir")"
    printf "    %s\n" "$_name"
    _any_tooling=true
done
if [ "$_any_tooling" = false ]; then
    printf "    (none — add submodules under tooling/)\n"
fi

printf "\n"
printf "  \033[1mLogs:\033[0m            %s/<site>-{error,access}.log\n" "$LOG_DIR"
printf "  \033[1mlaunchd logs:\033[0m    %s/<site>.{log,error.log}\n" "$WATCHER_DIR"
printf "  \033[1mApache config:\033[0m   %s\n" "$CUSTOM_CONF"
printf "  \033[1mHTTPD config:\033[0m    %s\n" "$HTTPD_CONF"
printf "  \033[1mlaunchd agents:\033[0m  %s/\n" "$LAUNCH_AGENTS_DIR"
printf "  \033[1mTemplates:\033[0m       %s/\n" "$UTILITIES_DIR"
printf "\n"
printf "  \033[1mArchitecture:\033[0m\n"
printf "    Cloudflare Tunnel → Apache :80 → routes internally\n"
printf "    Static sites served directly from .output directories\n"
printf "    Server binaries reverse-proxied via mod_proxy\n"
printf "    Sites watcher auto-detects new projects every 30s\n"
printf "    For HTTPS, rely on Cloudflare or configure local SSL\n"
printf "\n"
printf "  \033[1mSubmodules:\033[0m\n"
printf "    Repos are managed as git submodules — no config arrays needed.\n"
printf "    To add a new site:\n"
printf "      cd %s\n" "$DEV_DIR"
printf "      git submodule add https://github.com/%s/<repo>.git sites/<repo>\n" "$GITHUB_USER"
printf "    The sites-watcher will auto-detect and configure it.\n"
printf "\n"
printf "  \033[1mNext steps:\033[0m\n"
printf "    1. Run 'gh auth login' to authenticate with GitHub\n"
printf "\n"
printf "  \033[1mCloudflare Tunnel:\033[0m\n"
printf "    Tunnel routes are configured remotely via dash.cloudflare.com,\n"
printf "    not from locally stored config files.\n"
printf "\n"
printf "    New tunnel:\n"
printf "      cloudflared tunnel login\n"
printf "      cloudflared tunnel create dev\n"
printf "      cloudflared tunnel run dev\n"
printf "\n"
printf "    Existing tunnel:\n"
printf "      cloudflared tunnel login\n"
printf "      cloudflared tunnel run <TUNNEL_NAME_OR_UUID>\n"
printf "\n"
printf "    Then go to dash.cloudflare.com → Zero Trust → Networks → Tunnels\n"
printf "    to manage public hostnames, access policies, and route mappings.\n"
printf "\n"
printf "  \033[1mUseful commands:\033[0m\n"
printf "    sudo apachectl configtest && sudo apachectl restart\n"
printf "    launchctl list | grep %s\n" "$GITHUB_USER"
printf "    tail -f %s/<site>.log\n" "$WATCHER_DIR"
printf "    git submodule status\n"
printf "    git submodule update --remote --merge\n"
printf "\n"
