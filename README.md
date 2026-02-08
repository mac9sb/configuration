# Server

Personal macOS development environment — manages sites, tooling, and infrastructure as a single repository with git submodules.

## Structure

```
~/Developer/
├── setup.sh                 # Main setup script
├── uninstall.sh             # Teardown script
├── utilities/
│   ├── dotfiles/            # Symlinked to ~/.*
│   │   ├── zshrc
│   │   ├── vimrc
│   │   ├── gitconfig
│   │   ├── gitignore
│   │   └── ssh_config
│   ├── apache/              # Apache config templates
│   │   ├── custom.conf.header
│   │   ├── static-site.conf.tmpl
│   │   └── server-site.conf.tmpl
│   ├── launchd/             # launchd plist templates
│   │   ├── server-agent.plist.tmpl
│   │   ├── watcher-agent.plist.tmpl
│   │   └── sites-watcher-agent.plist.tmpl
│   └── scripts/             # Runtime scripts & templates
│       ├── sites-watcher.sh
│       ├── crash-wrapper.sh.tmpl
│       └── restart-server.sh.tmpl
├── sites/                   # Website submodules
│   ├── portfolio/           # Static site (Swift → .output)
│   └── todos-auth-fluent/   # Server app (Swift → .build/release/Application)
├── tooling/                 # CLI tool submodules
│   ├── list/                # sls — directory listing
│   └── web-ui/              # Web UI library
└── tsx/                     # Next.js app (pulseboard)
```

## Quick Start

```sh
# Clone with submodules
git clone --recursive https://github.com/mac9sb/server.git ~/Developer

# Run setup
cd ~/Developer
sudo ./setup.sh
```

## What Setup Does

There are no hardcoded repo arrays — everything is derived from `.gitmodules` and filesystem state (`.output/` = static, `.build/release/Application` = server).

| Step | Action |
|------|--------|
| 1 | Enable Touch ID for sudo |
| 2 | Symlink dotfiles from `utilities/dotfiles/` to `~/.*` |
| 3 | Generate SSH key (`~/.ssh/id_ed25519`) |
| 4 | Install Xcode CLI tools & verify Swift |
| 5 | Install `cloudflared` (arm64 `.pkg`) |
| 6 | Install `gh` CLI (arm64 `.zip`) |
| 7 | Initialize git submodules (`git submodule update --init --recursive`) |
| 8 | Build all Swift packages found under `sites/` and `tooling/` |
| 9 | Configure Apache by scanning `sites/` for `.output` and `.build/release/Application` |
| 10 | Create launchd agents for detected server binaries |
| 11 | Create file watchers for binary hot-reload |
| 12 | Install sites-watcher launchd agent |
| 13 | Test & restart Apache |

## Submodules

Nested repositories are managed as git submodules — they are the **only** source of truth for what repos exist. There are no arrays to maintain in `setup.sh`. Adding or removing a submodule is all you need to do; the setup script and sites-watcher discover everything dynamically.

### Adding a new submodule

```sh
cd ~/Developer

# Site
git submodule add https://github.com/mac9sb/<repo>.git sites/<repo>

# Tooling
git submodule add https://github.com/mac9sb/<repo>.git tooling/<repo>

git commit -m "Add <repo> submodule"
```

The **sites-watcher** will automatically detect new sites and configure Apache + launchd agents when `.output/` or `.build/release/Application` appears. No further configuration needed.

### Updating submodules

```sh
# Pull latest for all submodules
git submodule update --remote --merge

# Pull latest for a specific submodule
git -C sites/portfolio pull origin main
```

## Architecture

```
Internet → Cloudflare Tunnel → Apache :80 → routes internally
                                  │
                   ┌──────────────┼──────────────┐
                   │              │              │
              /portfolio    /app-name       /other
             (static files)  (proxy →     (proxy →
              from .output   :8000)        :8001)
```

- **Static sites**: Detected by `.output/` directory; Apache serves files directly via `Alias`
- **Server apps**: Detected by `.build/release/Application` binary; Apache reverse-proxies to `localhost:8000+` via `mod_proxy`
- **Classification**: Automatic — if a built binary produces `.output` when run, it's static; otherwise it's a server
- **HTTPS**: Handled by Cloudflare; local traffic is HTTP on `:80`

## Templates

All generated configuration uses `{{PLACEHOLDER}}` templates from `utilities/`. The `render_template` function in `setup.sh` and `sites-watcher.sh` performs `sed`-based substitution at runtime.

| Directory | Templates | Purpose |
|-----------|-----------|---------|
| `apache/` | `static-site.conf.tmpl`, `server-site.conf.tmpl` | Per-site Apache config blocks |
| `launchd/` | `server-agent.plist.tmpl`, `watcher-agent.plist.tmpl` | launchd plists for servers & watchers |
| `scripts/` | `crash-wrapper.sh.tmpl`, `restart-server.sh.tmpl` | Crash-guarded launcher & hot-reload restart |

## Dotfiles

Dotfiles are **symlinked** (not copied) from `utilities/dotfiles/` so edits are tracked in git:

| Source | Target |
|--------|--------|
| `utilities/dotfiles/zshrc` | `~/.zshrc` |
| `utilities/dotfiles/vimrc` | `~/.vimrc` |
| `utilities/dotfiles/gitconfig` | `~/.gitconfig` |
| `utilities/dotfiles/gitignore` | `~/.gitignore` |
| `utilities/dotfiles/ssh_config` | `~/.ssh/config` |

## Sites Watcher

A launchd agent (`com.mac9sb.sites-watcher`) monitors `~/Developer/sites/` and auto-configures new projects:

- Watches the directory for new/removed project folders
- Polls every 30 seconds for `.output/` or `.build/release/Application` appearing
- Regenerates Apache config and launchd agents when state changes
- Logs to `~/.watchers/sites-watcher.log`

## Server Binaries

Each server site gets:

1. **Crash-guarded wrapper** — tracks consecutive crashes, sends macOS notification after 5 failures
2. **launchd agent** — starts at login, keeps alive, throttles restarts
3. **Binary watcher** — restarts the server when `.build/release/Application` changes (after `swift build -c release`)

Ports are assigned deterministically starting at `8000` and persisted in `.watchers/port-assignments`.

k# Cloudflare Tunnel

Tunnel routes are managed remotely via the Cloudflare dashboard, not local config files.

```sh
# First time
cloudflared tunnel login
cloudflared tunnel create dev
cloudflared tunnel run dev

# Existing tunnel
cloudflared tunnel login
cloudflared tunnel run <TUNNEL_NAME_OR_UUID>
```

Manage hostnames and access policies at: **dash.cloudflare.com → Zero Trust → Networks → Tunnels**

## Useful Commands

```sh
# Apache
sudo apachectl configtest && sudo apachectl restart

# launchd agents
launchctl list | grep mac9sb

# Logs
tail -f ~/Developer/.watchers/<site>.log
tail -f /var/log/apache2/sites/<site>-error.log

# Submodules
git submodule status
git submodule update --remote --merge

# Rebuild a site
cd ~/Developer/sites/<name>
swift build -c release
```
