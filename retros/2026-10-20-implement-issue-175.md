---
skill: implement-issue
issue: 175
pr: 177
area: docs
paths: .claude/skills/implement-issue/SKILL.es.md, docs/guides/README.es.md, scripts/test-init.sh, CHANGELOG.md
skill_sha: 11a4784c1ce6b94f1cb0fd52550b4c1d8ea13c55
date: 2026-10-20
model: sonnet
role: implementer
agent_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
---
**Deviations:** no /code-review (the orchestrator told me not to invoke it via Skill); reviewed by hand. Fixed a shellcheck SC2154 in the test after the red commit, in a separate commit.
**Decisions not covered:** check-docs exits 1 on findings, which the red-commit rules forbid expecting. I wrapped it in a python single program that always exits 0 and prints the output, run through tap_run out 0, and asserted on "Docs OK." That form is not in the guide. The TODO map was patched inside the test project. A --small --lang es case was not added: the existing one already passes check-docs.
**What the review found:** nothing (not run).
**Proposal:** document in the skill the idiom for programs whose failure is a verdict (python wrapper that prints the status), and that tap_run's `$out` needs a shellcheck SC2154 disable.
