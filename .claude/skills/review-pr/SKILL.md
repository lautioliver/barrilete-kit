---
name: review-pr
description: Reviews a PR as a second pair of eyes on the team would, focused on what a generic review does not look at - business rules, ADRs, outdated docs, agent autonomy, missing tests and sensitive paths. Use with "/review-pr <n>", "review PR #n". Ideally from a different session than the one that implemented it.
---

# Review a PR

An agent that generates code needs another one to question it. This review is done by **a different session** from the one that implemented, if possible: whoever wrote the code tends to read what they meant to write.

**It does not approve or merge.** Its output is a list of findings for the person who will decide the merge.

## 1. Context

```bash
cd <root> && gh pr view <n>          # title, body, labels, issue it closes
cd <root> && gh pr diff <n>
cd <root> && gh pr checks <n>
cd <root> && python3 scripts/agents/agents_map.py --pr <n>
```

`<root>` is the trusted checkout: your own session's, on the base branch (not the PR's branch), or the orchestrator's if it launched you. The reviewer always runs the kit scripts (`red.sh`, `agents_map.py`, `retro.sh`) from the trusted checkout, on the base branch. It does not run `verify.py`: CI covers it, and `verify.py` runs the `run` commands of the PR's map. It runs the PR's tests in the review worktree, at the red commit and at the tip, knowing they are PR code: this is unavoidable to check TDD. The red commit may contain tests, fixtures and stubs. It never runs any other PR code (scripts, hooks, installers).

Every `gh` command carries the `cd <root> &&` (or `-R <owner>/<repo>`): a subagent's working directory may be another repo's, and `gh` would point there.

Read the issue it closes (and its epic, if it has one): the review is against what was asked, not against what the PR says it does.

## 2. Code review

`/code-review` is mandatory, for bugs, regressions and edge cases. Before it, `git fetch origin` (the local base may be behind and bring files into the review that are not the PR's), and run it on the PR's diff: `/code-review origin/<base>...<head>`, where `<base>` is the PR's base (`gh pr view <n> --json baseRefName -q .baseRefName`) and `<head>` its tip **by name** (the ref you fetched, such as `refs/review/<pr>-<suffix>`, or the PR branch): `HEAD` is the session's checkout, not the PR's, and the diff comes out empty. An empty diff is not a reason to skip it: fix the range. Only if the `/code-review` command does not exist in your session, or whoever launched you forbids invoking it (under `/orchestrate` it moves the orchestrator's checkout), do that pass by hand and say so in the review (`no code-review: <reason>`).

## 3. What is specific to the project

