#!/bin/sh
# ─────────────────────────────────────────────
# Weekly Claude Creative Build
# Runs every Monday at 09:00 via cron
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/utils.sh"

WORK_DIR="$HOME/Work/claude"
BUILD_DIR="$WORK_DIR/$(date +%Y-w%U)"
LOG_DIR="$HOME/.claude-weekly/logs"
PROMPT_FILE="$HOME/.claude-weekly/prompt.md"

total_start

# ——— Step: Setup directories ———
setup_dirs() {
  step "Setting up directories"
  mkdir -p "$BUILD_DIR"
  mkdir -p "$LOG_DIR"
  step_done
}

# ——— Step: Write prompt ———
write_prompt() {
  step "Writing prompt file"
  cat > "$PROMPT_FILE" <<'PROMPT'
You are an expert full-stack engineer with creative vision and strong product instincts.

## Your Mandate

1. **Research** — Search for genuine gaps in developer tools, productivity, infrastructure, or indie software markets. Look for underserved niches. Don't build something that already exists well. Check Product Hunt, Hacker News, GitHub issues, Reddit threads.

2. **Decide** — Pick the minimal viable form for the product. Could be a CLI tool, an API, a desktop app, a web app, an editor plugin, a daemon, or a combination. Justify your choices. Omit stack layers that add no value.

3. **Build** — Implement it completely. No stubs, no TODO comments, no placeholder logic. It must compile and run.

4. **Document** — Write a README.md with setup instructions that actually work, and a DECISIONS.md explaining your research and architecture choices.

5. **Pitch** — Generate a PITCH.pdf that sells the product and outlines future progression paths.

---

## Stack (use what fits — never force a layer)

**Languages**
- Rust
- TypeScript
- SQL
- CSS

**CLI Tools (Rust)**
- Clap — argument parsing
- Indicatif — progress bars and spinners
- Crossterm — terminal manipulation and colour
- Anyhow — ergonomic error handling
- Thiserror — typed error enums for library code
- Tracing + tracing-subscriber — structured logging
- Serde + serde_json — serialisation
- Tokio — async runtime (also applies to backend)
- Reqwest — HTTP client
- Dialoguer — interactive prompts
- Console — terminal styling utilities

**Application (Desktop / Web)**
- Tauri + Solid.js — cross-platform desktop with web frontend
- Vite — bundler and dev server
- TailwindCSS — utility-first CSS framework

**Backend / Daemon**
- Axum — HTTP framework
- Tower + tower-http — middleware (CORS, compression, tracing)
- Tokio — async runtime
- SQLx — async SQL with compile-time query checking
- PostgreSQL — primary database
- pgvector — vector similarity search
- SQLite / libsql — lightweight local-first database
- Redis / Valkey — caching, queues, pub/sub
- tokio-tungstenite — WebSocket support
- notify — filesystem watching
- Tree-sitter — code parsing and analysis
- jsonwebtoken — JWT signing and verification
- OAuth2 / OIDC — third-party auth flows

**AI / LLM**
- Anthropic SDK — Claude API integration
- OpenAI SDK — GPT API fallback

**Testing**
- cargo test + proptest — unit and property testing (Rust)
- Criterion — benchmarks (Rust)
- Vitest — unit and integration testing (TypeScript)
- Playwright — end-to-end browser testing

**Observability**
- OpenTelemetry — distributed tracing for production

**Editor Integrations**
- Zed extension
- VS Code extension
- Neovim plugin
- JetBrains plugin

**Infrastructure**
- Cloudflare Developer Platform (Workers, R2, D1, Pages)
- Stripe — payments
- Docker + Helm — containerisation and orchestration
- Nix — reproducible dev environments and builds

---

## Output

All files go to: ~/Developer/Work/claude/<YYYY-wWW>/

Required files:
- `README.md` — setup and usage instructions that work
- `DECISIONS.md` — research log and architecture rationale
- `PITCH.pdf` — sales pitch and roadmap (generate via pandoc from PITCH.md)

Generate PITCH.pdf using pandoc from a PITCH.md source. PITCH.md should cover:
- What the product is and who it's for
- Why it's different from existing solutions
- 2–3 realistic progression paths and monetisation angles

Production quality only. Linted, formatted, with proper error handling and test suites throughout.
PROMPT
  step_done
}

