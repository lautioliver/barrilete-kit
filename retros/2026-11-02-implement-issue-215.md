---
skill: implement-issue
issue: 215
pr: 223
area: agents
paths: docs/decisions/kit/ADR-003-minimal-ddd-glossary-and-contexts.md, docs/decisions/kit/ADR-003-minimal-ddd-glossary-and-contexts.es.md
date: 2026-11-02
skill_sha: 6af6e0f7f6d6586c037d1da72ae7bd34eca4bff0
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** I did not run `/code-review` on the corrections nor save the retro right at the end: it was asked for afterwards. I did not run the full `test-init.sh` to the end locally (it exceeds the 120 s tool timeout); I relied on CI for it and reproduced the small profile by hand.
**Decisions not covered:** how to cite in a kit ADR a path that exists in the full profile but not in `--small`. I dropped the backticks (same as for paths that do not exist yet), which `check-docs.py` then accepts. Also: the review said "do not touch test-init.sh", so the fix went to the ADR text only.
**What the review found:** (1) the ADR named `install.py`, forbidden by `test-init.sh` case 19 in installed docs; (2) the sensitive-path consequence presented the ADR as the approval, against AGENTS.md; (3) stale "does not exist yet" sentence, bare `#214`, "Tactical patterns in the glossary". The review did NOT see a second CI failure: in `--small`, `check-docs.py` rejected backticked `docs/reference/{domain,modules,glossary}.md`. I only found it after the first fix left CI red.
**Proposal:** in `implement-issue`/`review-pr`, for a doc that the init installs in projects, ask to run `init-template.sh --small` (and full) and `check-docs.py` on the result before the PR; a CI red on `test-init.sh` hides later failures because the test bails out at the first crash. Also `gh pr checks --watch` exceeds the tool timeout: suggest polling in a loop.
