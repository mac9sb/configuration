---
description: Scaffold a new Deno app from the foundation template
argument-hint: [app-name] [--no-stripe]
allowed-tools: Bash, Read, Write, Edit, Glob
---

Scaffold a new Deno app using the mac9sb stack. Arguments: `$ARGUMENTS`

## Stack

- **`@mac9sb/deno-foundation`** (JSR) — auth, KV, routing, logging, Stripe
- **`~/Developer/deno-template`** — canonical template to copy from
- **Key pattern**: `mountAuthRoutes(router, kv, opts)` handles all `/auth/*` and `/api/session` routes; the app only adds domain routes

## Steps

### 1. Parse arguments

From `$ARGUMENTS`:
- First non-flag token = slug name (e.g. `my-saas`)
- `--no-stripe` flag = omit Stripe env vars and note in README
- Derive display name: capitalise each word, replace hyphens/underscores with spaces
  (e.g. `my-saas` → `My Saas`, `notetaker` → `Notetaker`)

If no name is provided, stop and ask for one.

### 2. Verify the template exists

Check that `~/Developer/deno-template/` exists and has `index.ts`. If not, stop and tell the user to clone it from `mac9sb/deno-template`.

### 3. Create project directory

Target: `~/Developer/<slug>/`

If it already exists, stop and tell the user rather than overwriting.

### 4. Copy template files

Copy everything from `~/Developer/deno-template/` into the new directory **excluding**:
- `.git/`
- `deno.lock`
- `.env`

```bash
rsync -a --exclude='.git' --exclude='deno.lock' --exclude='.env' \
  ~/Developer/deno-template/ ~/Developer/<slug>/
```

### 5. Substitute the app name

Replace every occurrence of `My App` with the display name in:
- `public/**/*.html`
- `public/locales/en.js`
- `public/locales/fr.js`
- `README.md`

Use `sed -i ''` or Edit tool — whichever is cleaner for each file.

### 6. Update deno.json

The copied `deno.json` already has the right foundation import. No changes needed unless `--no-stripe` was passed (see step 7).

### 7. Create .env.example

Write a `.env.example` in the project root:

```
BASE_URL=https://<slug>.deno.dev
RP_NAME=<Display Name>
RESEND_API_KEY=re_...
```

If `--no-stripe` was **not** passed, also add:

```
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

### 8. Handle --no-stripe

If `--no-stripe`:
- Do not add Stripe keys to `.env.example` (done above)
- Add a comment to `index.ts` after `mountAuthRoutes`:
  ```typescript
  // Stripe: import { mountStripeRoutes } from "@mac9sb/deno-foundation"
  // and call mountStripeRoutes(router, kv, { baseUrl: BASE_URL }) to add billing routes.
  ```

### 9. Update README

Replace the generic README content with:

```markdown
# <Display Name>

Built with [`@mac9sb/deno-foundation`](https://jsr.io/@mac9sb/deno-foundation).

## Setup

```bash
cp .env.example .env
# fill in your values
deno task dev
```

Open [http://localhost:8000](http://localhost:8000).

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `BASE_URL` | Yes | Full origin URL (e.g. `https://<slug>.deno.dev`) |
| `RP_NAME` | No | Passkey relying-party name (default: `<Display Name>`) |
| `RESEND_API_KEY` | Yes | [Resend](https://resend.com) API key for magic links |
[stripe rows if applicable]

## Deploy

```bash
deployctl deploy --project=<slug> index.ts
```

Set env vars in the Deno Deploy dashboard.
```

### 10. Initialise git

```bash
cd ~/Developer/<slug>
git init && git add -A && git commit -m "Initial commit"
```

### 11. Offer GitHub repo creation

Ask: **"Create a private GitHub repo `mac9sb/<slug>`? [y/N]"**

If yes:
```bash
gh repo create mac9sb/<slug> --private --source=. --remote=origin --push
```

Then tell the user to:
1. Go to jsr.io → `@mac9sb/<slug>` settings → link the GitHub repo for OIDC publishing (only needed if this will be a JSR package)

### 12. Print summary

```
✓ Created ~/Developer/<slug>
  Display name : <Display Name>
  Foundation   : @mac9sb/deno-foundation@^0.1.4
  Stripe       : included / not included
  GitHub repo  : mac9sb/<slug> / not created

Next steps:
  1. cp .env.example .env  →  fill in RESEND_API_KEY and BASE_URL
  2. deno task dev          →  http://localhost:8000
  3. Set env vars in Deno Deploy dashboard before deploying
```