# ——— Step: Run Claude Code ———
run_claude() {
  step "Running Claude Code session"
  cd "$BUILD_DIR"
  claude \
    --model claude-opus-4-6 \
    --max-turns 500 \
    --allowedTools "Bash,Read,Write,Edit,Search,WebFetch,WebSearch" \
    --print \
    < "$PROMPT_FILE"
  step_done
}

# ——— Step: Maintenance ———
maintenance() {
  step "Running weekly maintenance"

  # macOS caches and logs
  rm -rf "$HOME/Library/Caches/"* 2>/dev/null || true
  rm -rf "$HOME/Library/Logs/"* 2>/dev/null || true
  rm -rf "$HOME/Library/Developer/Xcode/DerivedData/"* 2>/dev/null || true
  rm -rf "$HOME/Library/Developer/Xcode/Archives/"* 2>/dev/null || true
  rm -rf "$HOME/Library/Developer/CoreSimulator/Caches/"* 2>/dev/null || true

  # Homebrew cleanup
  if command -v brew >/dev/null 2>&1; then
    brew cleanup --prune=7 -s 2>/dev/null || true
    brew autoremove 2>/dev/null || true
  fi

  # Rust build artefacts
  if command -v cargo >/dev/null 2>&1; then
    cargo cache -a 2>/dev/null || true
  fi
  find "$HOME/Developer" -maxdepth 4 -name "target" -type d -path "*/target" -exec rm -rf {} + 2>/dev/null || true

  # Node artefacts
  find "$HOME/Developer" -maxdepth 4 -name "node_modules" -type d -exec rm -rf {} + 2>/dev/null || true
  find "$HOME/Developer" -maxdepth 4 -name ".next" -type d -exec rm -rf {} + 2>/dev/null || true
  find "$HOME/Developer" -maxdepth 4 -name "dist" -type d -exec rm -rf {} + 2>/dev/null || true
  npm cache clean --force 2>/dev/null || true
  bun pm cache rm 2>/dev/null || true

  # Docker cleanup
  if command -v docker >/dev/null 2>&1; then
    docker system prune -af --volumes 2>/dev/null || true
  fi

  # Nix garbage collection
  if command -v nix-collect-garbage >/dev/null 2>&1; then
    nix-collect-garbage -d 2>/dev/null || true
  fi

  # Trash and temp files
  rm -rf "$HOME/.Trash/"* 2>/dev/null || true
  rm -rf /tmp/com.apple.* 2>/dev/null || true

  step_done
}

# ——— Step: Generate PDF ———
generate_pdf() {
  step "Generating PITCH.pdf"
  if [ ! -f "$BUILD_DIR/PITCH.md" ]; then
    warn "PITCH.md not found; skipping PDF"
    step_done
    return 0
  fi
  if ! command -v pandoc >/dev/null 2>&1; then
    warn "pandoc not found; skipping PDF"
    step_done
    return 0
  fi
  pandoc "$BUILD_DIR/PITCH.md" \
    -o "$BUILD_DIR/PITCH.pdf" \
    --pdf-engine=xelatex \
    -V geometry:margin=1in \
    -V fontsize=12pt
  step_done
}

# ——— Step: Notify ———
notify() {
  step "Sending notification"
  osascript <<APPLESCRIPT
display notification "Your new project is ready" with title "Claude Weekly Build"
delay 1
tell application "Zed"
  activate
  open POSIX file "$WORK_DIR"
end tell
APPLESCRIPT
  step_done
}

# ——— Main sequence ———
log "Starting weekly Claude build"

setup_dirs
write_prompt

parallel_step "Maintenance" maintenance
parallel_step "Claude Code" run_claude

wait_parallel_steps

generate_pdf
notify

total_done
log "Done"
