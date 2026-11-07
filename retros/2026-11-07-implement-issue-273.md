---
skill: implement-issue
issue: 273
pr: 277
area: infra
paths: scripts/agents/tap.sh, scripts/agents/test-tap.sh, .claude/skills/implement-issue/SKILL.md, .claude/skills/implement-issue/SKILL.es.md
skill_sha: da5949abe3ed0fed29aa083488f521ab3d37d48e
date: 2026-11-07
model: haiku
role: implementer-light
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** the `/code-review` self-review was not run: the launcher forbids invoking it under /orchestrate, so the bug pass was done by hand over the full diff against main (declared as `no code-review: forbidden under /orchestrate, bug pass by hand`). The red was run with the old helper restored in the working tree for that run only, because red.sh runs the working tree and not the commit. The verify.py run took about 15 minutes (test-i18n, test-update, test-install); it was run in the background. The `test-tap.sh` cases that set `TAP_FORMAT=tap` were not deleted but moved to read the stdout TAP stream, which is the path that stays. Eight file-only checks were removed in four blocks (several scripts in one file, the plan left by an earlier bailed script, the stdout-to-file injection check, which never tested anything because the child stdout was always redirected elsewhere, and the "writes nothing to stdout when it has an output file" check).

**Decisions not covered:** whether `TAP_FORMAT=tap` without `TAP_OUT` should also fail closed. The skill is silent. I kept the existing rule (the check runs only when there is a TAP_OUT, as it did for unknown values) and flagged it for the reviewer in the PR body. Whether to edit the two `implement-issue` skill files was also not covered: they cited `TAP_FORMAT=tap` in the "Bail out!" sentence, so I corrected that parenthetical in the same PR (the lessons say to correct stale phrases in the same PR).

**What the review found:** nothing from the bug pass beyond the order of the TAP_FORMAT check (moved before opening the file, so a rejected run creates no file). Mutation checks on a copy of the tree: accepting `tap` fails the three `TAP_FORMAT=tap` cases; dropping the check fails those and the three unknown-format cases.

**Proposal:** `verify.py` took about 15 minutes here (test-i18n, test-update, test-install), with other agents on the same machine; the skill could say that it is slow and that it can run in the background. Also, `red.sh` runs the working tree, not the commit: when the red commit only adds tests for code that changes in the same PR, the skill could say how to run the red with the old code (`git checkout` of the code file for the run only, then restore it).
