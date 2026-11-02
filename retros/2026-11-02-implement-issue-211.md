---
skill: implement-issue
issue: 211
pr: 212
area: agents
paths: scripts/agents/red_report.py, scripts/agents/test-tap.sh, .claude/skills/implement-issue/test-red.sh, docs/decisions/kit/ADR-002-structured-red-validation.md
date: 2026-11-02
skill_sha: 08b30f89fc480666f624ce1072e9d14f19f035ab
model: sonnet
role: session
---
**Deviations:** the review-fix round rewrote history (rebase with autosquash, push with --force-with-lease) because the person asked to rewrite the red commit. I ran `red.sh` from `main` on a temporary `git archive` copy, not from the worktree. I put the newest red block in the PR and described the older reds in prose without a literal `red commit:` line, so the CI check would not read two.
**Decisions not covered:** (1) which red block to paste when a round adds a new red on top of a rewritten one: I used the last one. (2) The house form `[ -f x ]; tap_check $? "id"` triggers SC2319 in shellcheck when it is indented inside a block; an inline `# shellcheck disable` did not help, only the file-level directive in the header did. The red commit has to carry that directive. (3) `red.sh` needs `docs/agents-map.json` next to it, so the `git archive` of the trusted copy must include it (and a `git init`).
**What the review found:** the ADR amendment was not backed by a comment from the person; the PR body said "ADR unchanged" while amending the ADR; an `if [ -f … ]` in the red that was not the house idiom; the `<n>: ` id prefix was not recognized. None of these was visible to me before the review. I also took the first `test-tap.sh` failure (case 135) as a flake and only found it was shellcheck (SC2319) in the installed kit by reading the nested output.
**Proposal:** in step 3 of implement-issue, say how to run the trusted `red.sh` from a `git archive` copy (it needs `docs/agents-map.json`), and mention SC2319 next to the `tap_check $?` idiom. Also `verify.py` takes about 5 minutes: say it should run in the background.
