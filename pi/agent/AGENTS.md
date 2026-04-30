# Global AI Coding Instructions

## Workflow Efficiency

- Token and usage efficiency matter. Treat short-window and weekly usage limits as hard limits; use concise reasoning, avoid unnecessary repetition, and keep context focused so more useful work can be completed.
- As you work with the user, watch for bad habits, inefficient workflows, avoidable token use, and mismatched model usage. Suggest simple rules, automations, batching, or workflow changes that reduce friction.
- Choose tools, agents, and models appropriate to the task. Do not suggest switching the main-session model unless the user asks or there is a clear need, because switching may create a new session or lose useful continuity.
- When the user appears to misunderstand how the coding agent, tools, sessions, context, agents, or commands work, briefly explain the relevant feature and how to use it effectively.
- Use agents or agent teams for isolated research, boilerplate generation, design exploration, documentation drafting, and parallel review when it keeps the main session cleaner and more efficient.
- Batch related tasks logically. Group similar code changes and commits so work is easier to review, revert, and continue without wasting context.
- Keep commit messages and commit logs compact but comprehensive. Git history is useful project memory; preserve the what and why without unnecessary detail.

## Commits

- Never add co-authoring lines to commit messages (e.g. "Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"). Omit them entirely.
- Follow Apple-style commit messages by default across all projects, unless the project has an established convention.

  **Apple commit style** (as seen in github.com/apple repos like swift, swift-foundation, llvm-project):
  - Short imperative subject line (72 chars max, no trailing period)
  - Optional component prefix in brackets: `[stdlib] Fix crash in...` or `[TypeChecker] Add support for...`
  - Blank line between subject and body
  - Body wrapped at ~72 chars; explains *what* and *why* (not *how*)
  - Plain imperative mood: "Fix", "Add", "Remove", "Improve" — not "Fixed", "Adding", "Fixes #123"

## Code Style

Follow these guides for each language:

| Language | Style Guide |
|----------|-------------|
| Swift | [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) |
| JavaScript | [Google JavaScript Style Guide](https://google.github.io/styleguide/jsguide.html) |
| HTML/CSS | [Google HTML/CSS Style Guide](https://google.github.io/styleguide/htmlcssguide.html) |
| TypeScript | [Google TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html) |

### Fallback Rules
- When no specific guide exists for a language/framework, prioritize:
  1. Readability and consistency with existing codebase
  2. Semantic naming (avoid abbreviations)
  3. Minimal cognitive load for readers

## File Operations

- Never delete or modify files outside the explicitly scoped working directory
- Do not create excessive `.backup` files. Create backups only for major changes to non-git-tracked files, or for files without a recent commit history when rollback may be harder.

## Error Handling

- When encountering parse errors, missing dependencies, or unclear project structure:
  1. Ask for clarification before proceeding
  2. Suggest specific next steps or questions
  3. Never guess or make destructive changes
