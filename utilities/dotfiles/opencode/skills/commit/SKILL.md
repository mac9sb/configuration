---
name: commit
description: "Read this skill before making git commits"
---

Create a git commit for the current changes using Apple-style commit subjects (as commonly seen in apple/* repositories).

## Format

`<summary>`

- Use a short, direct subject line in sentence-style English.
- Prefer imperative or present-tense phrasing focused on the change.
- Keep the subject concise (ideally <= 72 chars), no trailing period.
- Do NOT use Conventional Commits prefixes like `feat:`, `fix:`, or `chore:`.

Examples:
- `Add rose pine themes for opencode`
- `Update opencode setup symlink handling`
- `Improve web browser skill scripts`

## Notes

- Body is OPTIONAL. If needed, add a blank line after the subject and write short paragraphs.
- Do NOT include breaking-change markers or footers.
- Do NOT add sign-offs (no `Signed-off-by`).
- Only commit; do NOT push.
- If it is unclear whether a file should be included, ask the user which files to commit.
- Treat any caller-provided arguments as additional commit guidance. Common patterns:
  - Freeform instructions should influence the subject and body.
  - File paths or globs should limit which files to commit. If files are specified, only stage/commit those unless the user explicitly asks otherwise.
  - If arguments combine files and instructions, honor both.

## Steps

1. Infer from the prompt if the user provided specific file paths/globs and/or additional instructions.
2. Review `git status` and `git diff` to understand the current changes (limit to argument-specified files if provided).
3. (Optional) Run `git log -n 50 --pretty=format:%s` to mirror recent project style.
4. If there are ambiguous extra files, ask the user for clarification before committing.
5. Stage only the intended files (all changes if no files specified).
6. Run `git commit -m "<summary>"` (and `-m "<body>"` if needed).
