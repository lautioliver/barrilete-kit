# GitHub naming convention — <PROJECT>

> **Status:** PROPOSAL — pending a team decision.
> **Date:** <DATE>
> **Scope:** branches, commits, pull requests, issues / Project items, labels, Project fields, milestones, tags and releases.
> **For agents:** once approved, this document is the source of truth. No agent should create branches, commits, PRs or issues with another format. If something is not covered, ask before inventing a new format.

Each section shows the **options** the industry uses, their pros and cons, and a **recommendation**. At the end there is a table to mark the decision.

---

## 0. Summary of the recommendation

| Element | Recommended format | Example |
|---|---|---|
| Branch | `<type>/<issue-no>-<description>` (Conventional Branch 1.1) | `feat/42-unified-user-view` |
| Branch created by an agent | `claude/<issue-no>-<description>` | `claude/57-payment-flow-audit` |
| Commit | `<type>(<scope>): <description>` (Conventional Commits 1.0) | `fix(checkout): avoid double charge on retry` |
| PR title | Same as a commit + `Closes #n` in the body | `feat(user): unify accounts by email` |
| Issue title | Imperative, no prefix; the type goes in *Issue Type* | `Unify buyer, attendee and organizer under a single email` |
| Labels | With a `group:value` prefix | `area:checkout`, `priority:high` |
| Tag / release | SemVer with `v` | `v1.2.0` |
| Milestone | Business milestone or version | `Event MVP 14-11` / `v1.0.0` |

---

## 1. Branches

### Option A — Classic Git Flow
Permanent `main` + `develop` branches, and temporary `feature/*`, `release/*`, `hotfix/*`.
- ✅ Very well known, clearly separates production from development.
- ❌ Heavy for a team of 2: `develop` has to be kept in sync and release branches made.

> ✅ **DECIDED (<DATE>):** short branches with a prefix (Conventional Branch 1.1). <BRANCH_RULE>

### Option B — GitHub Flow + Conventional Branch 1.1
A single permanent branch (`main`) and short branches with the format `<type>/<description>`.

The Conventional Branch specification defines the prefixes `feature/` (alias `feat/`), `bugfix/` (alias `fix/`), `hotfix/`, `release/` and `chore/`, and since v1.1.0 it adds prefixes for branches created by AI agents: `ai/`, `claude/`, `codex/`, `copilot/`, `cursor/`. Trunk branches (`main`, `master`, `develop`) carry no prefix.

Rules of the spec:
- Lowercase, numbers and hyphens only. No spaces, `_` or uppercase.
- Dots only in versions: `release/v1.2.0`.
- No double hyphens, nor at the start or the end of the description.
- Include the ticket number when there is one.

- ✅ Published standard, automatically validatable (there is a GitHub Action), goes well with Conventional Commits.
- ✅ The `claude/` prefix makes it possible to tell at a glance which work an agent did — useful for auditing.
- ❌ Requires discipline with the issue number.

### Option C — Ticket first
`<issue-no>-<description>` (it is what GitHub generates with the "Create a branch" button from an issue).
- ✅ Zero friction, perfect traceability with the issue.
- ❌ The name does not say what kind of change it is; no external standard backs it.

### Option D — By author
`<user>/<description>` (e.g. `lautaro/login`).
- ✅ You know whose each branch is.
- ❌ Git already gives that information; it does not say the purpose. Rarely used as a standard.

### Recommended format (B + issue number)
```
<type>/<issue-no>-<short-description>
```

| Type | When | Example |
|---|---|---|
| `feat/` | New functionality | `feat/42-unified-user-view` |
| `fix/` | Fixing a bug | `fix/51-qr-does-not-validate-offline` |
| `hotfix/` | Urgent fix in production | `hotfix/60-payment-gateway-down` |
| `chore/` | Dependencies, config, docs, tooling | `chore/58-update-dependencies` |
| `release/` | Preparing a version | `release/v1.0.0` |
| `claude/` | Branch created by a Claude agent | `claude/57-payment-flow-audit` |

**Exception: `agents/retros`.** A long-lived orphan branch where agents save their retros (one file per retro) with `.claude/skills/improve-skills/retro.sh`. It is a data branch: it carries no issue number, it is never merged and it is written without a PR, always with that script. If the repo protects branches with a broad pattern (`*`), exclude it, or the retros stay pending in `.git/pending-retros/`. Projects coming from 0.9 keep the `agentes/retros` branch: it is still read (`/improve-skills`), never written or deleted.

> **Decision to make:** do we use the short aliases (`feat/`, `fix/`) or the long ones (`feature/`, `bugfix/`)? Recommended: **short**, because they match the commit types.

