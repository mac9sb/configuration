---
description: Scaffold a new SwiftUI iOS app from the swift-template
argument-hint: [app-name] [--bundle-id com.example.myapp] [--no-apple] [--platforms tvos,macos,watchos,visionos]
allowed-tools: Bash, Read, Write, Edit, Glob
---

Scaffold a new SwiftUI iOS app using the mac9sb Swift stack. Arguments: `$ARGUMENTS`

## Stack

- **`swift-foundation`** (SPM) — `APIClient`, `SessionStore`, `AuthService`, passkey transport types
- **`~/Developer/swift-template`** — canonical template to copy from
- **`xcodegen`** — generates `MyApp.xcodeproj` from `project.yml`
- **Pairs with**: a Deno backend scaffolded by `/create-app`

## Steps

### 1. Parse arguments

From `$ARGUMENTS`:
- First non-flag token = app slug (e.g. `my-saas` or `NoteTaker`)
- `--bundle-id <id>` = explicit bundle ID (default: `com.mac9sb.<slug>`)
- `--no-apple` = omit Sign in with Apple
- `--platforms <list>` = comma-separated extra platforms to enable in `project.yml`
  (valid values: `tvos`, `macos`, `watchos`, `visionos`)
- Derive display name: capitalise each word, replace hyphens/underscores with spaces
  (e.g. `my-saas` → `My Saas`, `notetaker` → `Notetaker`)
- Derive Xcode target name: PascalCase, no spaces (e.g. `My Saas` → `MySaas`)

If no name is provided, stop and ask for one.

### 2. Verify prerequisites

```bash
which xcodegen
```

If not found, install it:

```bash
brew install xcodegen
```

Check that `~/Developer/swift-template/` exists and contains `project.yml`. If not, stop and
tell the user to clone `mac9sb/swift-template`.

### 3. Create project directory

Target: `~/Developer/<slug>/`

If it already exists, stop and tell the user rather than overwriting.

### 4. Copy template files

```bash
rsync -a --exclude='.git' ~/Developer/swift-template/ ~/Developer/<slug>/
```

### 5. Rename the app target

In `project.yml`, replace:
- `name: MyApp` → `name: <TargetName>`
- `targets:\n  MyApp:` → `targets:\n  <TargetName>:`
- `PRODUCT_BUNDLE_IDENTIFIER: com.example.myapp` → `PRODUCT_BUNDLE_IDENTIFIER: <bundle-id>`
- `bundleIdPrefix: com.example` → `bundleIdPrefix: <bundle-id-prefix>` (everything before the last
  `.`-separated segment of the bundle ID)

### 6. Update Config.swift

Replace:
- `"https://myapp.deno.dev"` → `"https://<slug>.deno.dev"`
- `"com.example.myapp"` → `"<bundle-id>"`

### 7. Rename Swift files and types

In `Sources/App/MyApp.swift`:
- Replace `struct MyApp: App` → `struct <TargetName>: App`

In `Sources/App/HomeView.swift`:
- Replace `.navigationTitle("My App")` → `.navigationTitle("<Display Name>")`

In `Sources/App/Sources/App/Assets.xcassets` — nothing to rename, the asset catalog is generic.

### 8. Handle Sign in with Apple

**If `--no-apple` was NOT passed** (included by default): no changes needed.

**If `--no-apple` was passed**:

1. In `Sources/App/Auth/AuthView.swift`:
   - Remove the `import AuthenticationServices` line
   - Remove the `SignInWithAppleButton` block and its surrounding `divider`
   - Remove the `handleAppleResult(_:)` method

2. In `Sources/App/Info.plist`:
   - Remove the `NSFaceIDUsageDescription` key (only needed if you also want Face ID for passkeys;
     keep it if passkeys remain)

3. In `project.yml`, if there is an `entitlements` section referencing Sign in with Apple, remove it.

### 9. Handle extra platforms

**If `--platforms` was passed**, add the requested platforms to `project.yml` under `options.deploymentTarget`:

```yaml
options:
  deploymentTarget:
    iOS: "17.0"
    tvOS: "17.0"       # if tvos requested
    macOS: "14.0"      # if macos requested
    watchOS: "10.0"    # if watchos requested
    visionOS: "1.0"    # if visionos requested
```

Also add a new target entry in `project.yml` for each platform, using the same sources and dependencies as the iOS target but with `platform: tvOS` / `macOS` / `watchOS` / `visionOS`.

### 10. Generate Xcode project

```bash
cd ~/Developer/<slug>
xcodegen generate
```

If `xcodegen` fails, show the error and stop.

### 11. Create .env.example

Write a `.env.example` with the expected backend env vars, so the developer knows what to configure
on the Deno side:

```
# Backend (deno-foundation) — set these in your Deno Deploy dashboard
BASE_URL=https://<slug>.deno.dev
RESEND_API_KEY=re_...
APPLE_CLIENT_ID=<bundle-id>
```

### 12. Initialise git

```bash
cd ~/Developer/<slug>
git init && git add -A && git commit -m "Initial commit"
```

### 13. Offer GitHub repo creation

Ask: **"Create a private GitHub repo `mac9sb/<slug>`? [y/N]"**

If yes:
```bash
gh repo create mac9sb/<slug> --private --source=. --remote=origin --push
```

### 14. Print summary

```
✓ Created ~/Developer/<slug>
  Display name  : <Display Name>
  Target name   : <TargetName>
  Bundle ID     : <bundle-id>
  Swift package : swift-foundation (via SPM)
  Apple signin  : included / not included
  Platforms     : iOS[, tvOS, macOS, watchOS, visionOS]
  Xcode project : <slug>.xcodeproj  ✓ generated
  GitHub repo   : mac9sb/<slug> / not created

Next steps:
  1. open ~/Developer/<slug>/<TargetName>.xcodeproj
  2. Select your team in Signing & Capabilities
  3. Set Config.baseURL to your backend URL
  4. On the backend: set APPLE_CLIENT_ID=<bundle-id> so native Sign in with Apple works
  5. Run on device or simulator
```
