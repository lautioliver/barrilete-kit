---
skill: implement-issue
issue: 173
pr: 180
area: infra
paths: scripts/test-init.sh, scripts/agents/test-agents.sh, scripts/agents/test-i18n.sh, scripts/agents/tap.sh, .claude/skills/implement-issue, .claude/skills/review-pr
skill_sha: 11a4784c1ce6b94f1cb0fd52550b4c1d8ea13c55
date: 2026-10-20
model: sonnet
role: implementer
agent_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
---
**Deviations:** no /code-review (the orchestrator said not to invoke it via the Skill tool); reviewed by hand. The red commit was amended three times (red re-proven each time with the trusted red.sh) because my own lint tests were wrong: `n=$(grep -c ...)` with no match is status 1 on a command that is not named grep, so it bails; and an id containing `$?` trips test-tap's "ids are literals" check. I found both only when I ran the green suite, so the red I first proved was not a good test.
**Decisions not covered:** how to prove a red for "the guide says X" and "the file no longer has form Y" (lint tests in test-i18n.sh, with `[x]` regex tricks so the pattern does not match itself, and `grep -q ...; [ $? -eq 1 ]` to assert absence). Chose the guide-side fix for the tap_run variants (open-ended blocklist otherwise). Added the output tail to tap_run's crash message so replacing the nested-tests loop did not lose the FAIL lines.
**What the review found:** nothing from code-review (not run). verify.py found a shellcheck SC2319 on the new `[ ]; tap_check $?` lines. CI docs failed once on test-install.sh:104 (not touched, passes locally and on rerun): flaky.
**Proposal:** the skill could say how to assert absence in a red (`grep -q`; `[ $? -eq 1 ]`) and warn that a `$(grep -c)` with no match bails. Running the whole verify.py takes about 40 minutes (init test); say so.
