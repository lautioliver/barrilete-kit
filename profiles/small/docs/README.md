# <PROJECT> documentation

| For | Read |
|---|---|
| Understanding what runs today | [architecture.md](architecture.md) |
| Knowing why something is the way it is | [decisions/](decisions/README.md) |
| Branches, commits, PRs and labels | [github-naming-convention.md](github-naming-convention.md) |
| Rules for agents | [`AGENTS.md`](../AGENTS.md) and [`llms.txt`](llms.txt) |

Rules:
- If `architecture.md` and the code do not match, the code wins and the doc is fixed **in the same PR**.
- A decision that is hard to revert goes in a new ADR.
- A new document is added to this index and to `llms.txt`.

## Decisions

- [ADR-002](decisions/ADR-002-structured-red-validation.md) — red tests are validated only with a structured report (JUnit or TAP)
- TODO: `- [ADR-001](decisions/ADR-001-....md) — one-line summary`
