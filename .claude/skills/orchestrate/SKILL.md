---
name: orchestrate
description: Distributes the available issues among agents working in parallel (Haiku or Sonnet implement depending on risk, Opus reviews), each launched as a `bk` agent or a subagent according to roles.yml, each in its own worktree, and gathers everything in a single message with the PRs, the questions and what was escalated. It does not merge or publish without confirmation. Use with "/orchestrate", "orchestrate the available issues", "spread the queue among agents" or similar.
---

# Orchestrate

You are the main session: you distribute, coordinate and talk to the person. The agents (`.claude/agents/`) implement and review following `docs/agents/subagent-contract.md`. Each role is launched in its **mode** (`roles.yml`, kit/ADR-004): `sub` is a subagent (it cannot talk to the person or launch others: everything goes through you); `bk` is an agent in its own tmux window (`bk run`) that asks the person at the moment.

**Never** merge, approve or publish anything on a PR without an explicit "yes" from the person. `AGENTS.md` applies in full.

## 1. Prepare

- This session has to run on Opus. If it is not, ask the person for `/model opus` and wait.
- The base branch of the PRs (`<base>`) is the one from the branch rule in `AGENTS.md`; you pass it to each subagent as `BASE=<base>`.
- Note the run (`date +%Y%m%d-%H%M`, it is the `run` of your retro), and the path of your checkout, the **orchestrator's checkout** (`git rev-parse --show-toplevel`): every git command goes with `git -C <path>`. If `git status --porcelain .claude` shows changes, stop and ask for them to be committed: the `agent_sha` and `skill_sha` you pass come from commits, and they have to be the definitions that run. Do not switch branches or `pull` during the run.
- Run `.claude/skills/project-status/available.sh`. Only issues from **"Can be started now"** are launched: a blocked issue, one already assigned or with an open PR is never launched, even if the person names it (tell them so).

## 2. Propose and wait for confirmation

Pick up to **3** issues from "Can be started now", in the order they appear (priority). For each one run:

```bash
.claude/skills/orchestrate/routing.py <n>
```

It prints the model and the `reason`. It is the routing rule: **Haiku only if the issue is `type:docs` or `type:task`, without `business-logic` or `breaking-change` and without sensitive paths named in the text. Everything else, Sonnet.** If in the self-review `agents_map.py` flags sensitive paths, Haiku stops and returns `escalate`, and you relaunch it with Sonnet in the same worktree. `routing.py` errs on purpose toward Sonnet: a word like "infra" or "middleware" in prose already counts as a sensitive path. Do not change the rule by eye: if a case does not fit, propose the change to `routing.py` in an issue.

