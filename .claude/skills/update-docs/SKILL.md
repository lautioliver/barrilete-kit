---
name: update-docs
description: Detects which documentation became outdated because of a change and fixes it. Use before opening a PR (implement-issue calls it), with "/update-docs", "update the docs", "which docs went stale?" or to fix gaps between docs and code.
---

# Update docs

Agents work with what the docs say. If a doc says something the code no longer does, the next agent will build on something false. This skill keeps the docs in step with the code.

Underlying rule (`docs/README.md`): if a doc and the code do not match, **the code wins** and the doc is fixed. Exception: if the doc is an ADR, the code may be wrong; in that case, ask.

## Mode 1: after a change (the usual one)

1. **What to touch:**
   ```bash
   python3 scripts/agents/agents_map.py            # current branch against the base
   python3 scripts/agents/agents_map.py --pr <n>   # or a PR
   ```
   It lists the docs that the map (`docs/agents-map.json`) associates with the changed files, marking those that are still **NOT MODIFIED**.
2. **Review each one** against the diff (`git diff <base>...HEAD`). The map suggests; you decide. A listed doc may need no changes (the change does not alter what it describes), and an unlisted doc may need them.
3. **Besides the map**, always check:
   - Did a command or a convention change? → `AGENTS.md`.
   - Did an ADR decision change? → do not rewrite it: amend with a date or a new ADR (`docs/decisions/README.md`). This requires asking (AGENTS.md, "Agent autonomy" section).
   - Did you add a document with content? → `docs/README.md` and `docs/llms.txt`.
   - A new domain term? → `docs/reference/glossary.md`.
4. **Write.** Minimal, precise changes: describe what is there, not the history of the change (that goes in the PR). Do not duplicate canonical lists: if the list lives in another file, link to it.
5. **Validate:**
   ```bash
   python3 scripts/agents/check-docs.py
   ```
6. **Report** which docs you changed and which ones from the map you decided not to touch and why. This goes in the PR.

## Mode 2: audit old gaps

With "which docs went stale?" or "check that architecture.md is up to date":

1. Run `check-docs.py` (broken links and paths are the cheapest symptom).
2. For each doc in `docs/reference/` and `docs/development/architecture.md`, compare what it claims with the code: endpoints, tables, modules, commands. Prioritize what an agent would use to decide.
3. List the gaps found with file and line. Fix the small ones in a `docs(docs): …` PR; the big ones, as issues (`create-issue`, `type:docs`).

## Do not

- Do not invent behavior that is not in the code or in the diff.
- Do not move content from `horizon.md` or `roadmap.md` into `architecture.md` if it is not implemented.
- Do not rewrite accepted ADRs.
