Below is the updated PLAN.md reflecting everything we’ve decided — including:
	•	✅ Static/Runtime automatic by default
	•	✅ Stage owns dev/serve lifecycle
	•	✅ Score remains generic Swift framework (not tied to Stage)
	•	✅ Stage hosts generic Swift workloads
	•	✅ Hybrid hosting philosophy clarified
	•	✅ Swift-first → Proto benefits
	•	✅ Serverless playground
	•	✅ Enterprise directory rules
	•	✅ Noora CLI
	•	✅ Score targets consolidated
	•	✅ Automatic asset + image optimization
	•	✅ GitHub integration
	•	✅ Explicit Application builder
	•	✅ PRD-first development rule with blank syntax sections

This is written as a single ecosystem source-of-truth artifact.

You can drop this directly as:

PLAN.md

at repo root.

⸻

Allegro Ecosystem — PLAN.md

(Ecosystem Product & Architecture Plan)

⸻

1. Mission

Allegro enables developers to:

Write everything in Swift and deploy anywhere — static hosts, custom servers, or Stage hosting — while gaining modern platform capabilities normally tied to other ecosystems.

The system consists of:

Component	Role
Score	Static-first Swift web framework
Stage	Hosting + deployment platform
Libretto	First-party dogfood application


⸻

2. Core Principles

⸻

2.1 Static + Runtime Are Automatic

Developers do not choose static vs runtime.

Score determines automatically:

Feature Used	Result
Static pages only	Static export
Auth/API/SSR used	Runtime enabled automatically
Mixed usage	Hybrid output

The framework decides the minimal runtime required.

This prevents configuration complexity and preserves simplicity.

⸻

2.2 Hybrid Hosting Model

Stage is hybrid hosting.
	•	Static delivery is default.
	•	Runtime activates only when required.
	•	One artifact deploys everywhere.

Static remains the performance baseline.

⸻

2.3 Swift Is the Source of Truth

Developers write Swift.

Score generates:
	•	HTML/CSS
	•	Protobuf schemas
	•	API contracts
	•	optimized assets
	•	runtime manifests

External ecosystem benefits without leaving Swift.

⸻

2.4 Stage Owns Hosting Lifecycle

Stage is responsible for:

dev
serve
build
deploy
logs
domains
previews

Score does not own serving.

This guarantees parity.

⸻

2.5 Score Remains Framework-Generic

Stage must be able to host:
	•	Score apps
	•	non-Score Swift apps
	•	generic Swift binaries

Score is not a requirement for Stage.

Stage hosts Swift workloads.

⸻

2.6 Enterprise Directory Discipline

Hard rule:
	•	No monolithic files.
	•	Feature-based directories.
	•	Small public APIs.

Example:

Posts/
  Pages/
  API/
  Components/
  Models/
  Services/
  Storage/
  Styles/
  Internal/


⸻

3. Repository Layout

apps/
web/
platform/
  stage/
  score/
  shared/
setup/
embedded/


⸻

4. Score — Framework

Score is a static-first Swift web framework.

⸻

4.1 Targets (single repository)

ScoreCore
ScoreHTML
ScoreCSS
ScoreRouter
ScoreRuntime
ScoreUI
ScoreAuth
ScoreContent
ScoreDB
ScoreAssets
ScorePayments
ScoreAI

Auth/UI/Content are targets — not separate repos.

⸻

4.2 Application Model

All apps begin with:

Application {
    pages {
    }

    api {
    }
}

Explicit routing only.

No filesystem discovery as primary system.

⸻

4.3 Automatic Rendering Mode

Score analyzes usage:
	•	static rendering default
	•	runtime added when needed
	•	hybrid produced automatically

Runtime emits BOTH:
	•	frontend routes
	•	API routes

Single routing truth.

⸻

4.4 Database Layer — ScoreDB

SQLite
	•	migrations
	•	typed queries
	•	lightweight ORM helpers

In-Memory Store (SwiftNIO)
	•	TTL cache
	•	sessions
	•	rate limiting
	•	pub/sub

⸻

4.5 REST APIs with Protobuf
	•	HTTP REST semantics
	•	protobuf request/response bodies
	•	Swift types generate schemas

HTTP remains canonical protocol.

⸻

4.6 Assets Pipeline — ScoreAssets