Then, per role (`implementer` or `implementer-light` for the model above; `reviewer` later), the mode: `.claude/skills/orchestrate/mode.py <role> --root <root>` prints `main`, `bk` or `sub` (the project's `.barrilete/roles.yml`, then `bk mode`). `reviewer` and `implementer-light` never come out as `bk` (`bk run` starts a plain `/implement-issue` session, not their agent definition): a `bk` in `roles.yml` prints `sub`; say it in the plan. **Without `bk` installed it prints `sub` for every role, except a `main` written in the project's `roles.yml`, and warns on stderr**: launch everything as subagents, as before, and say it in the plan and in the final message.

`main` is not launched (it is you or the person's own session). If `mode.py` exits 64 (a typo in `roles.yml`, `bk` failing), do not guess a mode: tell the person and wait.

Show the person the **plan**: a table (issue, title, role, model, mode, `reason`), and wait for the "yes". They can drop issues or switch one's model to Sonnet; to Haiku only if `routing.py` allows it.

## 3. Launch

```bash
git -C <root> fetch -q origin        # only once, before launching: parallel fetches clash on .git/*.lock
.claude/skills/implement-issue/prepare.sh <n> --worktree   # one per issue whose mode is `sub`, one at a time
```

`prepare.sh` is only for the issues whose mode is `sub` (a `bk` agent does it itself and a `main` issue is not launched: it would stay assigned with nobody on it). It validates, assigns, creates the worktree at `../<repo>-wt/<n>` and prints `Worktree: <path>`. If it fails for an issue, do not launch it and note it for the final message.

Per the plan's mode. A `bk` agent: `bk run <n> --role <role>` (it creates the worktree and the window itself: do not run `prepare.sh` for it), one at a time, and tell the person the window (`i<n>`). A `bk` agent is a normal standalone session: it gets none of `BASE`, `agent_sha`, `skill_sha` or `retro_sh` (it takes the base from the default branch and its `retro.sh` from `origin/<base>`). So **launch an issue as `bk` only if its PR base is the repo's default branch**; if not, launch it as `sub` and say so in the plan. A `main` implementer or a `bk run` that fails is not launched: note it for the final message. A `sub` agent: the rest of this step.

Launch the `sub` agents in parallel, in a single message, with the Agent tool: `subagent_type` `implementer-light` (Haiku) or `implementer` (Sonnet). In pi, with the `subagent` tool of `barrilete-pi` (`packages/pi/` of the template): the same roles in `agent`, and several at once in `tasks`. Without `isolation`: the worktree already exists. In the prompt: issue number, worktree path, base branch (`BASE=<base>`), `agent_sha` (`git log -1 --format=%H -- .claude/agents/<role>.md` in your checkout: it is the version that runs, even if the worktree has another), `skill_sha` (the same with `.claude/skills/implement-issue/SKILL.md`), `retro_sh` (the absolute path of `.claude/skills/improve-skills/retro.sh` in your checkout, already merged on the base branch: the implementer saves its retro with it, never with its worktree's, which is the PR's unreviewed code) and that it follows its definition, and that it must **not invoke `/code-review` through the Skill tool** (a forked skill moves your checkout): it does the bug pass by hand and declares `no code-review: <reason>`. To the reviewer: PR number, the orchestrator's checkout path, `agent_sha` of `reviewer.md` and `skill_sha` (`git log -1 --format=%H -- .claude/skills/review-pr/SKILL.md`), and the same ban on `/code-review` through the Skill tool (it declares `no code-review: <reason>` in `review:`). **Never more than 3 implementing at once**, counting both modes and the relaunched ones.

## 4. With each result

Each `sub` agent returns the contract block. A `bk` agent does not return anything to you: follow it with `bk ls` and read its result from the PR: its branch is the one the agent created, so take its exact name with `git -C <worktree> branch --show-current` (or find the PR with `gh pr list --search 'head:claude/<n>-' --state open --json number,headRefName`: `--head` takes the exact name, not a prefix) and then `gh pr checks` (no contract block). When `bk ls` shows a `bk` agent finished: with an open PR, treat it as `pr` (implementer) (launch the `reviewer`); without one, look at the issue for its question and note it as `question`; if there is no question either (a crash, a closed window), note it as `dropped`. Read only that: never diffs or retros.

A `bk` agent counts toward the 3 until `bk ls` shows it finished (not only until its PR is open: it keeps working on CI, the retro and questions).

**When a `bk` agent asks** (text, permission or questionnaire; `bk ls` shows it waiting), show the question and its options in your chat. The person answers with `! bk say <agent> "…"` (or `bk say <agent> <n>` for option `n` of a questionnaire). **You never send an approval yourself.**

| `result` | What you do |
|---|---|
| `pr` (implementer) | Launch a `reviewer` (if its mode is `sub`; `main` → "Not launched") with what step 3 says (PR, orchestrator's checkout, `agent_sha`, `skill_sha`). **Only one review per PR at a time.** |
| `escalate` | Relaunch `implementer` (Sonnet), with the `reason` (in `sub`, in the prompt), **in the mode `mode.py` gives for `implementer`**: `sub` → Agent in the **same worktree**; `main` → not relaunched: note it under "Not launched"; `bk` → `bk run <n> --role implementer`, which runs `prepare.sh` again and resumes the issue's branch (it is already assigned to the same person). `bk run` cannot take the `reason`: comment it on the issue before `bk run` (`implement-issue` reads the comments). Only if the PR's base is the repo's default branch; otherwise relaunch as `sub` in the same worktree, as in step 3. If `bk run` fails because the branch is still in the worktree of the first launch, do not force it: note it for the final message and tell the person. It counts toward the maximum of 3. |
| `question` / `dropped` | Note it for the final message. It is already commented on the issue. An issue that asks to touch CI, infra or anything else under "ask first" ends in `question` even if the request is in the issue: do not relaunch it saying it is approved unless the person told you so. The same goes for a relaunch: if Sonnet, relaunched after an `escalate`, returns `question` (for example, the issue touches CI and that requires asking for any model), there is no other relaunch. |
| `pr` (reviewer) | Note it with its `review:` for the final message. |
| `blockers` (reviewer) | You decide, with the criteria below. |

### Review blockers

At most **one extra round** per PR. Pick one and explain it in the final message:

1. **Another round with the same implementer** (relaunched in its worktree, with the blockers): if they are concrete and within the issue's scope (an edge case, a missing test, a doc).
2. **Relaunch with `implementer` (Sonnet)**: if Haiku did it and the blocker shows the issue was not for it (business logic, sensitive path, design).
3. **Hand it to the person**: if the blocker is a decision (contradicts an ADR, changes a rule, the issue is ambiguous), or if there was already an extra round.

After the extra round, the PR goes back to the reviewer. If it comes back with blockers, it goes to the person: there is no second round.

## 5. Final message

Only one, when they have all finished:

- **PRs**: link, model that did it, CI status (`gh pr checks <pr>`), the implementer's `self-review` (if `/code-review` did not run, highlight which PRs had none: under `/orchestrate` that is expected, and the person decides whether to run it themselves), the reviewer's verdict and findings in one line each.
- **Pending questions**: all together, with their issue, to answer in one go.
- **Escalated and relaunched**: which issue, from which model to which and why.
- **Decisions on blockers**: what you chose and why.
- **Not launched**: those `prepare.sh` rejected, an `implementer` whose mode is `main` (nobody is working on it) and a `bk run` that failed, and a `reviewer` whose mode is `main` (the PR has no review: say so).

Offer to publish the reviews (`gh pr review <pr> --comment --body-file <file>`), all or some. Publish only what the person confirms. They do the merge.

## 6. Retro

The subagents' retros are already saved: you receive where they ended up (`retro:`, see the contract), but do not open them (only `/improve-skills` reads them). Save yours with `.claude/skills/improve-skills/retro.sh <file>` and this frontmatter: `skill: orchestrate`, `issue: <epic>` (if the issues belong to one) or `run: <YYYYMMDD-HHMM>`, `model: opus`, `role: orchestrator`, `area`, `paths`. In the body: issues launched with their model, escalated ones, extra rounds and how long each took. Write the file outside the repo.

## 7. Clean up

```bash
.claude/skills/orchestrate/cleanup.sh            # lists the worktrees of closed issues
.claude/skills/orchestrate/cleanup.sh --delete   # deletes them, if the person says yes
```

It also lists the `claude/<n>-…` branches whose PR was closed without merging, with the command to delete each one (at the end, after removing the worktrees: `git branch -D` fails while the branch is in one) (`git push origin --delete`; `gh pr close --delete-branch` fails from a detached HEAD). It does not delete them: offer it to the person, branch by branch, and warn them if any has unpushed commits. It does not delete a worktree with uncommitted changes, nor any at all if retros remain in `pending-retros/` (the run is not closed until they are saved): in that case, retry each retro with `retro.sh <file>` and run it again.
