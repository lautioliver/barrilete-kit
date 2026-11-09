---
skill: implement-issue
issue: 219
pr: no PR
area: infra
paths: scripts/update.py, scripts/install.py, scripts/grow.py, scripts/test-update.sh, scripts/test-install.sh, CHANGELOG.md
date: 2026-11-09
skill_sha: 7efef22daf2a854a44d247ed515623cdc106037d
model: haiku
role: implementer-light
agent_sha: 96fd308065f1c623c92b2fbaabed40bd746e4180
---

**Deviations:** I escalated before writing anything: the worktree has no commits and no changes. The launch message did not give `retro_sh`, `agent_sha` or `skill_sha`, so I took the copy of `origin/main` for the retro script and left the two sha keys out (retro.sh fills them in).

**Decisions not covered:** the issue touches the `contexts` section of `docs/agents-map.json` and the tests of update, install and grow. ADR-003 (Consequences, line 56) says those are sensitive paths that need a person's approval, but `scripts/agents/agents_map.py` does not flag them: the `sensitive` list of `docs/agents-map.json` does not include them. The skill's checks and the ADR disagree, so I returned escalate instead of deciding it. Suggestion: add the ADR's paths to the `sensitive` list, or say explicitly that the issue is approved.

**What the review found:** not applicable (no code written).

**Proposal:** the implement-issue step 2 check on `agents_map.py` only sees the map's `sensitive` list. A rule that lives only in an ADR's text is missed. Consider a step that greps the ADRs of the touched area for "sensitive" or "approval".
