# ADR-004 — `/orchestrate` launches each role as a `bk` agent or a subagent, per `roles.yml`

## Status

Accepted (2026-11-03). @lautioliver confirmed D1 to D5 as written in [a comment on #237](https://github.com/lautioliver/barrilete-kit/pull/237#issuecomment-6617865161), and in [a second comment](https://github.com/lautioliver/barrilete-kit/pull/237#issuecomment-6618761555) confirmed the D3 of that time, plus three more decisions (limit of `reviewer` and `implementer-light`, base branch, `main` without `bk`; see Consequences).

Origin: lautioliver/barrilete-kit#236. The issue records the decision as taken by the person in the chat on 2026-11-03. That record sits in the issue body, which an agent may have written, so it was not a person's approval yet (AGENTS.md, "Must ask first"); the confirmation above is. D4 and D5 are unchanged since the first confirmation. After it, D3 was reworded (no output block for a `bk` agent), and D1 and D2 got the limit (a) (`reviewer` and `implementer-light` always `sub`) and the `main` exception (c) (without `bk`); the second comment confirms all three. In [a later comment](https://github.com/lautioliver/barrilete-kit/pull/237#issuecomment-6622091388) the person approved rewriting D3 to align it with step 4 of the skill (#246): the PR is found with `gh pr list --search 'head:claude/<n>-'`, because `--head` only accepts the exact name.

## Context

- `/orchestrate` spreads the issues among **subagents** (Agent tool). It is cheap and fast, but a subagent cannot ask the person anything: every doubt arrives at the end as `question`, and if the orchestrator's session dies, all of them are lost.
- `bk` (the terminal workspace, https://github.com/lautioliver/bk-shell) launches **its own agents** in tmux windows (`bk run`, `bk review`, `bk fix`). Each one asks the person at the moment, survives the orchestrator and can be watched live.
- In the issues of epic #221 almost every one needed a decision in the middle. With subagents those decisions would have arrived at the end, or the agent would have taken them.
- `roles.yml` already says which provider and model runs each role. Its third column is the mode, and `bk mode <role>` returns it (`main`, `bk` or `sub`; no mode means `bk`). A project overrides it with `.barrilete/roles.yml`.

## Decision

1. **D1. The orchestrator plans and picks, per role, how to launch each task.** The models per role do not change:

   | role | model | mode |
   |---|---|---|
   | planner | opus | main (the main session) |
   | orchestrator | opus | main: plans and launches |
   | implementer | sonnet | **bk**: business-logic, ADR, CI; asks the person at the moment |
   | implementer-light | haiku | **sub**: docs and small tasks (always `sub`, see Consequences) |
   | reviewer | opus | **sub**: returns the draft; the orchestrator asks the person whether to publish it (always `sub`, see Consequences) |

2. **D2. Where the mode comes from.** `/orchestrate` runs `.claude/skills/orchestrate/mode.py <role>`:
   - the role's line in the project's `.barrilete/roles.yml` (`<role>: <provider>/<model> [mode]`; a line without mode is `bk`);
   - if the project's file does not have the role (or does not exist), `bk mode <role>`, which reads its own `roles.yml`;
   - **without `bk` installed**, every role is `sub`, as before, except a `main` written in the project's `roles.yml` (a person does that role), and the orchestrator says so in the plan and in the final message.

3. **D3. How the orchestrator follows a `bk` agent.** State with `bk ls`; the result from the PR (`gh pr list --search 'head:claude/<n>-'`, its CI; `--head` only takes the exact name), without the output block of docs/agents/subagent-contract.md (a `bk` agent does not return it). It does **not** open the agent's diffs or retros, as with a subagent.

4. **D4. The person answers everything from the orchestrator's chat.** When a `bk` agent asks (text, permission or questionnaire), the orchestrator shows the question and its options in its own chat, and the person answers with `! bk say <agent> "…"` (or `bk say <agent> <n>` to pick option `n` of a questionnaire). The orchestrator **never** sends an approval on its own: the answer comes from the person.

5. **D5. The cap of 3 implementing at once counts both modes together** (`bk` agents and subagents, relaunched ones included).

## Rejected alternatives

- **All roles as subagents (today).** Cheap, but the doubts arrive at the end and are lost if the session dies.
- **All roles as `bk` agents.** The reviewer and the light implementer only return a result: a window each adds nothing and costs the person attention.
- **The orchestrator answers the `bk` agents' questions.** An agent approving another agent is not an approval from a person (AGENTS.md).
- **Reading `bk mode` only.** `bk mode` already checks the project's `.barrilete/roles.yml` before its own file, so reading it would work. What `mode.py` adds is a strict reading (a role line that does not parse or an unknown mode exits 64 instead of falling back silently) and the `sub` fallback when `bk` is not installed, which `bk mode` cannot give.

## Consequences

- `/orchestrate` (en and es) gets a plan step that shows, per issue, role, model and mode before launching, and launches each with its mode (`bk run <n> --role <role>` or the Agent tool). `bk run` creates the worktree itself, so `prepare.sh --worktree` is only for `sub`.
- docs/agents/subagent-contract.md says that the contract does not apply to a `bk` agent: `bk run` starts a normal `/implement-issue` session, which has its own rules (retro, no merge) and asks the person in its window.
- `mode.py` copies the format of `roles.yml` that `bk mode` reads, so the project's file is parsed twice (by `mode.py` and, if the role is missing from it, by `bk mode`). `/orchestrate` only asks `mode.py`, so when the project's file has the role, `mode.py` decides; if the two parsers ever disagree, `mode.py` wins. If that format changes in `bk`, `mode.py` and its test (`test-mode.sh`) change with it.
- **Limit: `reviewer` and `implementer-light` are always `sub`, even if `roles.yml` says `bk`** (`mode.py` prints `sub`). `bk run` starts a plain `/implement-issue` session and `bk review` runs `/review-pr` in the orchestrator's own checkout, with `/code-review` mandatory and no result block back; neither loads `.claude/agents/<role>.md`, so nothing would enforce the stop on sensitive paths of the light implementer or return the reviewer's draft. `main` and `sub` are kept for them. Lifting the limit needs a change in `bk`.
- **A role is launched as `bk` only if the PR's base is the repo's default branch.** A `bk` agent gets no `BASE`, `agent_sha`, `skill_sha` or `retro_sh`, so with another base the orchestrator launches that issue as `sub` and says so in the plan. This refines D1 for those issues; the person accepted it in the second comment.
- Out of scope: `bk` itself, the contents of `roles.yml`, and routing (`routing.py` still picks Haiku or Sonnet for an implementer; the mode is what `roles.yml` says for the role it picked).

## Amendment 2026-11-04

By ADR-005 D7 (lautioliver/barrilete-kit#250). **D3 changes:** the orchestrator follows a `bk` agent by reading its task (`task.json`, with `bk tasks --json`: state, result and PR number), no longer with `bk ls` or by looking the PR up by branch. With a `bk` that has no tasks, the method of D3 still applies. It still does not open its diffs or its retros. **D4 does not change:** the person answers with `bk say`, and the task being `waiting` is what tells the orchestrator there is a question to show. The accepted text above is not rewritten.
