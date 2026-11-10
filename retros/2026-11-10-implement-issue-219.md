---
skill: implement-issue
issue: 219
pr: 304
area: agents
paths: scripts/grow.py, scripts/install.py, scripts/update.py, scripts/agents/check-docs.py, scripts/test-update.sh, scripts/test-install.sh, .claude/skills/implement-issue/SKILL.md
skill_sha: 454c976bef5dbcd1ca092fe5d8e8eb7c34533ce5
date: 2026-11-10
model: sonnet
role: implementer
agent_sha: de5334804ffd6aa0bb41e1a02c1fcbcd264a44b0
---
**Deviations:** I amended my own unpushed red commit twice (a check-docs case that exits 1 is a crash in a red, so it goes through a python wrapper that prints the status; the fixture needed its own map) and re-ran red.sh each time. In the green commit I touched one test line (an unassigned variable for shellcheck). The second merge of main (#312) conflicted again in CHANGELOG and the SKILL; resolved keeping both sides, no rebase.
**Decisions not covered:** how to assert in a red that a tool which exits 1 on findings (check-docs.py) runs clean after the change: `tap_run ... 0` bails on status 1 even in the red, and `tap_run` expecting 1 is forbidden; I used a one-file python wrapper that always exits 0 and prints the real status on the first line. The skill could say so. Also: a case that checks the grow-then-update path needs `.agent-kit/pending` removed and the version lowered, otherwise update stops for an unrelated reason.
**What the review found:** `/code-review` gave 8 findings, none fixed: false or out of scope (`git mv` on untracked files is already refused by the clean-tree check, enlaza reading like check-docs, `contexts: null`, braces in globs, three copies of the same helpers). The published review had 3 real blockers/gaps the first round missed: grow registered the map after writing the contexts (update would erase them), tests that pass with the code under test disabled, and texts that promised a warning that does not exist in installed repos.
**Proposal:** a short line in step 3 of implement-issue about asserting the status of a tool that exits 1 on findings (wrapper that prints the status), and a reminder that mutation checks of new cases need a git repo copy of the tree (the tests build the template with git ls-files).
