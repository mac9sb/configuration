---
description: Scaffold a new Deno app from the foundation template
argument-hint: [app-name] [--no-stripe] [--no-apple]
allowed-tools: Bash, Read, Write, Edit, Glob
---

Scaffold a new Deno app using the mac9sb stack. Arguments: `$ARGUMENTS`

## Stack

- **`@mac9sb/deno-foundation`** (JSR) — auth, KV, routing, logging, static files, Stripe, Sign in with Apple
- **`~/Developer/deno-template`** — canonical template to copy from
- **Key pattern**: `mountAuthRoutes(router, kv, opts)` handles all `/auth/*` and `/api/session`
  routes; `createStaticHandler` handles MIME serving and locale cookies; `mountStripeRoutes` adds
  billing routes — the app only adds domain-specific routes

## Steps

### 1. Parse arguments

From `$ARGUMENTS`:
- First non-flag token = slug name (e.g. `my-saas`)
- `--no-stripe` flag = leave Stripe as commented-out instructions, omit Stripe env vars
- `--no-apple` flag = omit Sign in with Apple (included by default)
- Derive display name: capitalise each word, replace hyphens/underscores with spaces
  (e.g. `my-saas` → `My Saas`, `notetaker` → `Notetaker`)

If no name is provided, stop and ask for one.

### 2. Verify the template exists

Check that `~/Developer/deno-template/` exists and has `index.ts`. If not, stop and tell the user
to clone it from `mac9sb/deno-template`.

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
- `public/locales/en.json`
- `public/locales/fr.json`

Use `sed -i ''` or Edit tool — whichever is cleaner for each file.

### 6. Update deno.json

The copied `deno.json` already has the right foundation import. No changes needed.

### 7. Handle Stripe

The copied `index.ts` contains a commented-out Stripe block:

```typescript
// Stripe: import { mountStripeRoutes } from "@mac9sb/deno-foundation"
// and call mountStripeRoutes(router, kv, { baseUrl: BASE_URL }) to add billing routes.
```

**If `--no-stripe` was NOT passed** (Stripe is included):

1. Add `mountStripeRoutes` to the existing import destructure at the top of `index.ts`.
2. Replace the comment block with the actual call:
   ```typescript
   mountStripeRoutes(router, kv, { baseUrl: BASE_URL });
   ```

**If `--no-stripe` was passed**: leave the comment as-is.

### 8. Handle Sign in with Apple

**If `--no-apple` was NOT passed** (Apple is included — the default):

1. In `index.ts`, the `APPLE_CLIENT_ID` line is already present. No change needed — it reads from
   env and passes `undefined` when unset (which disables the route safely).

2. In `public/get-started.html`, set the `apple-client-id` meta tag content to a placeholder:
   ```html
   <meta name="apple-client-id" content="com.example.<slug>">
   ```
   Replace `com.example.<slug>` literally — the user will update this to their real Services ID.

**If `--no-apple` was passed**:

1. Remove the `APPLE_CLIENT_ID` line from `index.ts`.
2. Remove the `appleClientId` option from the `mountAuthRoutes` call.
3. Remove the Sign in with Apple button and its surrounding divider from `public/get-started.html`.
4. Remove the `get_started.apple_btn` and `get_started.apple_error` keys from both locale files.

### 9. Create .env.example

Write a `.env.example` in the project root:

```
BASE_URL=https://<slug>.deno.dev
RP_NAME=<Display Name>
RESEND_API_KEY=re_...
```

If `--no-apple` was **not** passed, also add:

```
# Sign in with Apple — set to your Apple Services ID (web) or bundle ID (native)
APPLE_CLIENT_ID=com.example.<slug>
```

If `--no-stripe` was **not** passed, also add:

```
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

### 10. Update README

Replace the README content with:

```markdown
# <Display Name>

Built with [`@mac9sb/deno-foundation`](https://jsr.io/@mac9sb/deno-foundation).

## Development setup

```bash
cp .env.example .env
# fill in your values — see Environment variables below
deno task dev
```

Open [http://localhost:8000](http://localhost:8000).

**Magic links in development**: set `BASE_URL=http://localhost:8000` and provide a real
`RESEND_API_KEY`. Alternatively, temporarily log the magic link token in `magic_link.ts` to
skip email delivery during local testing.

**Passkeys in development**: passkeys require HTTPS or `localhost`. Running on `localhost:8000`
works without any extra configuration.

[IF APPLE INCLUDED]
**Sign in with Apple in development**: the Apple JS SDK only works on domains registered in your
Apple Developer account. For local testing, either use an ngrok tunnel pointed at `localhost:8000`
and register that domain, or test on a registered staging domain.
[END IF APPLE]

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `BASE_URL` | Yes | Full origin URL (e.g. `https://<slug>.deno.dev`) |
| `RP_NAME` | No | Passkey relying-party display name (default: `<Display Name>`) |
| `RESEND_API_KEY` | Yes | [Resend](https://resend.com) API key for magic links |
[IF APPLE]
| `APPLE_CLIENT_ID` | Yes* | Apple Services ID (web) or bundle ID (native). Required to enable Sign in with Apple. |
[END IF APPLE]
[IF STRIPE]
| `STRIPE_SECRET_KEY` | Yes | Stripe secret key |
| `STRIPE_WEBHOOK_SECRET` | Yes | Stripe webhook signing secret |
[END IF STRIPE]

## Production checklist

- [ ] Set all env vars in the [Deno Deploy dashboard](https://dash.deno.com)
- [ ] Point your custom domain and set `BASE_URL` to match
- [ ] Configure your Resend sending domain and verify DNS records
- [ ] Register your domain's `/.well-known/apple-app-site-association` if using passkeys with a
      native Swift client (add an associated domains entitlement in Xcode)
[IF APPLE]
- [ ] Create an Apple Services ID in the [Apple Developer portal](https://developer.apple.com),
      register your domain, and set `APPLE_CLIENT_ID` to the Services ID
- [ ] For native app Sign in with Apple: add the Sign in with Apple capability in Xcode and set
      `APPLE_CLIENT_ID` to your bundle ID in the native app's `Config.swift`
[END IF APPLE]
[IF STRIPE]
- [ ] Register your Stripe webhook endpoint (`<BASE_URL>/billing/webhook`) in the Stripe dashboard
      and copy the signing secret to `STRIPE_WEBHOOK_SECRET`
[END IF STRIPE]

## Deploy

```bash
deployctl deploy --project=<slug> index.ts
```
```

Fill in `[IF ... / END IF ...]` blocks based on which flags were passed.

### 11. Initialise git

```bash
cd ~/Developer/<slug>
git init && git add -A && git commit -m "Initial commit"
```

### 12. Offer GitHub repo creation

Ask: **"Create a private GitHub repo `mac9sb/<slug>`? [y/N]"**

If yes:
```bash
gh repo create mac9sb/<slug> --private --source=. --remote=origin --push
```

### 13. Print summary

```
✓ Created ~/Developer/<slug>
  Display name : <Display Name>
  Foundation   : @mac9sb/deno-foundation@^0.1.9
  Stripe       : included / not included
  Apple signin : included / not included
  GitHub repo  : mac9sb/<slug> / not created

Next steps:
  1. cp .env.example .env  →  fill in RESEND_API_KEY, BASE_URL[, APPLE_CLIENT_ID][, STRIPE keys]
  2. deno task dev          →  http://localhost:8000
  3. Set env vars in Deno Deploy dashboard before deploying
```
