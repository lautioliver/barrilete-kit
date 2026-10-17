# GitHub convention — <PROJECT>

> Decided on <DATE>. If something is not covered, ask before inventing a format.

## Branches

<BRANCH_RULE>

Format `<type>/<issue-no>-<description>` ([Conventional Branch](https://conventionalbranch.org/)): lowercase, numbers and hyphens only, no accents or ñ.

| Type | When |
|---|---|
| `feat/` | New functionality |
| `fix/` | Fixing a bug |
| `chore/` | Dependencies, config, docs, tooling |
| `claude/` | Branch created by an agent |

## Commits and PR titles

[Conventional Commits](https://www.conventionalcommits.org/): `<type>: <description>`, in the imperative, lowercase, no final period, ≤ 72 characters. The description is written in <COMMIT_LANG>. Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`. If it breaks compatibility: `feat!: …`.

## Pull requests

Body with [the template](../.github/pull_request_template.md) and `Closes #n`. Merged with squash. Nobody (agents included) pushes straight to the trunk branch.

## Issues

Title in the imperative, no prefix: `Add login with Google`. For bugs the symptom works: `The form does not save offline`.

## Labels

| Group | Values |
|---|---|
| `type:` | `feature`, `bug`, `task`, `docs` — exactly one |
| `priority:` | `high`, `medium`, `low` — only on issues |

Source: [`.github/labels.yml`](../.github/labels.yml). No others are created.

**Repos that already have labels:** the `labels.yml` sync deletes the ones that are not in the file. The installer (`install.py`) adds to the file the ones the repo already has (`gh label list`), in the `# ── project's own labels …` section, so the sync deletes none. The ones GitHub creates in every new repo (`bug`, `enhancement`…) stay there: delete them from that section if you do not want them.

## Versions

If they are published: [SemVer](https://semver.org/) with `v` (`v0.3.0`).
