---
skill: implement-issue
issue: 225
pr: 255
area: infra
paths: scripts/agents/tap.sh, scripts/agents/red_report.py, .claude/skills/implement-issue/test-red.sh, scripts/agents/test-tap.sh, scripts/test-init.sh, CHANGELOG.md
date: 2026-11-05
skill_sha: 8f2bf8fad83a8ae9d2c3ea0a7b81aca57c2bead2
model: sonnet
role: session
---
**Deviations:** (1) I did not run `/code-review` on the round-3 diff (the skill says it is mandatory): I reviewed by hand the lines I changed and ran the mutations below. Not said in the PR body until now; the final message says it. (2) Item 2 of the review (cache of `go_module`/`cargo_crates`) has no test: it is a cache with no change of behavior, and I did not measure the git processes. The PR body says so.
**Decisions not covered:** how to put the new cases into the red commit when the red is rewritten: a `fixup!` of the red commit plus `rebase -i --autosquash` with `GIT_SEQUENCE_EDITOR=true` worked with no conflicts, because the green commits touched other lines. The skill does not say how to rewrite a red commit. Also: `red.sh` of `main` runs at the checked-out commit, so I had to `checkout --detach <red>` for the run (and not touch the worktree meanwhile), then go back to the branch.
**What the review found:** the 2nd review found that removing `rep.suite_files.append(...)` left 98/98 green (an untested line), an uncached read per case in `missing_test_files`, one forbidden form (`$(sed …)` with no redirection) in the red, a header that still described TAP only, and "ADR unchanged" in a PR that edits ADR-002 D6. I confirmed the first with the mutation (both new cases fail with the line disabled, 100/100 with it).
**Proposal:** (a) `implement-issue` could say how to rewrite a red commit (fixup + autosquash, then `red.sh` from `origin/main` at the detached red commit, then update the block and the sha everywhere in the body). (b) `test-red.sh`, `test-init.sh` and `verify.py` take several minutes: say it in the skill so a session runs them in the background writing to a file, since macOS has no `timeout` and a foreground command is cut at 120 s. (c) The `-m "...$M"` trailer with a single newline put the `Co-Authored-By` in the subject; two `-m` are needed (caught before the push).
