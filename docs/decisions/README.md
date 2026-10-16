# Decisions (ADRs) — <PROJECT>

An ADR (Architecture Decision Record) records a decision that is **hard to revert**: product, data, money, infrastructure or legal. It explains the why so nobody undoes it without knowing.

## When to write one

- It changes the data model in a way a revert does not undo.
- It fixes a business rule that others will take for granted.
- It picks a provider, a stack or a topology.
- It contradicts or replaces an earlier ADR.

No ADR is needed for things that are reverted with a PR at no cost.

## Format

- File: `ADR-NNN-<topic-in-kebab-case>.md`, consecutive three-digit number. A number is never reused.
- Start from [`ADR-000-template.md`](ADR-000-template.md).
- Status: `Proposed` → `Accepted (YYYY-MM-DD)` → optionally `Superseded by ADR-NNN`.
- An accepted ADR is not rewritten. If it changes, an `## Amendment YYYY-MM-DD` section is added or a new ADR that replaces it is written.
- Kit ADRs (the ones that explain how the kit is, not the product): line `Ámbito: kit` below `## Status` (the line is kept exactly like that: it is an identifier, not prose). The init (full and `--small`) deletes them, and deletes their lines from the indexes (blocks `<!-- template:start -->` … `<!-- template:end -->`). A project's ADRs do not carry it.
- Numbered rules (`R-1`, `R-2`…) when the code or the tests are going to cite them.

## When accepting an ADR

1. Add it to the index in `docs/README.md` and in `docs/llms.txt`.
2. If it changes an already defined rule, the PR carries the `business-logic` label.
3. If it contradicts existing code, open the issue to align the code (skill `create-issue`).