---

## 2. Commits

### Option A — Conventional Commits 1.0 ⭐ recommended
```
<type>(<optional scope>): <description>

[optional body]

[optional footer]
```
The spec only requires `feat` and `fix`; `fix` is equivalent to a PATCH in SemVer, `feat` to a MINOR, and `BREAKING CHANGE` (or `!` after the type) to a MAJOR. The other types (`docs`, `refactor`, `test`, `chore`, etc.) come from the Angular convention and are the most used.

| Type | Use |
|---|---|
| `feat` | New functionality |
| `fix` | Bug fix |
| `refactor` | Internal change without changing behavior |
| `perf` | Performance improvement |
| `test` | Tests |
| `docs` | Documentation (README, wiki, audits) |
| `style` | Formatting, no logic change |
| `build` | Build, dependencies |
| `ci` | Pipelines, GitHub Actions |
| `chore` | Maintenance that does not fit the above |
| `revert` | Reverting a commit |

- ✅ De facto standard; allows automatic changelog and versioning.
- ❌ The list of types has to be learned.

### Option B — Gitmoji
`🐛 Fix QR validation`.
- ✅ Visual and fun.
- ❌ Less structured, hard to parse, emojis look different depending on the terminal.

### Option C — Free style in the imperative (Chris Beams' guide)
`Fix QR validation`.
- ✅ Simple.
- ❌ No type or scope, not automatable.

### Project scopes
Scopes should be few and stable, and match the `area:` labels. `db`, `api` and `docs` always exist.

TODO: `<scope-1>`, `<scope-2>`, `db`, `api`, `docs`

> Rule: if a change touches several scopes, omit the scope or split it into several commits.

### Additional rules
- Description in the imperative, lowercase, no final period, ≤ 72 characters.
- One commit = one logical change.
- Changes that break compatibility: `feat(api)!: ...` + footer `BREAKING CHANGE: ...`.
- Reference the issue in the footer: `Refs #42` or `Closes #42`.

---

## 3. Pull requests

### Option A — Title = Conventional Commit + squash merge ⭐ recommended
- PR title with the same format as a commit: `feat(user): unify accounts by email`.
- It is merged with **Squash and merge**, so the PR title becomes the commit on `main`.
- Body with `Closes #42` to close the issue automatically, or `Refs #42` if the PR is part of the issue but does not close it (a diagnosis, one step of several).
- ✅ Clean `main` history even if the intermediate commits are messy.

### Option B — Free title + merge commit
- ✅ Keeps the whole branch history.
- ❌ `main` ends up with commits of every kind; useless for an automatic changelog.

### Suggested body template
```markdown
## What changes
## Why
## Business logic affected (does it modify anything already defined in audits?)
## How to test it
Closes #
```
> The "Business logic affected" section is key to the project's goal: it forces declaring whether the PR touches something that had already been fixed. (The headings are the ones of the current `.github/pull_request_template.md`.)

---

## 4. Issues and GitHub Project items

### 4.1 Title

#### Option A — Type prefix in the title
`[BUG] The QR does not validate offline` · `feat: unified user view`
- ✅ The type is visible in any list.
- ❌ Duplicates information if labels or issue types are already used; titles end up inconsistent.

#### Option B — Title in the imperative, type as metadata ⭐ recommended
`Unify buyer, attendee and organizer under a single email`
- The title describes **what has to be achieved**, in the imperative, with no final period, understandable by someone reading it months later.
- The type is marked with **Issue Type** (if the repo is in an organization) or with a **`type:` label** (if it is a personal repo).
- ✅ Clean, filterable titles.

#### Option C — Title with a module ID
`[CHECKOUT] Avoid double charge on retry`
- ✅ Visually groups by area.
- ❌ Same duplication problem; better solved with an `area:` label.

**For bugs**, a descriptive title of the symptom is accepted instead of the imperative: `The QR does not validate offline`.

### 4.2 Issue type

GitHub has native **Issue Types**, generally available since April 2025, with three default types: Task, Bug and Feature. They are configured at the organization level (up to 25 types).

| Situation | What to use |
|---|---|
| The repo is in a GitHub **organization** | Issue Types: `Feature`, `Bug`, `Task` (+ optional `Epic`, `Audit`) |
| The repo is **personal** | Labels `type:feature`, `type:bug`, `type:task`, `type:audit` |

> **Decision to make:** is the repo in an organization? If not, it is worth moving it — Issue Types and several Projects features work better that way.

### 4.3 Hierarchy (sub-issues)
Use native **sub-issues** instead of task lists in the body:

```
Epic     →  Unified user view
 └ Feature →  Single login by email
    └ Task  →  Migrate users table
```

