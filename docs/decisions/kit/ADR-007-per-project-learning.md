# ADR-007 — Per-project learning

## Status

Proposed (2026-11-16). It is accepted by merging the PR of lautioliver/barrilete-kit#322. It replaces ADR-006 in D1 (the vault part), D5, D6 and D10; the rest of ADR-006 stays in force.

Origin: lautioliver/barrilete-kit#322, epic lautioliver/barrilete-kit#321 and the person's proposal of 2026-11-15 ("per-project learning").

Decided by @lautioliver in the chat (2026-11-16):
- A new ADR instead of amending ADR-006.
- The data lives in the project, where the project chooses: `local` (the default) or a data branch (D2).
- A minimum of 20 rounds per cell (rule × model × harness) before giving a verdict (D5).
- The shared benchmark stays on the horizon and is not built (see Horizon).
- Routing harnesses by area is a separate feature (lautioliver/barrilete-kit#326): here only the `area` field is added to the event.
- The event carries only metadata: never prompts, code, or text from transcripts or from people.

The rest (the field list, the `outcome` values, the `rules_ref` format and how UHP is taken) are refinements an agent wrote and the person did not decide separately. They are approved by accepting this ADR or changed in the review of its PR.

Amended in lautioliver/barrilete-kit#324 (2026-11-17), decided by @lautioliver: the D5 cell has no role (rule × model × harness, as above; approved in the chat of 2026-11-17, recorded in https://github.com/lautioliver/barrilete-kit/pull/338#issuecomment-6963224944), and D6 fixes the `rules_ref` format (comment of 2026-11-16 on #324).

Amended in lautioliver/barrilete-kit#348 (2026-11-18), decided by @lautioliver in the chat (recorded in https://github.com/lautioliver/barrilete-kit/issues/348#issuecomment-6968066532): D3 limits `evidence_ref` to a local path plus the GitHub URLs of the list in D3, instead of any URL without credentials or query.

## Context

ADR-006 unified the rules in `barrilete-rules`, but left the learning data outside the projects:

- **Deviations live in the person's Obsidian vault** (ADR-006 D1 and D5). What a project's agents learn stays on one machine: the team does not see it and another dev does not have it.
- **The cuts that matter are missing.** 53% of the 395 deviations have no model, and none has `harness` or `class`. `bk learn` only reads Claude Code transcripts.
- **The measurement looked at something else.** `effect.py` measured the vault lessons, not the `barrilete-rules` rules (fixed by lautioliver/barrilete-workspace#10). The `[class]` tag was not recognized when the finding starts with `#n: `: 18 of 48 findings fell into `other`.
- **Checks left no record.** `verify.py` ran the checks of `.barrilete/checks.json` without saving whether they passed or failed. lautioliver/barrilete-kit#323 adds the `check_run` event with a v0 schema, pending this ADR.
- **Proposals go straight to the general store** (ADR-006 D6). A rule that only makes sense in one project has to go through a public repo.
- **The measurement does not cut by model or harness** (ADR-006 D10). The same rule can work with one model and not with another, and the minimum number of rounds was left as an open question.

## Decision

1. **D1. Each project's store is the source; the vault is a personal view.** It replaces ADR-006 D1 in what it says about the vault. `barrilete-rules` is still the only rules system. The learning data (deviations, findings, check runs, task ends) is written to the project's store (D2). The vault becomes a view that `bk learn` can build from the stores for the person: nothing reads it as a source. The events already in the vault are not migrated: they are still read as a legacy source until phase 3 of the epic (lautioliver/barrilete-workspace#12).

2. **D2. The project chooses where its data lives.** `.barrilete/learning.json` says `{"store": "local"}` or `{"store": "branch"}`. Without the file, `local`.
   - **`local`**: `.barrilete/learning/events.jsonl` of the main checkout (also when the agent works in a worktree). The folder carries its own `.gitignore`, so it never gets into a commit. It does not leave the machine.
   - **`branch`**: the data branch `agents/learning`, like `agents/retros`: it is written without a PR and only with its script. The team shares the history, and the data has the repo's visibility: in a public repo it is public.

3. **D3. One event for every adapter.** It replaces ADR-006 D5. Each line of the store is an event with these fields:

   | field | values | what for |
   |---|---|---|
   | `v` | `1` | schema version; the `check_run` of #323 is `v: 0` |
   | `ts` | ISO 8601, UTC | when |
   | `project` | repo name | which project, if a view gathers several |
   | `task_id` | ADR-005 id (`244-implementer`) | links to the task, when there is `BK_TASK_DIR` |
   | `pr` | number | the PR the event comes from, when there is one |
   | `provider` | `anthropic` · `openai`… | compare providers |
   | `model` | `claude-sonnet-5-5`… | **required** |
   | `harness` | `claude-code` · `codex` · `copilot` · `cursor` · `pi` | **required**: the same model behaves differently depending on where it runs |
   | `area` | the issue's `area:` label | for routing by area (#326) |
   | `role` | `implementer` · `reviewer`… | which role the rule reaches |
   | `kind` | `deviation` · `finding` · `check_run` · `task_end` | what happened |
   | `class` | id from `classes.yml` | connects deviation, rule and finding (ADR-006 D4) |
   | `rule_id` | rule id | the mapped rule, if there is one |
   | `outcome` | depends on `kind` (below) | the result |
   | `evidence_ref` | local path or an allowed URL (below) | where the evidence is, never the evidence |
   | `rules_ref` | see D6 | which version of the rules the agent received |

   - **`evidence_ref`:** a local path, or only one of these URLs, all of `https://github.com/<owner>/<repo>/`: `pull/<n>` or `issues/<n>` with an optional `#issuecomment-<n>` or `#discussion_r<n>`; `blob/<sha>/<path>` with an optional `#L<n>` or `#L<n>-L<m>`; `commit/<sha>`. `<sha>` is hexadecimal. Any other URL is rejected (a webhook or a token travels in the others, and `push` publishes the store).
   - **Required:** `v`, `ts`, `project`, `kind`, `model` and `harness`. The rest go when they are known. The emitter does not guess: if it cannot know the model or the harness, it writes `unknown`, and the report counts them apart.
   - **`outcome`:** in `check_run`, `pass`, `fail` or `skipped` (the check could not verify), as in the v0 of #323. In `task_end`, the terminal states of ADR-005 D3: `completed`, `failed`, `incomplete` or `cancelled`. In `deviation` and `finding` it does not go.
   - **No text fields.** The schema has no free-text fields, and an event with a field that is not in the table is rejected (a test in lautioliver/barrilete-kit#324 proves it). Prompts, code, text from transcripts or from people, client names and secrets never get in: the event has to be auditable without seeing anything of the business.
   - The ADR-005 contract does not change: learning events are not task events. `task_end` is the fact that the task ended, copied to the store to measure; the task's `events.jsonl` is still the ADR-005 one.

4. **D4. Proposals go to the project first.** It replaces ADR-006 D6. `bk learn` and `/improve-skills` propose the rule in the project's `.barrilete/rules/`, as `proposed`, through a PR to the project: accepting it means merging it. A rule reaches `barrilete-rules` only if someone promotes it by hand, with a PR to that repo. Nothing writes to a repo on its own, and a project exposes nothing by having its own rules.

5. **D5. The rules the project applies are measured, per cell.** It replaces ADR-006 D10 and answers its open question about rounds.
   - The rules measured are the ones the project receives: those of the `.barrilete/rules.lock` SHA that apply to it (the same ones `sync-rules` filters) and those of `.barrilete/rules/`.
   - A cell is rule × model × harness. Per cell, the findings of the rule's `classes` per review round are measured before and after `accepted`, and the failure rate of its check if it has one.
   - **A minimum of 20 rounds per cell.** With fewer, the report says "small sample" and gives no verdict.
   - A rule with no effect and a large enough sample has the same three outcomes as in ADR-006, and the person picks: it becomes a check, it is rewritten more concretely, or it moves to `deprecated`.

6. **D6. Load canary: `rules_ref`.** Each agent event records which version of the rules it received: the `barrilete-rules` SHA of `rules.lock` and a short hash of the generated sections it read (`.claude/agents/<role>.md` and the `AGENTS.md` block). If an agent ran with old sections (`sync-rules` was not run again), it shows in the event, and the measurement attributes the result to the version the agent really had. The format, fixed in #324: `<first 12 of the rules.lock SHA>.<first 12 of the sha256 of the rules block of AGENTS.md and the one of .claude/agents/<role>.md>`. It goes only in the events of a `bk` agent (`BK_TASK_DIR`), and never without `rules.lock`.

7. **D7. Compatible with UHP, not dependent on it.** From the Unified Harness Protocol the vocabulary is taken, not the format:
   - the task states: `completed`, `failed`, `incomplete`, `cancelled` (already in ADR-005);
   - stable prefixed codes to translate a class or a rule: `barrilete_<id>` with `_` instead of `-` (`barrilete_pr_metadata`);
   - what is our own goes in the metadata.

   Its server and its stream format are not adopted: the harnesses in use do not speak UHP, and deviations come from hooks, `verify.py`, reviews and PRs. If some harness speaks UHP, translating its stream to this event is direct. It is revisited when that happens.

## What does not change

- From ADR-006: D2 (the `barrilete-rules` repo), D3 (the format of a rule), D4 (the classes and the reviewer's tag), D7 (`rules.lock` and `sync-rules`), D8 (checks in `verify.py`), D9 (injection in the agent definition), D11 (the phases of that transition) and D12 (`rules_checked`).
- All of ADR-005.

## Horizon (not built)

- **Phase 5 of the epic: shared benchmark, opt-in, counts only.** A project could export, if it wants, counts by class, model, provider, harness and role, the rate per round, the failure rate of each check and the ids of the general rules. Text, prompts, code, evidence, the project or repo name, its own rules, PRs, issues and people would never leave. It would answer "which model leaves the most stale docs?" without any project showing how it works. To be built it has to move to the roadmap and carry its own ADR.
- **Routing harnesses by area** (#326): this ADR only leaves the `area` field in the event.

This stays here and not in the project horizon (horizon.md): in the kit that file is the template `init` copies to every new project, and what it said about the kit would reach all of them.

## Open questions

- **Is `unknown` enough for `model` and `harness`, or does an emitter that does not know them not emit?** D3 proposes `unknown`. It is confirmed in #324, once it is seen how many events arrive like that.

## Rejected alternatives

- **Amending ADR-006.** The person chose a new ADR: the changes touch four decisions and the principle of where the data lives.
- **Only the data branch.** The team would share the history, but it clashes with privacy: in a public repo the data would be public. It stays as an option (D2).
- **Only local.** The most private, but each dev sees only their own. It is the default, not the only option.
- **Staying in the vault.** A project's data stays on one person's machine.
- **Adopting the UHP format.** It is young, single-vendor and changes often (5 versions in ~10 weeks); it saves no adapters.
- **Measuring per rule alone, without cutting by model or harness.** It mixes models that behave differently and hides a rule that works with one and not with another.
- **Building the benchmark now.** The bottleneck is measuring well inside the project (phase 0), not sharing.

## Consequences

- **Gained:**
  - the learning data lives with the repo and the project chooses who sees it;
  - one event with the same shape for every harness;
  - measuring by model, harness and role, with a minimum that avoids verdicts on a small sample;
  - knowing which version of the rules each agent had.
- **Costs:**
  - one adapter per harness (Claude Code, Codex, Copilot, Cursor, pi);
  - two store paths to maintain;
  - cutting per cell splits the rounds: many cells will say "small sample" for a while.
- **Risk:** text leaking into the store. It is stopped by the schema without text fields and the test that rejects extra fields.
- **Issues of epic #321** (already open):
  - **kit** #324: the v1 event and the store (D2, D3, D6); #325: the Codex, Copilot, Cursor and pi adapters (it touches hooks: ask first);
  - **barrilete-workspace** lautioliver/barrilete-workspace#11: the Claude Code adapter; #12: proposals to the project (D4) and the alert for a silent stream; #13: the per-cell report (D5); #14: an A/B with tasks from the git history.
