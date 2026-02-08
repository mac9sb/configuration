# Server

Personal macOS development environment — manages sites, tooling, and infrastructure as a single repository with git submodules.

## Structure

```
~/Developer/
├── setup.sh                 # Main setup script
├── uninstall.sh             # Teardown script
├── .env.example             # R2 credentials template (tracked)
├── .env.local               # R2 credentials (gitignored)
├── utilities/
│   ├── apache/              # Apache config templates
│   ├── cloudflared/         # Tunnel + primary domain config
│   ├── dotfiles/            # Symlinked to ~/.*
│   ├── githooks/            # Installed to .git/hooks/ during setup
│   ├── launchd/             # Launchd plists (symlinked into ~/Library/LaunchAgents)
│   ├── newsyslog/           # Log rotation config
│   └── scripts/             # Runtime scripts
├── sites/                   # Website submodules
└── tooling/                 # CLI tool submodules
```

## Quick Start

```sh
git clone --recursive https://github.com/mac9sb/server.git ~/Developer
cd ~/Developer
cp .env.example .env.local   # fill in R2 credentials
sudo ./setup.sh
```

## Architecture

```
Internet → Cloudflare Tunnel (maclong) → Apache :80 → VirtualHost routing
                                            │
              ┌─────────────────────────────┼──────────────────────────────┐
              │                             │                              │
        maclong.dev                  api.maclong.dev                cool-app.com
       (VirtualHost →              (VirtualHost →                (VirtualHost →
        static from                 proxy → :8001)                proxy → :8002)
        .output)
                         localhost/site-name/  ← path-based dev access for all
```

- **Primary domain**: set in `utilities/cloudflared/config.yml` via `# primary-domain: maclong.dev`
- **Domain sites**: directory name contains a dot → custom domain VirtualHost (e.g. `sites/cool-app.com/`)
- **Subdomain sites**: directory name has no dot → subdomain of primary domain (e.g. `sites/api/` → `api.maclong.dev`)
- **Local dev**: every site is also accessible at `http://localhost/site-name/` via path-based routing
- **Static sites**: `.output/` directory → Apache serves via `DocumentRoot` or `Alias`
- **Server apps**: `.build/release/Application` → reverse-proxied via `mod_proxy`
- **State**: single SQLite database (WAL mode) at `~/Library/Application Support/com.mac9sb/state.db`

## Submodules

Submodules are the source of truth for what repos exist, Apache/server-manager config, and cloudflared ingress entries. Adding or removing a submodule is all you need to do for routing — custom domains still require a DNS route to the tunnel (see below).

### Adding

```sh
cd ~/Developer

# Primary domain site (directory name = domain)
git submodule add https://github.com/mac9sb/portfolio.git sites/maclong.dev

# Subdomain site (no dot → becomes api.maclong.dev)
git submodule add https://github.com/mac9sb/api.git sites/api

# Custom domain site (dot in name → becomes cool-app.com)
git submodule add https://github.com/mac9sb/cool-app.git sites/cool-app.com

# Tooling
git submodule add https://github.com/mac9sb/<repo>.git tooling/<repo>

git commit -m "Add <repo> submodule"
```

The sites-watcher auto-detects new sites and configures Apache + server-manager.

### Updating

```sh
git submodule update --remote --merge
git add sites/<name>
git commit -m "Update <name> submodule"
```

> [!WARNING]
> **Do NOT use `git -C sites/<name> pull`** — this bypasses submodule tracking. The pre-push hook will block inconsistent pushes.

## Domain Routing

Apache routing is derived entirely from site directory names and the primary domain configured in `utilities/cloudflared/config.yml` (custom domain ingress entries are auto-managed by sites-watcher):

```
# primary-domain: maclong.dev
```

| Directory name | VirtualHost `ServerName` | How it works |
|---|---|---|
| `sites/maclong.dev/` | `maclong.dev` | Dot in name → custom domain (also the primary) |
| `sites/api/` | `api.maclong.dev` | No dot → subdomain of primary domain |
| `sites/cool-app.com/` | `cool-app.com` | Dot in name → custom domain |

