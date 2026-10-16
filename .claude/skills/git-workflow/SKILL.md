---
name: git-workflow
description: Branch, commit and PR flow of this repo. Use whenever you create branches, commits, pushes or pull requests.
---

# Git workflow — <PROJECT>

Details in `docs/github-naming-convention.md`. Mandatory summary in `AGENTS.md`.

## Branches

- <BRANCH_RULE> Create the working branch from an up-to-date `<BASE_BRANCH>`.
- Name: `claude/<issue-no>-<description>` (agent) or `<type>/<issue-no>-<description>` (person). Lowercase, numbers and hyphens only.
- If there is no issue, ask whether to open one (skill `create-issue`) before inventing the number.

<!-- releases:start -->
## Releases (`develop` → `release/*` → `main`)

To publish without touching production until the version is tested:

1. **Cut the release** from an up-to-date `develop`: `release/vX.Y.Z` (SemVer, see convention §8). From then on `develop` keeps receiving work for the next version.
2. **Freeze.** Only fixes for that version go into `release/vX.Y.Z`, through a PR based on `release/vX.Y.Z`. No new features.
3. **Test** the release in the staging environment before merging.
4. **Publish:** PR `release/vX.Y.Z` → `main`. On merge, tag `vX.Y.Z` on `main`.
5. **Return to `develop`:** PR `main` → `develop` (or `release/vX.Y.Z` → `develop`) so the release fixes are not lost. Then the `release/*` branch is deleted.

Hotfix (something broken in production):

- It comes off `main`: `hotfix/<issue-no>-<description>`, PR to `main`, PATCH tag (`vX.Y.Z+1`).
- **It always goes back to `develop`**, and to the open `release/*` if there is one. If it does not go back, the bug reappears in the next version.

An agent does not cut releases, merge to `main` or create tags unless explicitly asked.
<!-- releases:end -->

## Commits

- `<type>(<scope>): <description>` — imperative, lowercase, no period, ≤ 72 characters. Types in English; the description in <COMMIT_LANG>.
<!-- template:start -->
- In this repo (the template itself) the descriptions are in Spanish.
<!-- template:end -->
- One commit = one logical change. If it touches several scopes: no scope, or split.
- Breaks compatibility: `feat(api)!: …` + footer `BREAKING CHANGE: …`.

## Pull requests

1. Never push directly to the trunk branches. Everything goes in through a PR.
2. Title with the same format as a commit.
3. Body from `.github/pull_request_template.md`: What changes / Why / Business logic affected / How to test it / `Closes #n`.
4. Labels: exactly one `type:` (`claude/` branches do not get it automatically: set it yourself), 1–2 `area:`, no `priority:`. Only labels from `.github/labels.yml`.
5. If it changes a rule from an ADR, audit or plan: label `business-logic` and explain it in "Business logic affected".

```bash
gh pr create --base <BASE_BRANCH> --title "fix(api): …" --body-file <file> --label "type:bug" --label "area:api"
```
