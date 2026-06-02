## Agent skills

### Issue tracker

Issues and PRDs for this repo live as markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage roles using default label names from `mattpocock/skills`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repo — one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
## Git Workflow Automation Rule
- ⚠️ **CRITICAL RULE**: After successfully completing any feature development, bug fix, or code modification requested by the user, you MUST automatically commit and push the changes to GitHub.
- Do NOT ask the user for permission to commit; proceed automatically if the task is done and tests/builds pass.
- Use the standard command: `git add . && git commit -m "prefix: brief message" && git push origin main`
- Standard commit prefixes: `feat:` (new features), `fix:` (bug fixes), `docs:` (documentation), `refactor:` (code cleanup).