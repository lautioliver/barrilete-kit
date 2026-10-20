---
name: orchestrate
description: Distributes the available issues among subagents working in parallel (Haiku or Sonnet implement depending on risk, Opus reviews), each in its own worktree, and gathers everything in a single message with the PRs, the questions and what was escalated. It does not merge or publish without confirmation. Use with "/orchestrate", "orchestrate the available issues", "spread the queue among agents" or similar.
---

# Orchestrate

You are the main session: you distribute, coordinate and talk to the person. The subagents (`.claude/agents/`) implement and review following `docs/agents/subagent-contract.md`; they cannot launch other subagents or talk to the person, so everything goes through you.

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

Show the person a table (issue, title, model, `reason`) and wait for the "yes". They can drop issues or switch one's model to Sonnet; to Haiku only if `routing.py` allows it.

## 3. Launch

```bash
git -C <root> fetch -q origin        # only once, before launching: parallel fetches clash on .git/*.lock
.claude/skills/implement-issue/prepare.sh <n> --worktree   # one per issue, one at a time
```

`prepare.sh` validates, assigns, creates the worktree at `../<repo>-wt/<n>` and prints `Worktree: <path>`. If it fails for an issue, do not launch it and note it for the final message.

Launch the subagents in parallel, in a single message, with the Agent tool: `subagent_type` `implementer-light` (Haiku) or `implementer` (Sonnet). Without `isolation`: the worktree already exists. In the prompt: issue number, worktree path, base branch (`BASE=<base>`), `agent_sha` (`git log -1 --format=%H -- .claude/agents/<role>.md` in your checkout: it is the version that runs, even if the worktree has another), `skill_sha` (the same with `.claude/skills/implement-issue/SKILL.md`) and that it follows its definition, and that it must **not invoke `/code-review` through the Skill tool** (a forked skill moves your checkout): it does the bug pass by hand and declares `no code-review: <reason>`. To the reviewer: PR number, the orchestrator's checkout path, `agent_sha` of `reviewer.md` and `skill_sha` (`git log -1 --format=%H -- .claude/skills/review-pr/SKILL.md`), and the same ban on `/code-review` through the Skill tool (it declares `no code-review: <reason>` in `review:`). **Never more than 3 implementing at once**, counting the relaunched ones.

## 4. With each result

Each subagent returns the contract block. Read only that: never diffs or retros.

| `result` | What you do |
|---|---|
| `pr` (implementer) | Launch a `reviewer` with what step 3 says (PR, orchestrator's checkout, `agent_sha`, `skill_sha`). **Only one review per PR at a time.** |
| `escalate` | Relaunch `implementer` (Sonnet) in the **same worktree**, with the `reason`. It counts toward the maximum of 3. |
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
- **Not launched**: those `prepare.sh` rejected.

Offer to publish the reviews (`gh pr review <pr> --comment --body-file <file>`), all or some. Publish only what the person confirms. They do the merge.

## 6. Retro

The subagents' retros are already saved: you receive where they ended up (`retro:`, see the contract), but do not open them (only `/improve-skills` reads them). Save yours with `.claude/skills/improve-skills/retro.sh <file>` and this frontmatter: `skill: orchestrate`, `issue: <epic>` (if the issues belong to one) or `run: <YYYYMMDD-HHMM>`, `model: opus`, `role: orchestrator`, `area`, `paths`. In the body: issues launched with their model, escalated ones, extra rounds and how long each took. Write the file outside the repo.

## 7. Clean up

```bash
.claude/skills/orchestrate/cleanup.sh            # lists the worktrees of closed issues
.claude/skills/orchestrate/cleanup.sh --delete   # deletes them, if the person says yes
```

It also lists the `claude/<n>-…` branches whose PR was closed without merging, with the command to delete each one (at the end, after removing the worktrees: `git branch -D` fails while the branch is in one) (`git push origin --delete`; `gh pr close --delete-branch` fails from a detached HEAD). It does not delete them: offer it to the person, branch by branch, and warn them if any has unpushed commits. It does not delete a worktree with uncommitted changes, nor any at all if retros remain in `pending-retros/` (the run is not closed until they are saved): in that case, retry each retro with `retro.sh <file>` and run it again.
