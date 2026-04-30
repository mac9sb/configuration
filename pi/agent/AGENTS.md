# Global AI Coding Instructions

## Operating Principles

- Optimize for useful progress with minimal context use. Keep reasoning concise,
  avoid repetition, and preserve context budget as a scarce resource.
- Prefer existing project conventions over generic preferences. Match naming,
  structure, testing style, and architecture before introducing new patterns.
- Ask clarifying questions when requirements, scope, or risk are unclear. Do not
  guess when guessing could cause destructive or hard-to-revert changes.
- Explain relevant agent, tool, session, or context mechanics briefly when the
  user appears to misunderstand them.
- Watch for inefficient workflows, avoidable token use, and mismatched tool or
  model choices. Suggest simple rules, batching, automation, or workflow changes
  that reduce friction.

## Planning and Execution

- Start with inspection before implementation when project structure, existing
  behavior, or risk is unclear.
- Batch related tasks logically so changes are easier to review, revert, and
  continue later.
- Keep final decision-making and integration in the main session.
- Use agents or agent teams for isolated research, boilerplate generation,
  design exploration, documentation drafting, and parallel review when that keeps
  the main session cleaner and more efficient.
  - Do not delegate tasks requiring full project context, architectural judgment,
    or user-specific decisions.
- Do not suggest switching the main-session model unless the user asks or there
  is a clear need, because switching may create a new session or lose useful
  continuity.

## Code Style

Follow these guides unless the repository has stronger local conventions:

| Language | Style Guide |
|----------|-------------|
| Swift | [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) |
| JavaScript | [Google JavaScript Style Guide](https://google.github.io/styleguide/jsguide.html) |
| HTML/CSS | [Google HTML/CSS Style Guide](https://google.github.io/styleguide/htmlcssguide.html) |
| TypeScript | [Google TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html) |

When no specific guide exists, prioritize:

1. Readability and consistency with the codebase
2. Semantic naming; avoid unclear abbreviations
3. Minimal cognitive load for future readers

## File Operations

- Never delete or modify files outside the explicitly scoped working directory.
- Avoid creating `.backup` files. Create backups only for major changes to
  non-git-tracked files, or for files without useful commit history.
- Prefer small, targeted edits over broad rewrites unless a rewrite is simpler
  and explicitly within scope.
- Preserve user changes. Check status or diffs before modifying files that may
  already have uncommitted edits.

## High-Risk Operations

- Ask before running migrations, dependency upgrades, lockfile rewrites,
  deployment commands, infrastructure changes, CI modifications, destructive
  file operations, or large-scale automated formatting.
- Prefer inspection before execution.
- Never assume a command is safe only because it is common.

## Validation

- Run the smallest relevant validation first: targeted test, typecheck, lint, or
  build before broad full-suite runs.
- Prefer fast feedback loops over expensive full-project validation.
- If validation cannot be run, state why and suggest the next best check.
- Report validation results accurately, including failures and skipped checks.

## Error Handling

When encountering parse errors, missing dependencies, failing tools, or unclear
project structure:

1. Stop and summarize the issue.
2. Ask for clarification if needed.
3. Suggest concrete next steps.
4. Avoid destructive changes and broad guesses.

## Commits

- Never add co-authoring lines to commit messages, such as
  `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`.
- Keep commit messages and commit logs compact but comprehensive. Git history is
  useful project memory; preserve the what and why without unnecessary detail.
- Follow Apple-style commit messages by default unless the project has an
  established convention:
  - Short imperative subject line, 72 characters max, no trailing period
  - Optional component prefix, for example `[stdlib] Fix crash in parser`
  - Blank line between subject and body
  - Body wrapped at roughly 72 characters; explain what and why, not how
  - Imperative mood: `Fix`, `Add`, `Remove`, `Improve`