### 4.4 Own type: audit
Since the project generates audits, an `audit` type/label is proposed for issues that come from an audit, with the title:

`Audit <area>: <finding>` → `Audit payments: the webhook is not idempotent` (the Spanish form `Auditoría <área>: <hallazgo>` is still accepted)

And in the body the link to the corresponding audit document.

---

## 5. Labels

### Option A — GitHub default labels
`bug`, `enhancement`, `documentation`, `question`, etc.
- ✅ Nothing to configure.
- ❌ They do not indicate priority, size or area.

### Option B — Labels with a `group:value` prefix ⭐ recommended
A proposal popularized as "Sane GitHub Labels": group by prefix and use one color per group.

| Group | Values | Suggested color |
|---|---|---|
| `type:` | `feature`, `bug`, `task`, `audit`, `docs` (only if there are no Issue Types) | Purple |
| `area:` | The product's areas (TODO: see `.github/labels.yml`) | Blue |
| `priority:` | `critical`, `high`, `medium`, `low` | Red → gray |
| `status:` | `blocked`, `needs-info`, `triage` | Yellow |
| special | `breaking-change`, `business-logic` | Black |

> `business-logic`: marks any issue/PR that touches rules already defined. It requires review by the whole team.

**Labels are always in English** (the kit's `ADR-001`, R-2): they are identifiers, like commit types, and do not change with the installation language. Projects created with 0.9 migrate them with label-sync `aliases`: `.github/labels.yml` declares the old name of each renamed label and the sync renames it without losing the labels already set on issues and PRs.

The full old → new table is in the kit's `CHANGELOG.md`.

### Option C — Flat labels without a prefix
`high`, `payments`, `blocked`.
- ❌ Over time you no longer know which group each one belongs to.

**Rules:** lowercase, kebab-case, no accents (avoids problems in filters and URLs).

### Repos that already have labels
The `labels.yml` sync deletes the labels that are not in the file (`delete-other-labels: true`: it is what cleans `bug`, `enhancement`… in a new repo). When installing the kit in an existing repo, the installer (`install.py`) (#122) calls the function below and adds to the file the labels the repo already has (`gh label list`), with their color and description, in the `# ── project's own labels …` section. That way the sync deletes nothing and does not remove them from the issues. If `gh` cannot read the labels, the installer does not install: without them, the first sync would delete them. If you installed the kit by hand, run the command below before the first sync.

- Those labels may not have the `group:value` prefix: the PR check only counts the `type:`, `area:`, `priority:` and `status:` prefixes, and `check-docs.py` only checks that the areas in `team.json` exist: both accept any other name.
- If a repo label has the same name as one of the kit's (case-insensitive), a single entry remains: the color is the repo's and the description the kit's.
- The labels GitHub creates in every new repo (`bug`, `enhancement`…) stay as your own and are not cleaned up on their own: if you do not want them, delete them from that section. The installer names them in its summary.
- The merge is done **when installing and right before merging the installation** (a label created while the PR is open is not in the file and the first sync would delete it; the installer's summary brings the command): running it again after an update would leave the repo's old color over the kit's new one and would bring back as your own the labels the kit removed. `labels.yml` is not registered as the kit's: `update.py` treats it as the project's (it merges it against the previous kit version if it can; if not, it leaves the kit's in `.agent-kit/pending/`). It is integrated by adding the kit's new labels, never by replacing the file: the sync deletes whatever is not there.
- The merge is done by `scripts/agents/labels.py` (`gh label list --limit 1000 --json name,color,description | python3 scripts/agents/labels.py .github/labels.yml`) and is idempotent.

---

## 6. GitHub Project fields

Prefer **Project fields** over labels for what changes often (status, size, iteration).

| Field | Type | Values |
|---|---|---|
| Status | Single select | `Backlog` → `Ready` → `In progress` → `In review` → `Done` |
| Priority | Single select | `P0 critical`, `P1 high`, `P2 medium`, `P3 low` |
| Size | Single select | `XS`, `S`, `M`, `L`, `XL` |
| Iteration | Iteration | `Sprint 1`, `Sprint 2`… (or by week) |
| Area | Single select | same values as `area:` |

> **Decision to make:** priority as a Project field **or** as a label, not both.

---

## 7. Milestones

| Option | Example | When it fits |
|---|---|---|
| A — By version | `v1.0.0` | If numbered versions are published |
| B — By business milestone ⭐ | `MVP <milestone>` | When there is a concrete business date |
| C — By date | `2026-11` | If work is organized by months |

---

## 8. Tags and releases

**Semantic Versioning** with a `v` prefix: `v<MAJOR>.<MINOR>.<PATCH>` → `v1.0.0`, `v1.1.0`, `v1.1.1`.
- Pre-releases: `v1.0.0-beta.1`, `v1.0.0-rc.1`.
- While the product is not stable: `v0.x.y`.
- With Conventional Commits the number can be computed automatically (`feat` → MINOR, `fix` → PATCH, `!` → MAJOR).

<!-- releases:start -->
### Release branches

With active users, versions are prepared in short `release/vX.Y.Z` branches cut from `develop`. They are frozen (only fixes for that version), tested in staging and merged to `main` with their tag. Fixes go back to `develop`. A hotfix comes off `main`, goes to `main` and always goes back to `develop` and to the open `release/*`. Step by step in `.claude/skills/git-workflow/SKILL.md`.

A short `release/*` was chosen instead of a permanent `staging` branch: each version stays frozen and there is no third trunk branch that falls out of sync.
<!-- releases:end -->

---

## 9. Language

| Option | Detail |
|---|---|
| A — All in English | International standard; better for tools and for bringing in outside people |
| B — Types in English, descriptions in the team's language ⭐ | The types (`feat`, `fix`) are part of the standard and are not translated; the description is in the language the team and the business use |
| C — All in the team's language | Breaks compatibility with tools (`funcionalidad:` is not a valid type) |

> ✅ **DECIDED (<DATE>):** the description of commits and PR titles is written in <COMMIT_LANG> (the language chosen at install, `--lang`). Types and scopes stay in English.
<!-- template:start -->
> In this repo (the template itself) the descriptions are in Spanish.
<!-- template:end -->

**Always without accents or ñ in branch and label names** (`user-view`, `design`, not `diseño`).

---

## 10. Rules for agents

To include in the repo's `CLAUDE.md` / `AGENTS.md`:

```markdown
## Naming conventions (mandatory)
- Branches: `<type>/<issue-no>-<description>`; if an agent creates it, use `claude/<issue-no>-<description>`.
- Branch types: feat, fix, hotfix, chore, release, claude.
- Commits and PR titles: Conventional Commits 1.0 → `<type>(<scope>): <description>`.
- Valid scopes: those in §2.
- <BRANCH_RULE>
- Never push directly to the trunk branches. Everything goes in through a PR.
- Exception: `agents/retros` (the retros' data branch), only with `retro.sh`.
- If the change modifies business logic already defined, add the `business-logic` label and explain it in the PR.
- See docs/github-naming-convention.md for the detail.
```

---

## 11. How to enforce it (optional)

| What | Tool |
|---|---|
| Branch name | GitHub Action `commit-check-action` or a GitHub Ruleset with a name pattern |
| Commit message | `commitlint` + `husky` hook, or `commit-check` |
| PR title | Action `amannn/action-semantic-pull-request` — included in `.github/workflows/pr-title.yml` |
| Protected trunk branches | Ruleset: PR required, 1 approval, no force-push |
| Labels | `.github/labels.yml` file + sync Action |

---

## 12. Decision table

Mark the option chosen by the team and the date:

| # | Topic | Chosen option | Date | Notes |
|---|---|---|---|---|
| 1 | Branches | ✅ Conventional Branch 1.1 | <DATE> | <BRANCH_RULE> Exception: `agents/retros`, the retros' data branch (§1). |
| 2 | Commits | | | scopes confirmed? |
| 3 | PRs | | | squash merge? |
| 4 | Issue titles | | | |
| 4.2 | Issue type | | | repo in an organization? |
| 5 | Labels | ✅ B — `group:value` prefix, in English | <DATE> | Comes decided in the template; source in .github/labels.yml (the kit's `ADR-001`) |
| 6 | Project fields | | | priority as a field or a label? |
| 7 | Milestones | | | |
| 8 | Versioning | | | |
| 9 | Language | ✅ B — types in English, description in <COMMIT_LANG> | <DATE> | Comes decided from the installation language (`--lang`) |

---

## Sources
- Conventional Branch 1.1.0 — https://conventionalbranch.org/
- Conventional Commits 1.0.0 — https://www.conventionalcommits.org/en/v1.0.0/
- GitHub Changelog, sub-issues and issue types (GA) — https://github.blog/changelog/2025-04-09-evolving-github-issues-and-projects/
- GitHub Docs, planning work with issues — https://docs.github.com/en/issues/tracking-your-work-with-issues/learning-about-issues/planning-and-tracking-work-for-your-team-or-project
- Sane GitHub Labels (Dave Lunny) — https://medium.com/@dave_lunny/sane-github-labels-c5d2e6004b63
- Semantic Versioning 2.0.0 — https://semver.org/
