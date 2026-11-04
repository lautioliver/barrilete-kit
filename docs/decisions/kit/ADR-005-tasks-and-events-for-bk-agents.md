# ADR-005 — Tasks and events for `bk` agents

## Status

Accepted (2026-11-04). @lautioliver approved it in the chat on 2026-11-04, D1 to D9 as they are in 0e1a7ca, with no changes.

Origin: lautioliver/barrilete-kit#244. Decided by @lautioliver in the chat (2026-11-04): the contract lives in the kit and the implementation in `bk` (D1), the agent declares the close with `bk done` (D4), the handoff to review is proposed and does not start on its own (D6), and the guardrails plugin is left out (see Alternatives). Decided by @lautioliver in the chat, on the same date, on the draft's open questions: `bk say` to a busy task is queued (D8), PostToolUse records only git and gh (D5), tasks are not deleted on their own and their location is known (D9), and Codex stays an open question. The rest (ids, fields, intermediate states, event types, the relationship with ADR-004) are refinements an agent wrote and the person did not decide separately: they are approved when this ADR is accepted, or changed in the review of its PR.

## Context

- A `bk` agent is a tmux window. `bk` knows what it is doing by capturing its screen (`bk peek`) or reading its transcripts; `/orchestrate` follows its state with `bk ls` and its result from the PR (ADR-004, D3), and the person answers it by typing into its window (`bk say`, ADR-004 D4).
- So the state is guessed: an agent waiting for the person and one that is working look the same from outside. Repeating `bk run` on the same issue launches a second agent in the same worktree. An agent that died leaves no reason behind, and the reason for a block is prose.
- The [Unified Harness Protocol](https://github.com/HarnessRouter/harnessrouter/tree/main/protocol) (UHP) solved the same problem for driving harnesses over HTTP: the task is the unit of work, the lifecycle ends in a single terminal state, events are facts and not screens, errors have a code, and a session runs one task at a time. From UHP we take the model, not the transport.
- The project's hooks already run in every Claude Code (`.claude/settings.json`) and Codex (`.codex/hooks.json`) session, and a PreToolUse hook blocks even with `--dangerously-skip-permissions` (tested on 2026-11-04 in #244). They are the place to emit events without depending on the screen.
- docs/agents/subagent-contract.md already defines a vocabulary of results (`pr`, `question`, `escalate`, `dropped`, `blockers`).

## Decision

1. **D1. The contract lives in the kit and the orchestrator implements it.** This ADR defines the files and their format, and the kit ships the hooks that write events. `bk` (or another orchestrator) creates the tasks, reads them and orchestrates. The orchestrator passes the agent its task folder in `BK_TASK_DIR`. **Without `BK_TASK_DIR`, the hooks write nothing and exit 0**, so a project without `bk` works as it does today.

2. **D2. One task per agent, with a stable id.** The id is `<issue>-<role>`, for example `244-implementer`, or `pr<n>-<role>` when the task comes from a PR (`pr241-reviewer`). The task folder holds `task.json` (the state, the source of truth) and `events.jsonl` (the facts). **Launching a task whose id exists and is not in a terminal state does not launch another agent**: the orchestrator returns the task that already exists. A worktree has a single active task at a time.

3. **D3. States.**

   | state | terminal | means |
   |---|---|---|
   | `pending` | no | created; waits for the person to approve it before it starts (D6) |
   | `in_progress` | no | the agent is working |
   | `waiting` | no | the agent ended its turn and waits for the person (question, permission, questionnaire) |
   | `completed` | yes | the agent declared a result (D4) |
   | `failed` | yes | the agent declared it cannot continue (D4) |
   | `incomplete` | yes | the agent ended without declaring the close; usually worth resuming |
   | `cancelled` | yes | the person stopped it (`bk stop`) |

   A terminal state never changes. `incomplete` is not `failed`: the first is usually worth resuming and the second is not. `cancelled` is not `failed` either: the person asked for the stop, there was no error. Whatever the task produced before it ended is kept.

4. **D4. The agent declares the close with `bk done`, using the subagent contract's vocabulary.** `bk done pr <n>` and `bk done blockers` close as `completed`. `bk done dropped "<reason>"` and `bk done escalate "<reason>"` close as `failed`. `question` closes nothing: a `bk` agent asks in its window, and that is `waiting`. **The Stop hook does not close the task**: in an interactive session it fires at the end of every turn, so it only moves the task to `waiting`. If the agent's process ends without `bk done`, the orchestrator closes the task as `incomplete`.

5. **D5. Events: one fact per line.** `events.jsonl` has one JSON line per event: `{"seq": n, "ts": "<ISO 8601>", "type": "<type>", …}`. `seq` starts at 1 and grows with no gaps. The first event is `task.created`, and the last is the only terminal event, which copies the final `task.json`. Initial types: `task.created`, `task.started`, `turn.waiting`, `commit` (`sha`), `pr.opened` (`pr`), and `task.completed`, `task.failed`, `task.incomplete`, `task.cancelled`. **The PostToolUse hook records only `git` and `gh` commands**: the rest produce no events. The registration filters in `sh` before starting Python, so the other Bash calls do not pay its cost. **An event records only metadata, never content**: no arguments, no tool output, no model text. `task.json` is the source of truth, and `events.jsonl` is for following the task live and understanding afterwards what happened.

6. **D6. The handoff is proposed and the person approves it.** When a task closes with `pr <n>`, the orchestrator creates `pr<n>-reviewer` as `pending` and notifies. The task starts only when the person approves it. The orchestrator never approves on its own, as in ADR-004 D4.

7. **D7. It changes ADR-004 D3, not D4.** The orchestrator follows a `bk` agent by reading its `task.json`: state, result and PR number. It no longer uses `bk ls` or looks the PR up by branch. It still does not open its diffs or its retros. D4 does not change: the person answers with `bk say`, and `waiting` is what tells the orchestrator there is a question to show. When this ADR is accepted, ADR-004 gets an `## Amendment` section pointing to this D7.

8. **D8. `bk say` to a busy task is queued.** If the task is `in_progress`, the orchestrator keeps the message and types it into the window when the task moves to `waiting`. `bk say --now` types it right away, for example to stop the agent. In `waiting` the message is typed at once, as today.

9. **D9. Tasks are not deleted on their own, and their location is known.** Finished tasks and their events stay until the person deletes them (`bk tasks prune`). So that it is always known where they are, the default folder is `${XDG_STATE_HOME:-~/.local/state}/bk/tasks/<project>/<id>/`, `task.json` stores its own path in `dir`, and `bk tasks` lists the tasks with their state and folder.

## Open questions

This question is not decided and is left for the implementation issue:

- **Codex**: its `hooks.json` accepts `PostToolUse` and `Stop` (the person's Orca config uses them), but it is not tested that they fire the same way as in Claude Code. It is tested when the person installs `codex`; until then, the contract applies to Claude Code and Codex meets it only if the test passes.

## Rejected alternatives

- **Keep reading screens and transcripts.** It is the problem that motivates this ADR.
- **Adopt all of UHP (HarnessRouter).** It needs a server and an API key, and it does not accept a Claude subscription. It also redirects `HOME`, so the agent loses `~/.claude` (the lessons) and the repo's hooks, unless the repo is in its working folder. What helps is the model. Because of D1, another orchestrator, including a UHP one, can implement this contract later.
- **Have `bk` infer the close** (Stop hook plus the open PR): it keeps guessing. The person's decision.
- **Automatic handoff to the reviewer**: it spends tokens the person does not see and chains agents without a pause. The person's decision.
- **Agents talking to each other directly** (A2A style): everything goes through the orchestrator and the person, as in ADR-004.
- **Move the guardrails into a Claude Code plugin now**: it was tested and works (#244), but today it is only needed with HarnessRouter and it does not cover Codex. Postponed.

## Consequences

- Gained: a reliable state, no two agents on the same issue, closes with a machine-readable reason, explicit handoffs, and a contract that survives a change of orchestrator (herdr, UHP).
- Costs: a `sh` filter on every Bash call (D5), one more step at the end of `/implement-issue`, and a task folder that grows until the person cleans it (D9).
- Issues opened when it is accepted:
  - **bk-shell**: tasks in `bk run`, `bk review` and `bk fix` (D2, idempotency), `bk done` (D4), `incomplete` when the process ends, `pending` with approval (D6), the `bk say` queue and `--now` (D8), `bk tasks` and `bk tasks prune` (D9), and `bk ls`, the rail and the bar reading `task.json`.
  - **kit**: a new hook in `scripts/agents/` that emits the events, registered in `.claude/settings.json` and `.codex/hooks.json`. Touching that registration is touching CI and infrastructure, and this ADR is the approval.
  - **kit**: `/implement-issue` and `/review-pr` (en and es) end with `bk done` when `BK_TASK_DIR` exists.
  - **kit**: the ADR-004 amendment (D7) and a note in docs/agents/subagent-contract.md.
