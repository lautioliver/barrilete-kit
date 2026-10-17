---
skill: implement-issue
issue: 150
pr: 164
area: infra
paths: .claude/skills/implement-issue/red.sh, .claude/skills/implement-issue/test-red.sh, .claude/skills/implement-issue/corpus/, scripts/agents/red_report.py, docs/decisions/kit/ADR-002-structured-red-validation.md, docs/decisions/kit/ADR-002-structured-red-validation.es.md, docs/agents-map.json
skill_sha: 6ec12861eb3ff04c0eefa85556d90a5816edd083
date: 2026-10-17
model: sonnet
role: implementer
agent_sha: 6ec12861eb3ff04c0eefa85556d90a5816edd083
---
**Deviations:** (1) Wrote the whole parser before the tests and had to set it aside outside the repo to get a clean red commit; the stub of red_report.py went in the red commit, the real one only in the green one. (2) Skills, agents and README still say `red.sh -- <command>`: I left them to #152/#153 because test-orchestrate.sh pins the old wording and #151 is migrating the kit tests in parallel. This leaves implement-issue step 3 describing a form that now exits 64. (3) The `/code-review` finding about stale docs was not fixed for the same reason; the PR says so.
**Decisions not covered:** how red.sh finds its `red` section and the repo under test (map of the checkout where red.sh lives, repo = cwd; needed for D7's trusted checkout, so no env override); the TAP id separator (` # `) since #151 had not decided it; reading the Rust test attribute from the red commit's file instead of the added lines (git shows it as context when a test is inserted before another with the same attribute); treating vitest file-level failures and gotestsum `TestMain` as errors, because both reporters write load failures as plain `failure`; an uncommitted-changes check; no `agents_map.py` import because the small profile deletes it. All are listed in the ADR header and the PR for the person to approve at merge. Also: ADR D4 says "classname" for go/cargo but the real reporters differ (nextest puts the module path in the name); the corpus for go/cargo is handwritten because those runners are not installed.
**What the review found:** 10 findings, 6 fixed (shell metacharacters of a stack name reaching `{out}`, TMPDIR checked after mkdtemp, `ok:` lines taken as TAP cases, a slash in a test title taken as a load failure, a misleading go.mod message, verify entry not watching red_report.py and the corpus). It also pointed at the stale docs, which is true and intentional.
**Proposal:** the skill could say what to do when the issue's code replaces a tool that the docs and a prose test in another file describe: it is easy to end with a PR that breaks the documented flow on purpose. Also: a verify `when` for a script should list the helper modules it calls (red.sh -> red_report.py), and the red/green cycle for self-review findings costs a commit pair each; batching them in one cycle was fine here.
