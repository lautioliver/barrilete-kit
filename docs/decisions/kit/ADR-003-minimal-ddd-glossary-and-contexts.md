# ADR-003 — Minimal DDD: glossary and bounded-context map in every project

## Status

Accepted (2026-11-02)

Origin: epic lautioliver/barrilete-kit#214 ("Traer lo mínimo de Domain-Driven Design a todos los proyectos") and its first issue, lautioliver/barrilete-kit#215. Decisions 1 to 7 of the epic were approved by @lautioliver in the chat on 2026-11-02, and they are recorded below as they were approved, with no change. Where a rule says "approved by @lautioliver in the chat (2026-11-02)", that is the approval.

## Context

- The kit has no shared vocabulary for the domain of a project and no map of its bounded contexts. The agents read `docs/reference/domain.md` and `docs/reference/modules.md`, which describe entities and modules, not the limits between them.
- `docs/reference/glossary.md` already exists in the full profile, as a `TODO` template. Nobody reads it: no skill and no check uses it.
- `--small` deletes `docs/reference/` as a whole (`profiles/small/DELETE`), so the small profile has no glossary. Its `docs/agents-map.json` has only `red`, and `check-docs.py` treats it apart (`SOLO_RED`) without validating `required`.
- `implement-issue` already reads "what applies from `docs/reference/`", `plan-feature` names it in general terms, and `review-pr` has no row for language or for context limits. The `--small` profile does not ship `plan-feature` or `review-pr`.
- Every project created from the kit would get the same rules. Taking them out later is a break for every project that already follows them, so what was decided in the chat has to be written where the agents read it.

## Decision

1. **D1. The kit gets an ADR, in `docs/decisions/kit/`.** This document is `kit/ADR-003`. It is the first issue of epic #214.

2. **D2. Where the glossary and the map live.**
   - **Full profile:** `docs/reference/glossary.md` (it already exists) and docs/reference/contexts.md (new).
   - **`--small` profile:** docs/glossary.md and docs/contexts.md, flat, like docs/architecture.md.
   - `grow.py` moves the small files to `docs/reference/`, when a project grows to the full profile.

3. **D3. Which code belongs to which context.**
   - **Full profile:** a new `contexts` section in `docs/agents-map.json`, with entries of the form `[{"name": "...", "paths": ["<glob>"], "depends_on": ["<name>"]}]`: `name`, `paths` (globs) and `depends_on` (the names of other contexts). `agents_map.py` uses it to say which contexts a diff touches, and `check-docs.py` validates it. It exists only in the full profile.
   - **`--small` profile:** only the table in docs/contexts.md. The small map keeps only `red` (ADR-002 D2).

4. **D4. What counts as crossing a limit.** A new dependency between contexts that is not in `depends_on` (or, in `--small`, not in the table). Touching two contexts in one PR is a signal for the reviewer, not an infraction.

5. **D5. How `check-docs.py` validates in `--small`.** In the `SOLO_RED` case it requires the two files by a fixed path. No `required` entry is added to the small map.

6. **D6. Severity in `review-pr`.**
   - A context crossing without an ADR is **to be fixed**.
   - A domain term that is not in the glossary is a **suggestion**: add it to the glossary or use the existing term.
   - "Blocking" is reserved for business rules.

7. **D7. An empty glossary (`TODO`).** The rules do not block. The agent proposes terms in its PR. `check-docs.py` only checks that the files exist and are linked, not what they say.

**Migrations.** There is no schema migration. From the kit: `update.py` and `install.py` bring the new files (the full glossary already exists); `grow.py` moves the small files to `docs/reference/`; a map without a `contexts` section is read as empty.

## Rejected alternatives

- **Tactical patterns in the glossary (aggregates, repositories, domain events).** They are an architecture decision for each project, not a minimum that every project needs. They are left out of scope.
- **Analysing imports, per language, to detect context crossings.** It would need one parser per language. The `depends_on` declaration is explicit and works for any stack (D3, D4).
- **A `contexts` section in the small map.** It would bring back the full map's complexity into the profile that deliberately has only `red` (ADR-002 D2). The small profile uses the table of docs/contexts.md (D3, D5).
- **A `required` entry in the small map.** For the same reason as above: the fixed paths of D5 cover it without changing the small map.

## Consequences

- `review-pr` can flag crossings and undefined terms with the severity of D6. The risk is noise, so only the domain names in the changed code and docs are marked, and the terms come as suggestions.
- Each skill that reads the glossary gets one line that points to this ADR, to keep the skills under their 120-line limit.
- A project installed with `install.py` that already has its glossary in another path gets a warning from the installer. The installer does not overwrite it.
- The new sections of `docs/agents-map.json` and the CI tests of the init and the update are sensitive paths: the approval is the one recorded in this ADR, and the change is checked by the tests of `test-init.sh`, `check-docs.py`, `agents_map.py`, `test-update.sh`, `test-install.sh`, the `grow` test and `test-i18n.sh`.
- Out of scope: filling in the kit's own glossary, and any check that reads the content of the glossary.
