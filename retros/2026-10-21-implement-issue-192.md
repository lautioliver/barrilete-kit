---
skill: implement-issue
issue: 192
run: 20261020-2200
pr: 193
area: docs
paths: README.md, README.es.md
skill_sha: aa963263a1d5d108581d55612357817f2a207dca
date: 2026-10-21
model: haiku
role: implementer-light
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** (1) Ran `check-docs.py` and `agents_map.py` before the first push but not `scripts/test-renames.sh`, which the docs CI job runs. It failed on the old 0.9 file name written in the new block; fixed in a second commit. Before pushing docs, run the test-renames script too. (2) `/code-review` not run: the launcher forbids the Skill tool for it; bug pass done by hand (anchors, en/es parity, the four steps against the #116 entry, no secrets).

**Decisions not covered:** The old file name cannot be written in any kit file (test-renames), so the 0.9 note describes it as "the update script in `scripts/`". Heading "From 0.9" / "Desde 0.9" with the anchors `#from-09` / `#desde-09`. Kept the issue's `<tag>` placeholder in the curl line.

**What the review found:** Nothing from the self-review beyond the rename failure above.

**Proposal:** The skill's docs step could name `scripts/test-renames.sh` next to `check-docs.py`, since the docs CI job runs both and check-docs alone does not catch old names.
