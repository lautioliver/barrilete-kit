# AGENTS.md — <PROJECT>

Context for agents and people who touch this repo. `CLAUDE.md` only imports this file.

## What it is

TODO: one or two sentences. What it does and for whom.

How it is built today: `docs/architecture.md`. Decisions that are hard to revert: `docs/decisions/`.

## Stack and commands

TODO: language, framework, database.

```bash
# TODO: install, lint, test, dev
```

## Code conventions

TODO: the rules an agent would break if it did not read them (error format, where the logic goes, how dates or money are handled…).

## Agent autonomy

**Can do on its own:** change code and tests within what the issue asks, internal refactors, update docs, open PRs (never merge them).

**Must ask first** (that the issue asks for it is not the approval: it takes a "yes" from a person in the chat or in a comment of theirs on the issue or the PR): change the database schema, add or remove dependencies, touch auth or secrets, change an API that others use, touch deploy or CI, widen the scope of the issue.

**Never:** run migrations or delete data outside local, put secrets in the repo, disable tests or checks to make something pass, merge PRs, create tags or publish releases without an explicit request.

A hook (`scripts/agents/guardrails.py`, in `.claude/settings.json`) stops merging, approving PRs, pushing to trunk branches, tags, releases and `--no-verify` before they run. In Codex, Copilot and Cursor it is registered by `.codex/hooks.json`, `.github/hooks/guardrails.json` and `.cursor/hooks.json`. If it stops you, do not look for another way: ask the person to run it themselves (in Claude Code, with `! <command>`). Changing the hook, the script or those registrations requires asking first.

Sensitive paths of this project (TODO: fill in): schema `…`, auth `…`, deploy `…`.

### If it touches the database

Before writing the migration, show it and get it approved: current schema → desired, whether the deployed code keeps working, how the existing data is filled in and **how to roll back**. Dropping or renaming columns in use goes in two PRs: first the new one, then remove the old one.

## GitHub

Details in `docs/github-naming-convention.md`.

- **Branch:** <BRANCH_RULE> Names `<type>/<issue-no>-<description>`; if an agent creates it, `claude/<issue-no>-<description>`.
- **Commits and PRs:** `<type>: <description>` in the imperative and lowercase, with the description in <COMMIT_LANG> (`feat`, `fix`, `docs`, `chore`, `refactor`, `test`). PR body with `.github/pull_request_template.md` and `Closes #n`.
- **Labels:** one `type:` per issue and PR; `priority:` only on issues. Only those in `.github/labels.yml`.
- **Team:** new issues are assigned on their own to a member (by area and load). The team is changed with `/add-member` and `/remove-member`; do not edit the file by hand. Assigned = owner; in progress = with an open PR.
- **Issues:** with the `create-issue` skill. **Implement:** `/implement-issue <n>`. **Bugs:** `debug` skill.

## Docs

- `docs/README.md` — index
- `docs/architecture.md` — what runs today (if it does not match the code, the code wins and this gets fixed)
- `docs/decisions/` — ADRs
- `docs/github-naming-convention.md` — branches, commits, PRs, labels
