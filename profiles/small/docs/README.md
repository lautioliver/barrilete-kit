# <PROJECT> documentation

| For | Read |
|---|---|
| Understanding what runs today | [architecture.md](architecture.md) |
| Using the project's words | [glossary.md](glossary.md) |
| Knowing the contexts and their limits | [contexts.md](contexts.md) |
| Knowing why something is the way it is | [decisions/](decisions/README.md) |
| Branches, commits, PRs and labels | [github-naming-convention.md](github-naming-convention.md) |
| Rules for agents | [`AGENTS.md`](../AGENTS.md) and [`llms.txt`](llms.txt) |

Rules:
- If `architecture.md` and the code do not match, the code wins and the doc is fixed **in the same PR**.
- A decision that is hard to revert goes in a new ADR.
- A new document is added to this index and to `llms.txt`.

## Decisions

- [ADR-002](decisions/kit/ADR-002-structured-red-validation.md) — red tests are validated only with a structured report (JUnit or TAP)
- [ADR-003](decisions/kit/ADR-003-minimal-ddd-glossary-and-contexts.md) — every project gets a domain glossary and a bounded-context map, with the rules the agents apply to them
- [ADR-004](decisions/kit/ADR-004-orchestrate-launch-mode-per-role.md) — `/orchestrate` launches each role as a `bk` agent or a subagent, per `roles.yml` (accepted)
- TODO: `- [ADR-001](decisions/ADR-001-....md) — one-line summary`
