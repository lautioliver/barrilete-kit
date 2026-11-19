---
skill: implement-issue
issue: 325
pr: 371
area: infra
paths: scripts/agents/guardrails.py, .codex/hooks.json, .cursor/hooks.json, .github/hooks/guardrails.json, packages/pi/extensions/guardrails.ts, docs/agents-map.json
date: 2026-11-19
skill_sha: 7fe49d2d1ce2184e3a28f4aaa34a6fcd9570a9a9
model: sonnet
role: session
---
**Deviations:** none that I know of. The ask-first approval was obtained before code. The red commit had the 15 first cases; the hung-store cases went in the fix commit, not a separate red (a test that hangs for minutes is a poor red).
**Decisions not covered:** (1) the red runner only supports bash tests, so the pi case (TypeScript) is outside the red block; (2) the new test file needs an entry in `docs/agents-map.json` (test-agents #43), which the skill does not mention; (3) the issue's HTML path (Desktop) conflicted with the person's iCloud rule: used Downloads under "use my judgment".
**What the review found:** /code-review: a slow store could delay or lose the verdict (important; fixed with write-after-verdict plus a 3 s alarm and a hung-git test), `BaseException` swallowed, `import learning` by name, pi test not isolating env. A copilot regression I introduced while moving the output (it stopped printing to stderr) was caught only by re-reading, not by a test: the test does not assert copilot's exit code.
**Proposal:** a red case per harness should assert exit code and stderr too; and warn in the skill that a new `test-*.sh` needs a map entry.
