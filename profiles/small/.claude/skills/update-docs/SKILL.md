---
name: update-docs
description: Detects which documentation became outdated because of a change and fixes it in the same PR. Use before opening a PR (implement-issue calls it), with "/update-docs", "update the docs" or "which docs went stale?".
---

# Update docs

Agents work with what the docs say: if a doc says something the code no longer does, the next agent builds on something false. If a doc and the code do not match, **the code wins** (except an ADR: there you ask).

1. **Look at the diff:** `git diff <BASE_BRANCH>...HEAD --stat` and then the detail.
2. **Check against each doc:**
   - Did something that runs change (screens, endpoints, data, flows, deploy)? → `docs/architecture.md`.
   - Did a command, a dependency or a convention change? → `AGENTS.md`.
   - Did an ADR decision change? → do not rewrite it: amend with a date or a new ADR (`docs/decisions/README.md`). Ask first.
   - Did you add a document? → `docs/README.md` and `docs/llms.txt`.
3. **Write the minimum:** describe what is there, not the history of the change (that goes in the PR). Do not invent what is not in the code.
4. **Validate:** `python3 scripts/agents/check-docs.py`.
5. **Report** in the PR which docs you changed, or why it was not needed.

For "which docs went stale?": run `check-docs.py`, then compare `docs/architecture.md` and `AGENTS.md` with the code and list the gaps with file and line.
