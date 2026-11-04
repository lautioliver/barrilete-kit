---
skill: implement-issue
issue: 222
pr: 230
area: docs
paths: docs/decisions/kit/ADR-002-structured-red-validation.md, docs/decisions/kit/ADR-002-structured-red-validation.es.md
date: 2026-11-04
skill_sha: eebc5b81b1f369c46b9e237b22ddf848160eeb11
model: sonnet
role: session
---
**Deviations:** none that change the flow. Docs-only PR, so no red (`no tests:` stays). `/code-review` not rerun: the round only edits prose of the two ADR files.
**Decisions not covered:** five points of the third review (`# file:` only with `format: tap`, a repeated id as one case, the XML root written by `red.sh`, `TAP_FORMAT` failing closed, the file rule on a `tap` entry) are rules the person did not decide ("como propone el reviewer"). I wrote them and listed them in the ADR header and the PR as not decided by the person, so they need a yes. The reviewer offered two options for the repeated id; I picked "one case".
**What the review found:** the D6 file-check rejected valid reds (cargo stubs, conftest, mocks, deleted files, go classname); the kit's own `# file:` guard cannot work on XML.
**Proposal:** the retro/review loop would be shorter if a reviewer marked which findings need a person's decision and which are plain fixes.
