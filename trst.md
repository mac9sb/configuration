Below is the regenerated, canonical ecosystem PRD — rewritten to incorporate all decisions made so far, including:
	•	Stage = hosting platform
	•	Score = static-first Swift framework
	•	Auth/UI/Content = Score targets
	•	Hybrid hosting (static default, runtime additive)
	•	Swift-first → Proto benefits
	•	SQLite + NIO memory store
	•	GitHub integration
	•	Asset optimization
	•	Stripe + AI integration
	•	Enterprise directory discipline
	•	No monolithic files
	•	Noora CLI
	•	Explicit routing via Application
	•	Tailwind-grade documentation expectations
	•	Val.town–style Swift serverless playground
	•	WASM editor extension built atop ScoreUI editor

This document is intended to live as:

platform/ECOSYSTEM_PRD.md

and act as the source-of-truth ecosystem design.

Every module begins life with a PRD.md containing blank syntax sections for you to define final DSL ergonomics later.

⸻

Allegro Ecosystem — Master Product Requirements Document

0. Purpose

Allegro is a vertically integrated Swift-native web ecosystem enabling developers to:
	•	Write everything in Swift
	•	Deploy anywhere (static hosts, custom servers, or Stage hosting)
	•	Gain benefits of external ecosystems (Protobuf, AI tooling, payments, serverless)
	•	Maintain strict runtime parity across environments

The ecosystem consists of:

Layer	Role
Score	Static-first web framework
Stage	Hosting + deployment platform
Libretto	Dogfood publishing platform


⸻

1. Core Philosophy

1.1 Static First, Runtime Optional

Score must always allow:

Swift → Static Site → Deploy Anywhere

Runtime is additive:

Swift → Runtime Binary → SSR + APIs

Stage hosts both seamlessly.

⸻

1.2 Hybrid Hosting Model (Non-Negotiable)

Stage is hybrid hosting:
	•	Static hosting enabled by default
	•	Runtime activated only when required

Static remains the performance baseline.

⸻

1.3 Swift As Source of Truth

Developers write Swift.

Score generates or integrates:
	•	Protobuf schemas
	•	optimized assets
	•	runtime manifests
	•	API contracts

Swift types define system behavior.

⸻

1.4 Enterprise Code Organization

Add to AGENTS.md:

Hard Rules
	•	No monolithic files.
	•	Feature-oriented directory layout.
	•	Public API surfaces remain small.
	•	Implementation pushed into internal modules.

Example:

Feature/
  Pages/
  API/
  Components/
  Models/
  Services/
  Storage/
  Styles/
  Internal/


⸻

2. Repository Structure

apps/
web/
platform/
  stage/
  score/
  shared/
setup/
embedded/


⸻

3. Score — Framework PRD (Overview)

Score is a static-first Swift web framework.

Targets (single repo)

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

NOT separate repositories.

⸻

3.1 Application Model

Score apps start from:

Application {
    pages { }
    api { }
}

Explicit routing only.

No filesystem discovery as primary mechanism.

⸻

3.2 Rendering Modes

Mode	Output
Static	HTML/CSS/JS
Runtime	Swift binary
Hybrid	Static + runtime

Runtime emits BOTH:
	•	frontend routes
	•	API routes

Single routing truth.

⸻

3.3 Database Layer (ScoreDB)

Includes:

SQLite Interface
	•	migrations
	•	typed queries
	•	lightweight ORM helpers
	•	SQL visibility preserved

In-Memory Store (SwiftNIO)
	•	TTL cache
	•	sessions
	•	rate limits
	•	pub/sub hooks

⸻

3.4 Protobuf REST APIs

APIs:
	•	HTTP REST semantics
	•	Protobuf request/response bodies
	•	Swift types generate schema artifacts

HTTP remains canonical protocol.

⸻

3.5 Asset Optimization (ScoreAssets)

Automatic:
	•	image resizing
	•	AVIF/WebP generation
	•	srcset generation
	•	asset fingerprinting
	•	cache headers

Zero-config defaults.

⸻

3.6 Styling System

ScoreCSS must ship with:

Tailwind-level documentation coverage, including:
	•	every modifier documented
	•	examples
	•	generated CSS output
	•	accessibility notes

Docs generated automatically from source definitions.

⸻

3.7 Payments (ScorePayments)

Built-in Stripe integration:
	•	subscriptions
	•	tier gating
	•	webhook verification
	•	billing middleware

Runtime-only feature.

