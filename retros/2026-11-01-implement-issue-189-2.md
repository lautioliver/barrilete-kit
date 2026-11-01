---
skill: implement-issue
issue: 189
pr: 209
area: agents
paths: scripts/agents/tap.sh, scripts/agents/test-i18n.sh, scripts/agents/test-tap.sh, .claude/skills/implement-issue, .claude/skills/review-pr
date: 2026-11-01
skill_sha: eb2fcbd705ca6ae764dc660eca87f8c1f8665b06
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** none from the skill. This was a correction round on an existing PR (review 5729234537), so I rewrote the red commit and pushed with `--force-with-lease` against the known tip. I used `/tmp` once for a scratch output file instead of the scratchpad.
**Decisions not covered:** the skill does not say how to rewrite a red commit when green commits sit on top. `cherry-pick -X theirs` silently dropped the new red tests, because the conflict resolution kept the old version of the test files. I caught it with a `grep -c` and rebuilt the history by checking out only the non-test files of each green commit. A second slip: unquoted `$files` in zsh is not word-split, so the first rebuild failed.
**What the review found:** the red commit had `grep && grep` (a forbidden form), and the exception did not tell a nested crash from an expected failure. The person chose to add a second marker. `red.sh` also rejected my first red: a case id containing the words `tap_check separados` matched the check that ids are literal (`tap_check [^ ]+ "…$`). I renamed the id.
**Proposal:** in implement-issue, add a line on rewriting a red commit: rebuild the green commits by checking out their non-test files (never `-X theirs`), then diff the tree against the old tip, and keep test case ids free of the text `tap_check <word>`.
