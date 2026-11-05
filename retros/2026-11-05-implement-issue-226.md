---
skill: implement-issue
issue: 226
pr: 266
area: infra
paths: scripts/update.py, scripts/agents/red_report.py, scripts/agents/check-docs.py, docs/guides/red-per-runner.md, CHANGELOG.md
date: 2026-11-05
skill_sha: 4894be8faf6cb51c8aa11d4755e42728938f86e9
model: sonnet
role: session
---
**Deviations:** The `verify.py` run was killed when the window closed; I re-ran it. `shellcheck` failed (SC2016 in my test), I fixed it and ran only `shellcheck` again, not the whole of `verify.py`. The PR body says so. In the red I had to avoid forbidden forms (`! grep`, `$(cat file)`), found by rereading the rules, not by `red.sh`.
**Decisions not covered:** The issue says `update.py` replaces the kit's `bash` entry, but that was not implemented (only `con_red` existed) and needs a list of published `run`s. I implemented it from D8 (v1.0.0 and v1.1.0 runs, whitespace normalized) instead of asking: it is in the ADR, so I did not treat it as new. Also a fixture of `test-agents.sh` (`modo_small`) used a `tap` entry and broke on the warning: I changed it to `junit`.
**What the review found:** `/code-review medium`: 8 findings, one real (the CHANGELOG line of #225 said "si el proyecto no la tocó", which now contradicts this change; fixed). The others were by design (D8) or the same as existing `completar_red`.
**Proposal:** `verify.py` takes ~30 min; a way to run only the checks affected by the last commit would help when re-running after a small fix. The skill could say that an issue's described behavior may be unimplemented (check before scoping).
