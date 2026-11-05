# ADR-006 — Rules store for agents (`barrilete-rules`)

## Status

Accepted (2026-11-05). @lautioliver approved it by merging lautioliver/barrilete-kit#257 on 2026-11-05, D1 to D12 as they are in d89240a. The open questions stay open: they are decided in the issue of the phase that needs them.

Origin: lautioliver/barrilete-kit#256 and a proposal from the person on 2026-11-04 ("store of general rules for agents").

Decided by @lautioliver in the chat:
- (2026-11-04) Rules are general, versionable and, when possible, verifiable with a check.
- (2026-11-05) The store **replaces** both of today's systems (D1). It lives in a separate public repo, `lautioliver/barrilete-rules` (D2). Deviations stay in a local jsonl with the ADR-005 `task_id` (D5). A rule's check runs inside `verify.py` (D8). The kit consumes the rules with a pinned version and `sync-rules` (D7).

The rest (the fields, the class list, where rules are injected, the measurement and the phases) are refinements an agent wrote and the person did not decide separately. They are approved by accepting this ADR or changed in the review of its PR.

## Context

Today there are two lesson systems that do not talk to each other:

- **Kit**: docs/agents/lessons.md. Only `/improve-skills` writes it, from the retros, through a PR and with at most 40 lines, and `implement-issue` reads it.
- **`bk learn`** (barrilete-workspace). It reads transcripts and reviews every ~2 min and stores deviations in an Obsidian vault. When a pattern repeats 3 times in 14 days, it proposes a lesson. The person accepts it and the rule goes to an `INDEX.md` imported from the person's global `CLAUDE.md`: it reaches every session of every project.

What was measured on 2026-11-05 with `bk learn effect`:

- **Text rules do not move deviations.** The two implementer rules accepted on 2026-11-01 stay the same over 44 review rounds: from 0.14 to 0.18 and from 0.14 to 0.16 findings of their class per round.
- **A regular expression guesses the class of each review finding.** Out of 138 findings, 68 (49%) fell into "other finding". Without a reliable class there is no way to connect deviations, rules and findings, to propose good rules or to measure.
- **Rules reach the wrong place.** An implementer rule takes up context in any chat. When the role runs as a subagent of the orchestrator (ADR-004), it gets no `SessionStart` of its own, so nothing injected by a hook reaches it.

## Decision

1. **D1. One rules system.** `barrilete-rules` replaces the kit's docs/agents/lessons.md and the `bk learn` lessons, including `INDEX.md` and its import in the global `CLAUDE.md`. When the transition (D11) ends:
   - `lessons.md` goes away;
   - `/improve-skills` and `bk learn` propose rules to the store instead of writing lessons;
   - the vault stays only for reading: deviations, patterns and measurement.

2. **D2. The `lautioliver/barrilete-rules` repo, public.** It holds three things:
   - `rules/<id>.md`: one rule per file;
   - `classes.yml`: the class list (D4);
   - `checks/<id>.*`: one check per file (D8).

   It never stores deviations (D5). A rule is accepted by merging the PR that adds it or moves it to `accepted`, so a person always reviews it, as `/improve-skills` does today.

3. **D3. A rule** is a `rules/<id>.md` file. At the top it has a frontmatter with the data and below, in the body, the rule in one line, the why and the evidence.

   | field | values | what for |
   |---|---|---|
   | `id` | slug (`pr-metadata`) | stable and without clashes between PRs in parallel; no sequential numbers |
   | `status` | `proposed` · `accepted` · `deprecated` | only `accepted` is injected (D9) |
   | `origin` | `observed` · `human` · `general` | `general` is accepted only with `classes` or `check` |
   | `applies_to` | roles (`implementer`, `reviewer`…) or `*` | where it is injected (D9) |
   | `scope` | `*` or repos (`barrilete-kit`) | a single-project rule, like today's "only in barrilete-kit" |
   | `classes` | ids from `classes.yml` | which findings it should lower; this is how it is measured (D10) |
   | `check` | id from `checks/` | optional; when present, the rule documents it |
   | `severity` | `block` · `fix` · `suggestion` | `block` requires `check`: a text rule cannot block |
   | `accepted` | ISO date | measured from then on |
   | `examples` | optional | `bad`/`good` cases |

4. **D4. Stable classes, and the reviewer tags them.** `classes.yml` lists the finding and deviation classes, with an id and a description: `pr-metadata`, `stale-docs`, `uncovered-case`, `test-cannot-fail`… The `review-pr` skill asks to tag each finding with its class (`[stale-docs] …`), and `bk learn` uses the tag. The regular expression stays only for old reviews, without a tag. Every other decision rests on this one: without a reliable class there is no way to map a deviation to its rule, to propose or to measure.

5. **D5. Deviations stay local, with `task_id`.** `bk learn` keeps storing them in a local jsonl, never in a repo, because there are many and they carry text from transcripts and from the person. Each deviation has:
   - when and of what: `ts`, `class`;
   - who: `model`, `harness`, `role`. Model and harness go separately: "sonnet" and "codex" are not the same kind of thing;
   - where: `project`, `pr`, and the ADR-005 `task_id` when the agent had `BK_TASK_DIR`;
   - `evidence` (path or URL) and `rule_id` if it is already mapped.

   The ADR-005 contract does not change: deviations are not task events.

6. **D6. Proposals are local until someone opens the PR.** `bk learn` builds the proposal (the rule in `proposed`, with evidence and class) locally. Accepting it means opening a PR to `barrilete-rules`. `/improve-skills` proposes the same way, from the retros. So nothing writes to a repo on its own, and the proposals generated every 2 minutes do not pollute the history.

