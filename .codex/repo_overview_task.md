# Repo Overview Maintenance

For this repository, maintain a single Markdown file at `.codex/repo_overview.md`.

The file must contain these headings:

- `# Repository Overview`
- `## 1. High-Level Purpose`
- `## 2. Main Components and Functionality`
- `## 3. Work In Progress, TODOs, and Stubs`
- `## 4. Broken, Failing, or Conflicting Areas`
- `## 5. Notes for Future Work`

Workflow:

1. Scan the project structure and identify the main modules, crates, packages, scripts, and workflow files.
2. Inspect entrypoints such as `Cargo.toml`, `src/main.rs`, scripts, tests, and CI files to describe what is actually implemented now.
3. Search for `TODO`, `FIXME`, `XXX`, `HACK`, `BROKEN`, `TEMP`, `todo!`, `unimplemented!`, `unimplemented`, `NotImplemented`, and similar markers.
4. Run the repo’s standard non-destructive checks when they are clear from the repository layout.
5. Refresh `.codex/repo_overview.md` so it is a current snapshot of the repo instead of an append-only log.

Style:

- Keep it factual, concise, and neutral.
- Distinguish between implemented behavior and intended future direction.
- Include file paths and line references when listing TODOs, stubs, or broken areas.
- If something is ambiguous, say so briefly instead of guessing.
