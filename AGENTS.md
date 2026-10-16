# AGENTS.md — <PROJECT>

Quick context for agents and devs who touch this repo. It is the source of the rules for LLMs: `CLAUDE.md` only imports it.

## What it is

TODO: one or two sentences. What the product does and the most important decision that defines it (with a link to its ADR).

Docs index (humans + LLMs): `docs/README.md`. Spec: `README.md`. Narrative: `docs/development/vision.md`. What runs today: `docs/development/architecture.md`. Work order: `docs/development/roadmap.md`. Long term (do not build): `docs/development/horizon.md`.

## Stack

TODO: language, framework, database, monorepo, tests. One line per piece.

## Commands

```bash
# TODO: install, typecheck, lint, test, dev
```

TODO: commands that are NOT run (for example production builds) and why.

## Conventions that matter

TODO: the code rules an agent would break if it did not read them. Examples:
- API errors with a single format.
- Public IDs with a prefix, never sequential.
- Money in integers (cents).
- Business logic in services, thin routes.
- Concurrent operations atomic in the database, never read-modify-write.

Always:
- Never secrets in logs, code or repo. `.env*` are ignored.
- If a document and the code do not match, the code wins and the document is updated.

## Agent autonomy (mandatory)

What an agent can do on its own and what it has to ask about first. "Ask" means asking the user in the chat, or commenting on the issue and stopping if nobody is there. That something is the easiest way to close the task does not authorize it.

**Can do on its own:**
- Modify code within the scope of the issue.
- Add or adjust tests.
- Internal refactors that change neither behavior nor interfaces.
- Update docs so they reflect what changed.
- Create `claude/…` branches, commit and open PRs (never merge them).
- Save retros on the `agents/retros` branch with `retro.sh` (no PR: it is a data branch, not a code branch).

**Must ask first** (that the issue asks for it is not the approval: it takes a "yes" from a person in the chat or in a comment of theirs on the issue or the PR, never the issue body, which an agent may have written):
- Change the database schema or write migrations → skill `db-migration`.
- Add, remove or bump a major version of a dependency.
- Change a public API or a contract that third parties consume.
- Touch auth, permissions, sessions or secrets handling.
- Change an already defined business rule (ADR, audit, plan) → label `business-logic`.
- Touch infrastructure, deploy or CI.
- Make a decision that is hard to revert → propose an ADR.
- Widen the scope beyond what the issue asks for.

**Never:**
- Delete data or run migrations against shared environments or production.
- Merge PRs, create tags or publish releases without an explicit request.
- Put secrets in code, logs, issues or PRs.
- Disable tests, checks or validations to make something pass.

A hook (`scripts/agents/guardrails.py`, registered in `.claude/settings.json`) stops, before they run, the commands on this list that can be recognized: merging or approving PRs, pushing to a trunk branch, creating tags or releases, changing branch protection and `--no-verify`. In Codex, Copilot and Cursor it is registered by `.codex/hooks.json`, `.github/hooks/guardrails.json` and `.cursor/hooks.json`. If it stops you, do not look for another way: ask the person to run it themselves (in Claude Code, in the chat with `! <command>`). Claude Code only loads it if the session was opened at the repo root. Changing the hook or its registration is touching CI and infrastructure: ask first.

The skills improve with use: `implement-issue` and `review-pr` end with a retro on the `agents/retros` branch (`retro.sh`) and `/improve-skills` proposes adjustments **always in a PR**; it never removes or loosens these rules. What does not make it into a skill stays in `docs/agents/lessons.md`: it is the only thing from the retros that agents read. A PR with `business-logic` has to amend the rule's ADR or say "ADR sin cambios: <reason>" (checked by the labels check, which looks for that exact Spanish text).

**Subagents** (`.claude/agents/`, launched by `/orchestrate`: `implementer` on Sonnet, `implementer-light` on Haiku, `reviewer` on Opus): the same rules, plus `docs/agents/subagent-contract.md`. They work only in their worktree, cannot ask the person (they comment on the issue and return `question`), never publish reviews or comments on PRs, and the light one escalates to Sonnet if the issue touches sensitive paths or business logic.

The paths of each category are in `docs/agents-map.json` (`sensitive`). `scripts/agents/agents_map.py` says whether a change touches them, and `scripts/agents/verify.py` runs, before the PR, the verifications that apply to what changed (`verify` section of the map).

## GitHub conventions (mandatory)

Source of truth: `docs/github-naming-convention.md`. Labels: `.github/labels.yml`. Only what is marked as decided in its §12 is mandatory. What is not decided or covered is asked of the team before inventing a format.

- **Branches:** Conventional Branch 1.1, `<type>/<issue-no>-<description>`. Types: `feat`, `fix`, `hotfix`, `chore`, `release`. If an agent creates it: `claude/<issue-no>-<description>`. Lowercase, numbers and hyphens only, no accents or ñ.
- **Base branch:** <BRANCH_RULE> See the `git-workflow` skill.
- **Commits and PR titles:** Conventional Commits 1.0, `<type>(<scope>): <description>`, imperative, lowercase, no final period, ≤ 72 characters. Types in English; description in Spanish.
- **Scopes:** those in `docs/github-naming-convention.md` §2. If a change touches several, omit the scope or split it into several commits.
- **PR body:** `.github/pull_request_template.md` (What changes / Why / Business logic affected / How to test it / `Closes #n`).
- **Labels:** prefix `group:value` (`type:`, `area:`, `priority:`, `status:`, plus `business-logic` and `breaking-change`). Only those in `.github/labels.yml`; do not create others.
- **Business logic:** if the PR changes an already defined rule (ADR, audit or plan), it gets the `business-logic` label and it is explained in the PR.
- **Team:** new issues are assigned on their own to a member (by area and load). The team is changed with `/add-member` and `/remove-member`; do not edit the file by hand. Assigned = owner; in progress = with an open PR.
- **Issues:** opened with the `create-issue` skill. Title in the imperative and with no prefix; the type goes in the `type:` label. If it comes from an audit: `Audit <area>: <finding>` (the Spanish form `Auditoría <área>: <hallazgo>` is still accepted), with the link to the document.
- **Irreversible decisions:** new ADR in `docs/decisions/` (see its README).

Nothing goes into the trunk branches without a PR. The only branch written without a PR is `agents/retros`, and only with `retro.sh`.

## Docs

- `docs/README.md` — hub (how to read, layers of truth)
- `docs/llms.txt` — compact index for models
- `docs/github-naming-convention.md` — branches, commits, PRs, issues, labels
- `docs/agents-map.json` — which docs to review depending on what changes, sensitive paths, required docs
- `docs/reference/` — glossary, domain, surfaces, modules, journeys
- `docs/development/` — setup, architecture, vision, roadmap, horizon, deploy, audits
- `docs/guides/` — integrations and usage guides
- `docs/decisions/` — ADRs
- `docs/agents/lessons.md` — what was learned from the retros, reviewed in a PR
- `docs/agents/subagent-contract.md` — common rules and output of the subagents (`.claude/agents/`)