Every site also gets a path-based entry in the default VirtualHost for local development at `http://localhost/site-name/`.

### Adding a Subdomain Site

Subdomain DNS is already covered by the `*.maclong.dev` wildcard — just add the submodule:

```sh
git submodule add https://github.com/mac9sb/api.git sites/api
git commit -m "Add api submodule"
# → automatically served at api.maclong.dev
```

### Adding a Custom Domain Site

Custom domains need a DNS route to the tunnel; the cloudflared ingress entry is auto-managed:

1. Add the submodule (directory name = the domain):

   ```sh
   git submodule add https://github.com/mac9sb/cool-app.git sites/cool-app.com
   ```

2. The sites-watcher updates `utilities/cloudflared/config.yml` automatically (no manual edits needed).

3. Route DNS to the tunnel:

   ```sh
   cloudflared tunnel route dns maclong cool-app.com
   ```

4. The sites-watcher picks up the change, regenerating Apache config and ingress entries automatically.

### Renaming / Changing Domains

```sh
git mv sites/old-name sites/new-name.com
git commit -m "Move to new-name.com"
```

## Cloudflare Tunnel

The tunnel config at `utilities/cloudflared/config.yml` is version-controlled (no credentials). It contains:

- The **primary domain** as a parseable comment (`# primary-domain: maclong.dev`)
- **Ingress rules** for the primary domain, wildcard subdomains, and any custom domains
- All ingress rules forward to Apache on `:80` — Apache handles per-site routing via VirtualHosts

See the comments in `utilities/cloudflared/config.yml` for full details.

### First-Time Setup

```sh
sudo ./setup.sh    # symlinks config, installs agents
cloudflared tunnel login
cloudflared tunnel create maclong --credentials-file ~/.cloudflared/maclong.json
cloudflared tunnel route dns maclong maclong.dev
cloudflared tunnel route dns maclong "*.maclong.dev"
```

### With Existing Tunnel

If the tunnel already exists (e.g., created on another machine or a previous install), fetch the credentials and add DNS routes:

```sh
# Authenticate with Cloudflare (creates ~/.cloudflared/cert.pem)
cloudflared tunnel login

# Fetch credentials for the existing tunnel
cloudflared tunnel token --cred-file ~/.cloudflared/maclong.json maclong

# Add DNS routes (creates CNAME records pointing to the tunnel)
cloudflared tunnel route dns maclong maclong.dev
cloudflared tunnel route dns maclong "*.maclong.dev"

# Use -f / --overwrite-dns to replace existing DNS records
cloudflared tunnel route dns -f maclong "*.maclong.dev"
```

## Daily Backups

A daily backup script runs at 03:00 via launchd, snapshots all SQLite databases, packages them into tarballs, and uploads to Cloudflare R2 using pure `curl` + S3v4 signing (no AWS CLI needed). Local backups are retained for 7 days.

See `utilities/scripts/backup.sh` for the full process. Copy `.env.example` to `.env.local` and fill in your R2 credentials:

```sh
cp .env.example .env.local
```

## Useful Commands

```sh
# Apache
sudo apachectl configtest && sudo apachectl restart

# Launchd agents
launchctl list | grep mac9sb

# Restart a specific server
~/Developer/utilities/scripts/restart-server.sh <server-name>

# Logs
tail -f ~/Library/Logs/com.mac9sb/<site>.log
tail -f ~/Library/Logs/com.mac9sb/server-manager.log
tail -f /var/log/apache2/sites/<site>-error.log

# Submodules
git submodule status
git submodule update --remote --merge

# Manual backup
~/Developer/utilities/scripts/backup.sh

# Rebuild a site
cd ~/Developer/sites/<name> && swift build -c release

# Tunnel
cloudflared tunnel info maclong
cloudflared tunnel list
```

## Teardown

```sh
sudo ./uninstall.sh          # standard (preserves CLI tools, SSH keys, credentials)
sudo ./uninstall.sh --all    # full (also removes cloudflared)
```

See `uninstall.sh` for exactly what gets removed and what's preserved.