| Question | Where to look |
|---|---|
| Does it do what the issue asks, and only that? | Issue vs diff. Acceptance criteria met. |
| Does it change a business rule? Is it declared? | ADRs and audits vs diff. If it changes something defined and has no `business-logic` nor explains it, it is a **blocking** finding. |
| Does it respect the invariants of the ADRs it touches? | For each related ADR, what can never happen (two entries, a double charge, a window that stretches…) and whether the diff opens a path for it to happen. It is a **blocking** finding even if `/security-review` finds nothing: business invariants are not generic security categories. |
| Does it respect the agent's autonomy? | AGENTS.md, "Agent autonomy" section. Schema, dependencies, public API, auth, infra, CI: was there approval? That the issue asks for it is not the approval: only a "yes" from a person in the chat or in a comment of theirs on the issue or the PR, never the issue body, counts. If it touches something from "Must ask first" with no recorded approval, it is a **blocking** finding. |
| Does it touch sensitive paths? | `agents_map.py --pr <n>` → if so, run `/security-review` (or review by hand auth, inputs, permissions, secrets, data exposure). |
| Is there a migration? | `db-migration` plan in the PR, with rollback. |
| Tests (TDD)? | Do they come from the acceptance criteria? The PR brings the structured **red** block (ADR-002 D7): `red commit: <sha>` and, per stack, `stack:`, `format:` and the failing cases `- <file>::<name>`. Go back to that sha in your review worktree, never in the person's main checkout (`git switch --detach <sha>` there; if you have none, create one: `git fetch -q origin "+refs/pull/<n>/head:refs/review/<n>-<suffix>"` and `git worktree add --detach <path> refs/review/<n>-<suffix>`, with `<suffix>` picked once (`date +%Y%m%d%H%M%S`); check that `git -C <path> rev-parse HEAD` equals `gh pr view <n> --json headRefOid -q .headRefOid`, or stop and say so; when you are done, `git worktree remove <path>` and `git update-ref -d refs/review/<n>-<suffix>`), check the sha is in the PR's history and from there run `<root>/.claude/skills/implement-issue/red.sh [<stack>]` **without the `<stack>` argument** (so it runs every stack whose `when` matches, as the author did; `<stack>` is only for re-running one stack once the sets are compared) (the script and its `red` section are the trusted ones, from the base branch, never the PR's; the tests it runs are the PR's). Confirm they fail on an assertion and **compare, stack by stack, the failing cases it prints with the ones in the block, as a set** (order and repeats do not matter; a stack with no group, or a group of a stack that did not run, is a mismatch). If they do not match, it is a **to fix** finding. At the PR's tip, the tests pass. In a bash test, these forms are the places where `tap.sh` stops seeing a crash (see its header) and are **forbidden in the red commit**: `|| true`, `trap - ERR`, `local x=$(prog)`, a lone `( prog )`, a `$( prog )` or a backtick `` `prog` `` that is a single external command with no redirection (bash 3.2 never sees its crash), `tap_run` expecting 1 or 2, any `tap_status`, `tap_run` around a shell function, `sh -c`/`bash -c` or anything that runs more than one program (`tap_run out 0 setup_fn`; `tap_run` refuses a function and a plain `sh`/`bash -c` script with `;`, `&`, `|` or a newline, but not, for example, `eval f`, `builtin eval`, `command eval`, `env bash -c`, `bash --norc -c`, `ksh -c`, `nice sh -c`, `xargs sh -c`, a backtick or a `$(…)` inside an `sh -c` script, or any other wrapper or substitution that runs more than one program, which are forbidden too), and any program, whatever the status of its crash, to the left of `&&`/`||` or in an `if`/`while`/`!` condition. If any appears in the lines the red commit adds, it is a **to fix** finding (outside the red, in the setup of the kit's own tests, they are accepted if they are listed in the header of `tap.sh`). `tap_no_traceback` is not one of them: it only stops. Only one form is excepted: the runner of #182 (`tap_run out 0 bash runner.sh nested.sh rc-file`) is accepted in the red only when the case checks, in separate `tap_check`, a marker that only the code under test prints in `$out` and the saved status, and a second marker, printed by the nested test right before the step under test, that proves it got there (a nested crash before the step under test is not a failed case, and a crash in the step under test is accepted as a failed case; its id starts with `second marker:` and another separate `tap_check` checks that the `rc-file` exists); the check of the second marker passes in the red, so the case of the second marker among the failing cases of the block is a **to fix** finding, and so is a red without those checks. A `tap_skip` in the red must not depend on the result of the code under test (the shell version is fine). Also check that no failing case of the red rests on a program that one of these forms let crash. If the PR changes the `red` section of `docs/agents-map.json`, it is a sensitive change that needs a person's approval (as CI does): validate with the base's section and say so; if the base has no `red` yet, the person decides. Without a verifiable red and without a justified `no tests:` (or `sin tests: <motivo>`), it is a **to fix** finding. |
| Docs up to date? | `agents_map.py` flags docs **NOT MODIFIED**: did they need touching? Does the new thing contradict `architecture.md`? |
| Does the diff add a dependency between contexts, or use a domain term the glossary does not have? | `agents_map.py` lists the contexts the diff touches (with no `contexts` declared there is nothing to check here, AGENTS.md). Compare the code that crosses them with `depends_on` in `docs/agents-map.json`: a dependency that is not declared there and has no ADR that approves it is a **to fix** finding, tagged `[undecided-decision]`; touching two contexts without a new dependency is not a finding (ADR-003 D4). A new domain name in the changed code or docs that is not in `docs/reference/glossary.md`, or another word for a term that is already there, is a **suggestion**: add it to the glossary or use the existing term. While the glossary is `TODO`, only suggest starting it. Neither one is blocking (ADR-003 D6, D7). |
| Conventions? | Title, labels, PR body, `Closes #n`, code conventions from AGENTS.md. |