7. **D7. The kit consumes a pinned version with `sync-rules`.**
   - `.barrilete/rules.lock` stores the repo and the SHA.
   - `scripts/agents/sync-rules` reads that version and does three things:
     - generates each role's `accepted` rules in `.claude/agents/<role>.md`, between markers;
     - generates the `applies_to: *` ones in `AGENTS.md`, which Codex reads;
     - copies the checks to `scripts/agents/checks/`.
   - Updating the rules is a PR to the kit that changes the lock, so what comes in is visible.
   - CI and `verify.py` run without network.
   - A project can have its own rules in `.barrilete/rules/`, with the same format, and `sync-rules` adds them to the store's.

8. **D8. Checks run inside `verify.py`.** A check has three things:
   - `id`;
   - the rule it answers to;
   - a `fail_message` that says what to do and when to escalate, so the agent does not end up in a loop.

   `verify.py` runs the checks of the rules that apply to the project. If one fails, the agent fixes it like any red verify: there is no new outcome in `bk done` (ADR-005 D4 does not change). A `ci` check also runs in the workflow.

9. **D9. Rules are injected in the agent definition, not by a hook.** A role's rules go in `.claude/agents/<role>.md` (D7), which loads both when the role runs as a `bk` agent and when it runs as a subagent. The `applies_to: *` ones go in `AGENTS.md`. The person's global `CLAUDE.md` stops importing lessons. When the rule has a `check`, the text says so ("validated by `verify.py`: <check>").

10. **D10. It is measured, and what does not work goes away.** `bk learn effect` measures, per rule, the findings of its `classes` per review round before and after `accepted`. A rule with no effect after a minimum number of rounds has three options, and the person picks:
    - it becomes a check;
    - it is rewritten more concretely;
    - it moves to `deprecated`.

    When a rule gets a check, the share of the check's runs that fail is measured too.

11. **D11. The transition goes in phases, and each phase is measured before moving on.**

    | phase | what changes | what stays the same |
    |---|---|---|
    | 0 | `classes.yml` and the reviewer's tag (D4) | everything else |
    | 1 | `barrilete-rules` is created; the vault lessons (accepted and retired) and docs/agents/lessons.md (as `origin: human`) are migrated | `INDEX.md` and `lessons.md` keep working |
    | 2 | `sync-rules` and injection per role (D7, D9); `lessons.md` and the global `CLAUDE.md` import are deleted | `bk learn` keeps detecting |
    | 3 | `bk learn` and `/improve-skills` propose to the store (D6) | — |
    | 4 | the first checks in `verify.py` (D8), starting with `pr-metadata` | — |

12. **D12. `rules_checked` in the self-review: a statement, not a proof.** The `self-review:` field of the output contract (docs/agents/subagent-contract.md) adds `rules_checked: [<id>…]`. If the agent declared a rule and the reviewer finds a finding of its class, that deviation is marked `declared`: it weighs more and moves the rule up toward becoming a check. What is declared never replaces a check.

## Open questions

- **How many rounds without effect before deciding on a rule (D10)?** The proposal is 20.
- **Does the vault keep a read-only view of the rules, or only the deviations?**
- **Does `bk learn` open a proposal's PR on its own, or does the person?** D6 says "someone"; the proposal is that the person opens it from `bk lessons`.

## Rejected alternatives

- **Adding the store as a third system.** The person rejected it: it makes worse the problem it is meant to solve.
- **Rules inside the kit (`agents/rules/`).** The person chose a separate repo. With the kit, accepting a rule was a PR to the same repo; with the separate repo, the lock and `sync-rules` are needed (D7).
- **Deviations as task events (ADR-005).** It tied everything to the task, but it required amending ADR-005, and deviations from chats without a task still needed another place.
- **A new `bk done` outcome when a check stops the PR.** It gave more information, but it amended ADR-005. `verify.py` is already the gate before the PR.
- **A git submodule, or always the latest version.** The submodule complicates worktrees and agents. Always pulling the latest lets a new rule break a project's CI without warning.
- **Injecting rules with a `SessionStart` hook.** It does not reach a role that runs as a subagent.

## Consequences

- **Gained:**
  - one place for rules, with history and review;
  - rules that reach only their role;
  - a reliable class to connect deviations, rules and findings;
  - rules that can become checks, and a measurement that decides what stays.
- **Costs:**
  - one more repo;
  - a PR to the kit each time the rules are updated;
  - one more line per finding in the review template;
  - maintaining `classes.yml`.
- **Risk:** the rule that today reaches all of the person's sessions, even outside the kit, is lost. The `applies_to: *` ones stay in `AGENTS.md`, but only in projects that have the kit.
- **Issues opened when it is accepted, one per D11 phase:**
  - **kit**: a provisional `classes.yml` and the tag in `review-pr`, in en and es (phase 0);
  - **barrilete-rules**: create the repo, the schema and the migration (phase 1);
  - **kit**: `rules.lock`, `sync-rules`, injection into `.claude/agents/` and `AGENTS.md`, and deleting `lessons.md` (phase 2). It touches CI and infrastructure, and this ADR is the approval;
  - **bk (workspace and bk-shell)**: `bk learn` with classes and `task_id`, proposals to the store and `bk learn effect` on `classes` (phases 0 and 3);
  - **kit**: checks in `verify.py` and `rules_checked` in the subagent contract (phase 4 and D12).
