---
skill: implement-issue
issue: 158
pr: 159
area: docs
paths: docs/decisions/kit/ADR-002-structured-red-validation.md, docs/decisions/kit/ADR-002-structured-red-validation.es.md, scripts/agents/check-docs.py, scripts/agents/test-i18n.sh, .claude/skills/project-status/status.sh
skill_sha: e2fea7e23d5849f4d4108796eaffbf3d1baba088
date: 2026-10-17
model: sonnet
role: implementer
agent_sha: 37b007a181fdbaec3233a2eabb71bda500ec2514
---
**Deviations:** none. The gh repo is lautioliver/barrilete-kit, so the PR number (159) differs from the origin URL name; no impact.
**Decisions not covered:** how to say "approved when merged" inside an ADR without it reading as an agent claiming approval; chose to name the PR and list the refinements. Also how to red-test ADR prose: grep of fixed phrases in test-i18n.sh (brittle, flagged by code-review). Kit-vs-project test reused the existing `scripts/init-template.sh` proxy. The `shellcheck disable` directive only covers the next command unless placed in the file header.
**What the review found:** 7 possible findings; fixed the misleading comment; left the rest with reasons in the PR (approval wording needs the person to confirm, init-template proxy, prose-pinning tests, nested testsuite and it.each edge cases).
**Proposal:** the skill could say how to red-test docs-only ADR changes (phrase greps vs "no tests: <reason>").
