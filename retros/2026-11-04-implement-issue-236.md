---
skill: implement-issue
issue: 236
pr: 237
area: infra
paths: .claude/skills/orchestrate/, docs/decisions/kit/ADR-004-*, docs/agents/subagent-contract*.md
date: 2026-11-04
skill_sha: ed239b63fcdd2e0737a6324f2493fc6426cadc57
model: sonnet
role: session
---
**Deviations:** `/code-review` not run on this round (`no code-review: bug pass by hand` over `mode.py`, declared in the PR). The `--root` test and the `bk mode` timeout test have no red (declared in the PR). My first `gh pr view --comments --json` call failed (flags clash) and the bot token expired once mid-run (push worked, `gh` did not); a retry a minute later worked, nothing was bypassed.
**Decisions not covered:** whether an explicit `main` for `reviewer`/`implementer-light` stays `main` when the limit forces `bk` to `sub` (I kept `main`/`sub`, only `bk` becomes `sub`). Whether `mode.py` should validate the project's file when `bk` is not installed (it now does: a typo fails 64 even without `bk`).
**What the review found:** round 2 found that `bk run`/`bk review` do not load `.claude/agents/<role>.md`, so the reviewer and light-implementer rules (no `/code-review` fork, stop on sensitive paths, result block) cannot hold in `bk` mode. Fix was to force `sub`, not to patch the text. The ADR's Status linked to a comment that approved an older D3: re-confirmation on the PR was needed.
**Proposal:** `implement-issue` could say how to handle the red when a green commit fixes a behavior a mode-specific test already covers, and that `retro.sh` for a worktree session needs the base's copy (done via `git archive`). Also: write the PR body from a file in the scratchpad before running `gh pr view > file`, which leaves an empty file when `gh` fails.
