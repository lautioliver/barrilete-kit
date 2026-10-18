---
skill: implement-issue
issue: 165
pr: 169
area: infra
paths: scripts/agents/tap.sh, scripts/agents/test-tap.sh, all test-*.sh of the kit, implement-issue and review-pr SKILL.md/.es.md, corpus tap-bash-crash-status-1
skill_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
date: 2026-10-18
model: sonnet
role: implementer
agent_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
---
**Deviations:** `/code-review` not run (forbidden through the Skill tool by the orchestrator), hand review instead. Red-first held for the probes of the review round (red commit 8075927, valid with the trusted red.sh), but the tap_status/tap_no_traceback helpers and their tests came in the green commit together.
**Decisions not covered:** the first design (ERR + DEBUG reading `$?`) was a dead end: it could not see crashes inside arguments, pipelines, functions or subshells. The second one (set -E + pipefail, ERR everywhere, assertion tools by name, tap_run/tap_status for programs that may fail) closes them. A crash in a command substitution under `|| true` only bails on bash 3.2, not on bash 5, so `|| true` stays a documented waiver.
**What the review found:** blockers 1 and 2 (crash inside an assertion's arguments, at the head of a pipeline, in a function or subshell) and the fail-open `ec` idiom. CI on bash 5 found what 3.2 hid: failing subshells fire ERR on the parent, `rm -rf` of a read-only tree fails, the `|| true` difference. A latent false green in test-agents.sh (`! check | grep -q` passing through SIGPIPE under pipefail) showed up once the pipeline was honest.
**Proposal:** say in implement-issue that tap.sh must be tested on bash 3.2 and bash 5 (CI is the only bash 5 here), and that a bash test helper should be validated by the reviewer's probe list (arguments, pipe head, here-string, process substitution, function, subshell) before the first PR.
