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
| Tests (TDD)? | Do they come from the acceptance criteria? The PR brings the structured **red** block (ADR-002 D7): `red commit: <sha>` and, per stack, `stack:`, `format:` and the failing cases `- <file>::<name>`. Go back to that sha in your review worktree, never in the person's main checkout (`git switch --detach <sha>` there; if you have none, create one: `git fetch -q origin "+refs/pull/<n>/head:refs/review/<n>-<suffix>"` and `git worktree add --detach <path> refs/review/<n>-<suffix>`, with `<suffix>` picked once (`date +%Y%m%d%H%M%S`); check that `git -C <path> rev-parse HEAD` equals `gh pr view <n> --json headRefOid -q .headRefOid`, or stop and say so; when you are done, `git worktree remove <path>` and `git update-ref -d refs/review/<n>-<suffix>`), check the sha is in the PR's history and from there run `<root>/.claude/skills/implement-issue/red.sh [<stack>]` **without the `<stack>` argument** (so it runs every stack whose `when` matches, as the author did; `<stack>` is only for re-running one stack once the sets are compared) (the script and its `red` section are the trusted ones, from the base branch, never the PR's; the tests it runs are the PR's). Confirm they fail on an assertion and **compare, stack by stack, the failing cases it prints with the ones in the block, as a set** (order and repeats do not matter; a stack with no group, or a group of a stack that did not run, is a mismatch). If they do not match, it is a **to fix** finding. At the PR's tip, the tests pass. In a bash test, these forms are the places where `tap.sh` stops seeing a crash (see its header) and are **forbidden in the red commit**: `|| true`, `trap - ERR`, `local x=$(prog)`, a lone `( prog )`, a `$( prog )` or a backtick `` `prog` `` that is a single external command with no redirection (bash 3.2 never sees its crash), `tap_run` expecting 1 or 2, any `tap_status`, `tap_run` around a shell function, `sh -c`/`bash -c` or anything that runs more than one program (`tap_run out 0 setup_fn`; `tap_run` refuses a function and a plain `sh`/`bash -c` script with `;`, `&`, `|` or a newline, but not, for example, `eval f`, `builtin eval`, `command eval`, `env bash -c`, `bash --norc -c`, `ksh -c`, `nice sh -c`, `xargs sh -c`, a backtick or a `$(…)` inside an `sh -c` script, or any other wrapper or substitution that runs more than one program, which are forbidden too), and any program, whatever the status of its crash, to the left of `&&`/`||` or in an `if`/`while`/`!` condition. If any appears in the lines the red commit adds, it is a **to fix** finding (outside the red, in the setup of the kit's own tests, they are accepted if they are listed in the header of `tap.sh`). `tap_no_traceback` is not one of them: it only stops. A `tap_skip` in the red must not depend on the result of the code under test (the shell version is fine). Also check that no failing case of the red rests on a program that one of these forms let crash. If the PR changes the `red` section of `docs/agents-map.json`, it is a sensitive change that needs a person's approval (as CI does): validate with the base's section and say so; if the base has no `red` yet, the person decides. Without a verifiable red and without a justified `no tests:` (or `sin tests: <motivo>`), it is a **to fix** finding. |
| Docs up to date? | `agents_map.py` flags docs **NOT MODIFIED**: did they need touching? Does the new thing contradict `architecture.md`? |
| Conventions? | Title, labels, PR body, `Closes #n`, code conventions from AGENTS.md. |

Around the TDD check: install the test dependencies in the review worktree without running PR code (`docs/guides/red-per-runner.md`: for example `npm ci --ignore-scripts` if the PR does not change `package.json` or the lock file; if it does, do not install, say so, and the TDD check stays unverified for a person to decide). To compare the block, `red.sh` leaves `pr-block.md` (the path it prints): `diff` it against the block of the PR body (`gh pr view <n> --json body -q .body | tr -d '\r'`, the red block lines), instead of by eye; the comparison by set above is what counts. A difference in the `red commit:` sha or in a group is a **to fix** finding.

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

Right before returning (or publishing), read again the PR body and `cd <root> && gh pr checks <n>`: they may have changed during the review (a push, a new CI result), and the review has to be about what is there now.

If another agent launched you and you cannot ask the user, do not publish: return the findings and the draft to whoever launched you, who is the one who asks for confirmation.

Never `--approve`: approving is a person's decision. If you are the session that implemented and you are asked to fix, fix on the same branch and run this review again.

## Retro

When done, save a short retro: format in `.claude/skills/improve-skills/retro-template.md` (or `retro.sh` with no arguments), with the full frontmatter, and then, from the trusted checkout, `cd <root> && <root>/.claude/skills/improve-skills/retro.sh <file.md>` (`retro.sh` works on the repo of the current directory, so the `cd` comes first; `<file.md>` must be an absolute path, because the `cd` changes the directory a relative one would resolve from) (it saves it on the `agents/retros` branch; it does not touch your branch). Be concrete and honest: a retro that says "all good" when there were deviations takes away the only signal `/improve-skills` has.