Around the TDD check: install the test dependencies in the review worktree without running PR code (`docs/guides/red-per-runner.md`: for example `npm ci --ignore-scripts` if the PR does not change `package.json` or the lock file; if it does, do not install, say so, and the TDD check stays unverified for a person to decide). To compare the block, `red.sh` leaves `pr-block.md` (the path it prints): `diff` it against the block of the PR body (`gh pr view <n> --json body -q .body | tr -d '\r'`, the red block lines), instead of by eye; the comparison by set above is what counts. A difference in the `red commit:` sha or in a group is a **to fix** finding.

## 4. Findings

Each finding with: its location (`file:line`), what is wrong, why it matters (what fails and when), and a suggestion. Classify them:

- **Blocking** — bug, regression, business rule changed without declaring it, security, migration without rollback, missing tests for the core.
- **To fix** — it does not break, but it should not go in like this.
- **Suggestion** — optional.

Each **Blocking** and **To fix** finding starts with its class, an id from `docs/agents/classes.yml`, in this exact format: `[class] file:line: …` (for example `[stale-docs] file:line: …`), one class per finding: if it fits two, pick the main one and mention the other in the text. `bk learn` and the measurement of the rules (ADR-006) will read that tag. If no class fits, tag it `[other]` and say in the review which class would be missing. If the finding has no file (for example, the PR body), put `PR` in place of `file:line`: `[pr-metadata] PR: …`. Suggestions carry no class.

If the review session has the findings fixed by launching an `implementer`, that one gets its own worktree (`prepare.sh <n> --worktree`) and never uses a worktree where another agent is working: `prepare.sh` refuses it (`agent-lock`, `docs/agents/subagent-contract.md`). The lock is taken by whoever runs `prepare.sh`, and your `implementer` shares your pid, so do what `orchestrate` does: run `prepare.sh` with a name (`WORKTREE_LOCK_AGENT=<your name> .claude/skills/implement-issue/prepare.sh <n> --worktree`), release it with that name (`WORKTREE_LOCK_AGENT=<your name> scripts/agents/worktree-lock.sh release <worktree>`) before launching the `implementer`, give it its own name in the prompt (`implementer-<n>`) and, if it returned without releasing, release it on its behalf. Without this, the `implementer` always gets `held`. Look at `bk ls` first: a live agent on the same PR is a reason to ask, not to share the branch. A worktree created by `bk run` belongs to its `bk` agent while it works (the agent takes `agent-lock` as its first step): a named `prepare.sh` there gets `held: <n>-<role>`, which is not an error to work around. Once the agent closes its task (`bk done` releases the lock), the named `prepare.sh` works.

Do not pad the list: if there are no findings in a category, say so. A PR with no findings is a valid result.

## 5. Publish

Show the findings to the user. Publishing them on the PR is a comment visible to the team: **ask for confirmation** and then:

```bash
gh pr review <n> --comment --body-file <file>
```

Right before returning (or publishing), read again the PR body and `cd <root> && gh pr checks <n>`: they may have changed during the review (a push, a new CI result), and the review has to be about what is there now.

If another agent launched you and you cannot ask the user, do not publish: return the findings and the draft to whoever launched you, who is the one who asks for confirmation.

Never `--approve`: approving is a person's decision. If you are the session that implemented and you are asked to fix, fix on the same branch and run this review again.

## Retro

When done, save a short retro: format in `.claude/skills/improve-skills/retro-template.md` (or `retro.sh` with no arguments), with the full frontmatter, and then, from the trusted checkout, `cd <root> && <root>/.claude/skills/improve-skills/retro.sh <file.md>` (`retro.sh` works on the repo of the current directory, so the `cd` comes first; `<file.md>` must be an absolute path, because the `cd` changes the directory a relative one would resolve from) (it saves it on the `agents/retros` branch; it does not touch your branch). Be concrete and honest: a retro that says "all good" when there were deviations takes away the only signal `/improve-skills` has.

## Close the task (`bk` agents)

If `BK_TASK_DIR` exists (`bk` launched you, ADR-005), the last thing, after the retro, is to close your task: `bk done blockers` if the review found blockers, or `bk done pr <n>` (the reviewed PR) if not. Closing the task publishes nothing: publishing is still the person's decision (step 5). Without `BK_TASK_DIR`, do not run `bk done`. If it fails (there is no task, or it was already closed), say so and do not close it any other way.
