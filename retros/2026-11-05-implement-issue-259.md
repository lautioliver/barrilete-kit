---
skill: implement-issue
issue: 259
pr: 262
area: docs
paths: docs/agents/classes.yml, .claude/skills/review-pr/SKILL.md, .claude/skills/review-pr/SKILL.es.md, scripts/agents/check-docs.py, scripts/agents/test-classes.sh, docs/agents-map.json, profiles/small/DELETE
date: 2026-11-05
skill_sha: eebc5b81b1f369c46b9e237b22ddf848160eeb11
model: sonnet
role: session
---
**Deviations:** the PR went red in CI four times before green, all on things I did not run locally before pushing: (1) the test grepped the `.es.md` skill, which an installed single-language project does not have; (2) the test assumed `check-docs.py` exits 0 on a freshly installed project (it does not: TODO placeholders); (3) `--small` deletes `review-pr` and `docs/agents` but I had not added `test-classes.sh` to `profiles/small/DELETE`; (4) my new `verify` entry in `agents-map.json` listed `SKILL.es.md` without `?`, and `test-install.sh` flagged it. I only ran `test-classes.sh`, `check-docs.py` and `verify.py` locally; `test-init.sh` and `test-install.sh` are the ones that exercise the installed and `--small` shapes. I also rewrote the second red commit once (amend) because my own test used a broken link target and failed for the wrong reason. Twice I read the result of `gh pr checks --watch` as if it belonged to the new commit when it was the previous run.
**Decisions not covered:** where `classes.yml` lives (I picked `docs/agents/classes.yml`, next to `lessons.md`); that `other` is reserved and not listed in the file; that a tag is only validated when it is a `[id]` inside a code span; adding a `classes` entry to the `verify` section of the map; adding a line to `profiles/small/DELETE`. None of these was in the issue; I flagged the ADR point in the PR.
**What the review found:** `/code-review` (medium): the regex took any `[word]` as a class (fixed: code span only), the check was silently skipped when `classes.yml` was missing (fixed), test mode 644 vs 755 (fixed). Not fixed, explained in the PR: no `.es` copy of the yml, hardcoded 9 ids in the test, the test checks the example and path rather than the wording.
**Proposal:** in implement-issue step 7, when the change adds a file, a test or a map entry, also run `scripts/test-init.sh` and `scripts/test-install.sh` locally (CI runs them and they take minutes); and say that a new `test-*.sh` for something that `--small` deletes must go in `profiles/small/DELETE`.
