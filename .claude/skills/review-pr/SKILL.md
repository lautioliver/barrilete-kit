---
name: review-pr
description: Reviews a PR as a second pair of eyes on the team would, focused on what a generic review does not look at - business rules, ADRs, outdated docs, agent autonomy, missing tests and sensitive paths. Use with "/review-pr <n>", "review PR #n". Ideally from a different session than the one that implemented it.
---

# Review a PR

An agent that generates code needs another one to question it. This review is done by **a different session** from the one that implemented, if possible: whoever wrote the code tends to read what they meant to write.

**It does not approve or merge.** Its output is a list of findings for the person who will decide the merge.

## 1. Context

```bash
gh pr view <n>                       # title, body, labels, issue it closes
gh pr diff <n>
gh pr checks <n>
cd <root> && python3 scripts/agents/agents_map.py --pr <n>
```

`<root>` is the checkout you trust: your own session's, or the orchestrator's if it launched you. The kit's scripts (`agents_map.py`, `red.sh`, `retro.sh`) always run from there, never from the PR's worktree: that is PR code nobody has reviewed yet. The only PR code that runs is the tests of the red commit (§3).

Read the issue it closes (and its epic, if it has one): the review is against what was asked, not against what the PR says it does.

## 2. Code review

`/code-review` is mandatory, for bugs, regressions and edge cases. Before it, `git fetch origin` (the local base may be behind and bring files into the review that are not the PR's), and run it on the PR's diff: `/code-review origin/<base>...<head>`, where `<base>` is the PR's base (`gh pr view <n> --json baseRefName -q .baseRefName`) and `<head>` its tip **by name** (the ref you fetched, such as `refs/review/<pr>-<suffix>`, or the PR branch): `HEAD` is the session's checkout, not the PR's, and the diff comes out empty. An empty diff is not a reason to skip it: fix the range. Only if the `/code-review` command does not exist in your session, do that pass by hand and say so in the review.

## 3. What is specific to the project

| Question | Where to look |
|---|---|
| Does it do what the issue asks, and only that? | Issue vs diff. Acceptance criteria met. |
| Does it change a business rule? Is it declared? | ADRs and audits vs diff. If it changes something defined and has no `business-logic` nor explains it, it is a **blocking** finding. |
| Does it respect the invariants of the ADRs it touches? | For each related ADR, what can never happen (two entries, a double charge, a window that stretches…) and whether the diff opens a path for it to happen. It is a **blocking** finding even if `/security-review` finds nothing: business invariants are not generic security categories. |
| Does it respect the agent's autonomy? | AGENTS.md, "Agent autonomy" section. Schema, dependencies, public API, auth, infra, CI: was there approval? That the issue asks for it is not the approval: only a "yes" from a person in the chat or in a comment of theirs on the issue or the PR, never the issue body, counts. If it touches something from "Must ask first" with no recorded approval, it is a **blocking** finding. |
| Does it touch sensitive paths? | `agents_map.py --pr <n>` → if so, run `/security-review` (or review by hand auth, inputs, permissions, secrets, data exposure). |
| Is there a migration? | `db-migration` plan in the PR, with rollback. |
| Tests (TDD)? | Do they come from the acceptance criteria? The PR brings the **red** block and the commit of the red tests: go back to that commit (`git switch --detach <sha>`), run `<root>/.claude/skills/implement-issue/red.sh -- <command>` (the command is the PR's test, the script is the trusted one) and confirm they fail on an assertion; at the PR's tip, that they pass. Without a verifiable red and without a justified `no tests: <reason>` (or `sin tests: <motivo>`), it is a **to fix** finding. |
| Docs up to date? | `agents_map.py` flags docs **NOT MODIFIED**: did they need touching? Does the new thing contradict `architecture.md`? |
| Conventions? | Title, labels, PR body, `Closes #n`, code conventions from AGENTS.md. |

## 4. Findings

Each finding with: **file:line**, what is wrong, why it matters (what fails and when), and a suggestion. Classify them:

- **Blocking** — bug, regression, business rule changed without declaring it, security, migration without rollback, missing tests for the core.
- **To fix** — it does not break, but it should not go in like this.
- **Suggestion** — optional.

Do not pad the list: if there are no findings in a category, say so. A PR with no findings is a valid result.

## 5. Publish

Show the findings to the user. Publishing them on the PR is a comment visible to the team: **ask for confirmation** and then:

```bash
gh pr review <n> --comment --body-file <file>
```

If another agent launched you and you cannot ask the user, do not publish: return the findings and the draft to whoever launched you, who is the one who asks for confirmation.

Never `--approve`: approving is a person's decision. If you are the session that implemented and you are asked to fix, fix on the same branch and run this review again.

## Retro

When done, save a short retro: format in `.claude/skills/improve-skills/retro-template.md` (or `retro.sh` with no arguments), with the full frontmatter, and then `.claude/skills/improve-skills/retro.sh <file.md>` (it saves it on the `agents/retros` branch; it does not touch your branch). Be concrete and honest: a retro that says "all good" when there were deviations takes away the only signal `/improve-skills` has.