⸻

3.8 AI Integration (ScoreAI)

Capabilities:
	•	provider abstraction via API keys
	•	webmcp integration
	•	embeddings
	•	tool calling
	•	structured responses

Safe defaults required:
	•	timeout
	•	retry
	•	cost visibility

⸻

4. Stage — Hosting Platform PRD (Overview)

Stage is a hosting product, not just runtime.

⸻

4.1 Responsibilities
	•	Host static builds
	•	Host runtime binaries
	•	Deploy applications
	•	Provide logs + environments
	•	Manage domains
	•	Enable experimentation

⸻

4.2 Hosting Modes

Stage Local

stage dev

Local parity hosting.

Stage Serverless

Managed hosting.

Stage Self-Hosted

Run .stage bundle anywhere.

⸻

4.3 GitHub Integration

Stage includes GitHub App:
	•	repo linking
	•	automatic builds
	•	automatic deploys
	•	deploy previews (future)
	•	build logs UI

⸻

4.4 Domains

Default:

random-name.stage.tld

Optional:
	•	custom domains
	•	automatic TLS

⸻

4.5 CLI

Uses Noora for UX.

Goals:
	•	beautiful output
	•	clear failures
	•	actionable next steps

Supports:

stage dev
stage build
stage deploy
stage logs


⸻

4.6 Serverless Playground (Val.town Inspired)

Stage includes a Swift-native experimentation environment.

Concept

Quick spin-up serverless functions written in Swift.

Features:
	•	instant execution
	•	ephemeral environments
	•	zero project setup
	•	shareable URLs

Equivalent philosophy to:
	•	val.town
	•	Deno Deploy playground

But entirely Swift-based.

⸻

4.7 Playground Editor

Built using:
	•	ScoreUI Text Editor
	•	WASM extension bundle providing:
	•	syntax highlighting
	•	formatting
	•	completions
	•	diagnostics
	•	symbol listing

Runs fully in browser.

⸻

4.8 Automatic Asset Handling

Stage automatically:
	•	caches optimized assets
	•	serves variants
	•	respects ScoreAssets manifests

⸻

5. Libretto — Platform Dogfood

Libretto validates ecosystem coherence.

Features:
	•	publishing workflow
	•	discovery feed (“posts like your interests”)
	•	embeddings-based similarity
	•	AI assistant
	•	basic free tier
	•	expanded paid tier

Uses:
	•	ScoreUI editor
	•	ScoreContent
	•	ScoreAI
	•	ScorePayments
	•	Stage hosting

⸻

6. Stage vs Score Relationship

Should Stage be built in Score?

Answer: No.

Reason:
	•	avoids circular dependency
	•	hosting must exist independently of apps

Correct model:

Stage hosts Score apps
Stage dashboard MAY use ScoreUI

Stage ≠ Score application.

⸻

7. Development Workflow

bootstrap.sh
↓
stage dev
↓
edit Swift
↓
instant rebuild
↓
deploy via git push or CLI


⸻

8. PRD-First Development Rule

Every platform module begins as:

PRD.md

Each PRD must include:

## Desired Syntax (Blank)
[developer fills later]

## Example Usage (Blank)

## DSL Goals (Blank)

## Anti-Goals (Blank)

Implementation cannot begin until PRD exists.

⸻

9. Initial PRDs Required

Create immediately:

platform/score/PRD.md
platform/score/Sources/ScoreUI/PRD.md
platform/score/Sources/ScoreAuth/PRD.md
platform/score/Sources/ScoreContent/PRD.md
platform/score/Sources/ScoreDB/PRD.md
platform/score/Sources/ScoreAssets/PRD.md
platform/score/Sources/ScorePayments/PRD.md
platform/score/Sources/ScoreAI/PRD.md

platform/stage/PRD.md
platform/stage/playground/PRD.md

Each contains blank syntax sections.

⸻

10. Implementation Order (Reality-Based)
	1.	Score static rendering
	2.	Stage Local static hosting
	3.	Libretto static MVP
	4.	Runtime binary
	5.	API + protobuf
	6.	SQLite + memory store
	7.	Asset pipeline
	8.	GitHub deploys
	9.	Serverless playground
	10.	Payments
	11.	AI integration
	12.	Discovery system

⸻

11. Final Mental Model

Score

Write Swift → produce static or runtime web apps.

Stage

Host, deploy, experiment, and observe those apps.

Libretto

Prove the ecosystem works.
