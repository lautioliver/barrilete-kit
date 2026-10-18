---
skill: implement-issue
issue: 165
pr: 169
area: infra
paths: scripts/agents/tap.sh, scripts/agents/test-tap.sh, the 12 test-*.sh of the kit, .claude/skills/implement-issue/corpus/tap-bash-crash-status-1, implement-issue SKILL.md/.es.md
skill_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
date: 2026-10-18
model: sonnet
role: implementer
agent_sha: ad4d60d41ed31965ff500a01b9fedd8ac9e7fea2
---
**Deviations:** `/code-review` was not run: the orchestrator forbade it through the Skill tool, so I reviewed the diff by hand (`self-review:` says so). I ran a bare `git stash` once by mistake (shared stack) and restored my own entry by SHA right away. Base was given as `main`, but the local `main` is stale; I used `origin/main` for diffs and `BASE=origin/main` for verify.py.
**Decisions not covered:** how to tell a crash from a checked status in bash. I used ERR + DEBUG traps: a failure must be read (`$?`) by the next command, and when `tap_check $?` reads it straight the command must be an assertion (builtins, grep/diff/cmp with status 1, or functions declared with `tap_assertions`, which are wrapped). Programs under test use `|| ec=$?; [ "$ec" -eq 0 ]`. Documented limits stay in the tap.sh header. A red test cannot use a `check $?` wrapper: `red_report.defines()` needs `tap_check <status> "id"` on an added line.
**What the review found:** hand review only. CI found what local runs did not: bash 3.2 (macOS) differs from bash 5 (CI) for failing subshells (3.2 never calls the ERR trap for `( ... )`), and 3.2 calls ERR inside `! a | b`. Also the ERR trap names the command that ran inside a function, so declared functions had to be wrapped.
**Proposal:** the skill should say to run test-*.sh under a bash 5 when changing tap.sh (the macOS one is 3.2), and that bare setup lines running a program under test need `|| true` when their exit code is environment dependent.