Automatic:
	•	image optimization
	•	AVIF/WebP generation
	•	responsive variants
	•	fingerprinting
	•	cache headers

Zero configuration required.

⸻

4.7 Styling System

ScoreCSS includes:

Tailwind-level documentation:
	•	every modifier documented
	•	examples
	•	generated CSS output
	•	searchable docs

Docs generated automatically.

⸻

4.8 Payments — ScorePayments

Built-in Stripe integration:
	•	subscriptions
	•	tiers
	•	webhook verification
	•	route gating middleware

Runtime feature only.

⸻

4.9 AI Integration — ScoreAI

Provides:
	•	provider abstraction
	•	API-key configuration
	•	embeddings
	•	tool calling
	•	webmcp support

Safe defaults required.

⸻

5. Stage — Hosting Platform

Stage is a hosting product, not a framework runtime.

⸻

5.1 Responsibilities
	•	Host static output
	•	Host runtime binaries
	•	Deploy apps
	•	Provide logs + environments
	•	Manage domains
	•	Enable experimentation

⸻

5.2 Hosting Modes

Stage Local

stage dev

Local parity hosting.

Stage Serverless

Managed hosting.

Stage Self-Hosted

Run .stage bundle anywhere.

⸻

5.3 Stage Workload Model (Generic Swift)

Stage hosts workloads defined by a manifest.

Inputs supported:
	•	.stage bundle
	•	Swift Package
	•	compiled Swift binary

Stage executes via generic Swift commands internally.

Score simply produces compatible workloads.

⸻

5.4 GitHub Integration

Stage GitHub App:
	•	repo linking
	•	automatic builds
	•	automatic deploys
	•	build logs
	•	deploy previews (future)

⸻

5.5 Domains

Default:

random-name.stage.tld

Optional:
	•	custom domains
	•	automatic TLS

⸻

5.6 CLI (Noora)

Stage CLI uses Noora for UX:
	•	spinners
	•	tables
	•	progress indicators
	•	structured errors

Supports:

stage dev
stage build
stage deploy
stage logs
stage serve


⸻

5.7 Serverless Playground (Swift Val.town Equivalent)

Stage includes instant experimentation.

Features:
	•	write Swift functions instantly
	•	zero setup
	•	ephemeral execution
	•	shareable URLs

⸻

Playground Editor

Built using:
	•	ScoreUI text editor
	•	WASM extension bundle providing:
	•	highlighting
	•	formatting
	•	completions
	•	diagnostics
	•	symbol navigation

Runs entirely in browser.

⸻

6. Libretto — Dogfood Platform

Validates ecosystem coherence.

Features:
	•	publishing workflow
	•	discovery feed (“similar posts”)
	•	embeddings-based recommendations
	•	AI assistant (basic free tier)

Uses entire stack.

⸻

7. Stage vs Score Boundary

Stage ≠ Score application.

Correct relationship:

Score builds apps
Stage hosts apps

Stage dashboard may use ScoreUI components.

⸻

8. Development Workflow

bootstrap.sh
↓
stage dev
↓
edit Swift
↓
automatic static/runtime decision
↓
deploy via git push or CLI


⸻

9. PRD-First Development Rule

Every module begins with:

PRD.md

Each PRD must include blank sections:

## Desired Syntax
[blank]

## Example Usage
[blank]

## DSL Goals
[blank]

## Anti-Goals
[blank]

Implementation begins only after PRD exists.

⸻

10. Initial PRDs Required

platform/score/PRD.md
platform/score/Sources/*/PRD.md
platform/stage/PRD.md
platform/stage/playground/PRD.md


⸻

11. Implementation Order (Reality-Safe)
	1.	Score static rendering
	2.	Stage Local hosting
	3.	Libretto static MVP
	4.	Automatic runtime detection
	5.	Runtime binary
	6.	Protobuf APIs
	7.	SQLite + memory store
	8.	Asset optimization
	9.	GitHub deploys
	10.	Playground
	11.	Payments
	12.	AI integration
	13.	Discovery system

⸻

12. Final Mental Model

Score

Swift framework producing deployable workloads automatically.

Stage

Universal Swift hosting platform.

Libretto

Proof the system works.

⸻

If you want next, the most important architectural lock we can do now is defining the Stage Workload Manifest (stage.yaml) — because once that exists, both Score and future non-Score Swift apps can target Stage without further architectural churn.