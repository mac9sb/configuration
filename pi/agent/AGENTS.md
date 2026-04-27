# Global Claude Code Instructions

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
- Create backups of modified files with `.backup` extension before changes
- Use descriptive filenames for new files (e.g. `user-auth-service.swift` not `auth.swift`)

## Error Handling

- When encountering parse errors, missing dependencies, or unclear project structure:
  1. Ask for clarification before proceeding
  2. Suggest specific next steps or questions
  3. Never guess or make destructive changes
