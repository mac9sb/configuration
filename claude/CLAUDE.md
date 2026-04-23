# Global Claude Code Instructions

## Commits

- Never add co-authoring lines to commit messages (e.g. "Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>" or similar). Omit them entirely.
- Follow Apple-style commit messages by default across all projects, unless the project already has an established commit convention.

  Apple commit style (as seen in github.com/apple repos like swift, swift-foundation, llvm-project):
  - Short imperative subject line, 72 chars max, no trailing period
  - Optional component prefix in brackets, e.g. `[stdlib] Fix crash in...` or `[TypeChecker] Add support for...`
  - Blank line between subject and body
  - Body wrapped at ~72 chars; explains *what* and *why*, not *how*
  - Plain imperative mood: "Fix", "Add", "Remove", "Improve" — not "Fixed", "Adding", "Fixes #123"
