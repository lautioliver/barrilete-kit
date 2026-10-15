---
name: db-migration
description: Plans and writes schema changes and database migrations safely (compatibility, backfill, rollback, validation). Use whenever a change touches the schema or migrations, with "/db-migration", "add a column", "change table X" or similar.
---

# Database migration

A schema change is among the hardest things to revert: data that is already migrated does not come back on its own. That is why it requires approval (AGENTS.md, Autonomy) and this plan **before** writing the migration.

The concrete commands (generate a migration, run it locally, tests) are in `AGENTS.md`. TODO: if the project has a migration tool (Drizzle, Prisma, Alembic, hand-written SQL…), document its particulars here.

## 1. Plan (show it and wait for approval)

Touching the schema also requires the Autonomy approval: ask for both in the same message, with this table. Then the full table goes into the PR.

| Point | What to answer |
|---|---|
| Current schema | Tables/columns/indexes/constraints involved, as they are today (read it from the schema code, not from memory). |
| Desired schema | The exact change. |
| Compatibility | Does the code deployed today keep working with the new schema? (versions coexist during the deploy). Are there external readers (reports, other services)? |
| Migration | SQL steps. Does it lock the table? How long does it take with the production volume? |
| Backfill | Does existing data need to be filled in? How, in batches, idempotent? |
| Rollback | How to go back. If it cannot be done without losing data, say so explicitly. |
| Validation | How to check afterwards that it came out right (queries, counts, tests). |

## 2. Rules

- **Destructive changes in two steps** (expand / contract): first add the new thing and make the code use both; in a later PR, when nothing uses the old one, delete it. Never rename or drop a column in use in a single deploy.
- New `NOT NULL` column on a table with data: add it nullable or with a default → backfill → only then `NOT NULL`.
- Indexes on large tables: concurrently if the engine allows it.
- Invariants in the database (constraints, `CHECK`, `UNIQUE`) when the rule has to hold always; not only in the code.
- Migrations are immutable once merged: if something has to be fixed, a new migration.
- **Never** run migrations against shared environments or production. Only local or the test database.

## 3. Implement

1. Change the schema and generate the migration with the project's tool. Review the generated SQL line by line.
2. Run it locally / in tests from scratch and over existing data.
3. Tests: the new behavior, and that the old data is still valid.
4. Docs: `docs/reference/domain.md` (and whatever `agents_map.py` says). If it is a data-model decision that is hard to revert, an ADR.

## 4. PR

In the PR body, the full table from step 1, rollback included. If it is a two-step change, say which step it is in and open the issue for the next one (`create-issue`, blocked by this one).
