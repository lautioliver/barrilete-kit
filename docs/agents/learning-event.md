# Learning event (v1)

What a project records so that `bk learn` can measure whether its rules work. The decisions are in [ADR-007](../decisions/kit/ADR-007-per-project-learning.md); this page is how the kit carries them out. The code is `scripts/agents/learning.py`.

## Where it goes

`.barrilete/learning.json` of the main checkout chooses the store (ADR-007 D2), also from a worktree: an old copy in a worktree does not open a second store. `init`, `install` and `update` bring it with `local`:

```json
{"store": "local"}
```

| store | where | leaves the machine |
|---|---|---|
| `local` (also without the file) | `.barrilete/learning/events.jsonl` of the main checkout, also from a worktree. The folder carries its own `.gitignore` and the root `.gitignore` ignores it too. | no |
| `branch` | the data branch `agents/learning`: each write is one plumbing commit on the local branch, without touching the working branch, the index or the tree. `learning.py push` uploads it and joins the lines if the remote moved. | only with `push` |

`agents/learning` is written without a PR and only with `learning.py`, like `agents/retros` with `retro.sh`. In a public repo its data is public.

## The event

One JSON line per event, only with the fields of the ADR-007 D3 table. Required: `v`, `ts`, `project`, `kind`, `model` and `harness`.

| field | form |
|---|---|
| `v` | `1` |
| `ts` | `YYYY-MM-DDTHH:MM:SS[.ffffff]Z` (UTC) |
| `project` | the repo name (of `origin`, or else the folder of the main checkout; what is not a letter, number, `.`, `_` or `-` becomes `-`) |
| `task_id` | the ADR-005 id (`244-implementer`) |
| `pr` | a positive number |
| `provider`, `harness`, `area`, `role`, `class`, `rule_id`, `outcome` | slug: lowercase, numbers and hyphens |
| `model` | a model id without spaces (`claude-sonnet-5-5`, `openai/gpt-4o`) |
| `kind` | `check_run`, `task_end`, `deviation` or `finding` |
| `evidence_ref` | a local path or a URL, never the evidence. The URL carries no user or password, no query (`?`), no `%` and no `=` in the path or the fragment: `push` publishes the store, and a token travels there (`#issuecomment-1` is valid) |
| `rules_ref` | `<12 hex>.<12 hex>` (below) |

- `outcome`: `pass`, `fail` or `skipped` in `check_run`; `completed`, `failed`, `incomplete` or `cancelled` in `task_end`; it does not go in `deviation` or `finding`.
- A field that is not in the table, or one with free text, makes the event invalid and nothing is written. The error names the field, never its value.
- `model` comes from `BK_MODEL` (or, without it, from `BARRILETE_MODEL`, which `bk` exports); `harness` from `BK_HARNESS` (or, if it is unset or empty, `claude-code` with `CLAUDECODE=1`; a non-empty invalid one is `unknown`); `provider` from `BK_PROVIDER` (or `BARRILETE_PROVIDER`). Without a known model or harness the event says `unknown`: the emitter never guesses.
- The v0 lines of #323 (the `check_run` of `verify.py` before v1, with `check` and `branch`) are not migrated: `validate` counts them apart as legacy and does not mark them broken, as long as they have exactly that shape. Their `branch` has the characters of a branch name (letters, `ñ` included, numbers, `.`, `_`, `/`, `@`, `+`, `#` and `-`, without `..`), as v0 wrote it; their `task_id`, the ADR-005 one.
- With `BK_TASK_DIR` (a `bk` agent, ADR-005) it also carries `task_id`, `role` and `pr` when `task.json` has them, and `rules_ref`.

### rules_ref

`<first 12 of the rules.lock SHA>.<first 12 of the sha256 of the generated sections>`: the rules block of `AGENTS.md` and the one of `.claude/agents/<role>.md`. If `sync-rules` was not run again, the second half changes and the measurement knows which version the agent had. Without `rules.lock` it does not go.

## Who writes

| kind | who | when |
|---|---|---|
| `check_run` | `verify.py` | each rule check of `.barrilete/checks.json` that runs |
| `task_end` | `task_events.py` | the `Stop` after `bk done`, once `task.json` is terminal; one per task |
| `deviation`, `finding` | `bk learn` (barrilete-workspace) | not yet in the kit |

Writing never stops the work: if the event cannot be written, `verify.py` and the hook go on.

## Commands

```bash
python3 scripts/agents/learning.py validate .barrilete/learning/events.jsonl   # 3 and the line of each broken event; counts legacy v0 lines apart
python3 scripts/agents/learning.py emit check_run rule_id=pr-metadata outcome=pass   # only ts, pr, area, role, class, rule_id, outcome and evidence_ref (inside a bk task not role or pr, which come from task.json); 64 with any other
python3 scripts/agents/learning.py push                                        # store branch only; 1 if git rejects it (with git's reason), 3 with an invalid learning.json
python3 scripts/agents/learning.py rules-ref implementer
```
