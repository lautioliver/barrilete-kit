# <PROJECT> documentation

TODO: what <PROJECT> is in one sentence, with a link to the ADR that defines it.

This folder is the map. The code is the truth of what runs; here it says **where to read** and **what not to mix**.

---

## How to read (pick a path)

| Who | Start here | Then |
|---|---|---|
| New person on the team | This file → [glossary](reference/glossary.md) → [journeys](reference/journeys.md) | [setup](development/setup.md) and get running |
| Product / business | [Vision](development/vision.md) → [Spec](../README.md) → [roadmap](development/roadmap.md) | [horizon](development/horizon.md) (it is not the next ticket) |
| Engineering (what exists today) | [architecture](development/architecture.md) → [modules](reference/modules.md) → [domain](reference/domain.md) | [surfaces](reference/surfaces.md) |
| Deploy | [deploy](development/deploy.md) | Infrastructure ADRs |
| Agent / LLM | [`llms.txt`](llms.txt) and [`AGENTS.md`](../AGENTS.md) | Do not invent schema or roadmap |

Rule: if a product document and the code do not match, [architecture.md](development/architecture.md) **wins**. The [README](../README.md) is spec (it includes what is coming). The [vision](development/vision.md) summarizes what it is, what exists and what is coming. The [horizon](development/horizon.md) is a long-term conversation.

---

## Layers of truth

| Layer | File | Used for |
|---|---|---|
| Spec | [`README.md`](../README.md) | What we want the product to be |
| Vision | [`development/vision.md`](development/vision.md) | What it is / what exists / what is coming (narrative) |
| Now | [`development/architecture.md`](development/architecture.md) | What is implemented |
| Order | [`development/roadmap.md`](development/roadmap.md) | What gets built and in what order |
| Later | [`development/horizon.md`](development/horizon.md) | Long-term ideas — **do not implement** |
| Why | [`decisions/`](decisions/) | ADRs |
| How it is run | [`development/setup.md`](development/setup.md) | Local dev |
| How it is published | [`development/deploy.md`](development/deploy.md) | Environments and deploy |
| How it is integrated | [`guides/`](guides/) | Third-party integrations |
| Map | [`reference/`](reference/) | Glossary, data, screens, modules, journeys |

---

## Index

### Reference

- [Glossary](reference/glossary.md) — words that do not change
- [Domain and data](reference/domain.md) — tables, IDs, states
- [Surfaces](reference/surfaces.md) — URLs and who gets in
- [Modules](reference/modules.md) — where each thing lives in the code
- [Journeys](reference/journeys.md) — end to end, with files

### Development

- [Setup](development/setup.md)
- [Implemented architecture](development/architecture.md)
- [Vision](development/vision.md)
- [Roadmap](development/roadmap.md)
- [Horizon](development/horizon.md)
- [Deploy](development/deploy.md)
- Audits: `development/audit-<topic>-<YYYY-MM-DD>.md`. Each finding with a stable ID (`AUD-01`…) so an issue can be opened per finding.

### Decisions

- [How to write an ADR](decisions/README.md)
<!-- template:start -->
- [ADR-001 (kit)](decisions/ADR-001-language-labels-and-names-in-english.md) — kit language: prose in two languages, labels and names in English (kit ADR: the init does not install it)
<!-- template:end -->
- [ADR-002](decisions/kit/ADR-002-structured-red-validation.md) — red tests are validated only with a structured report (JUnit or TAP)
- TODO: `- [ADR-001](decisions/ADR-001-....md) — one-line summary`

### Guides

- TODO: one guide per integration.

### Agents

- [`AGENTS.md`](../AGENTS.md) — short conventions for whoever touches the repo
- [`llms.txt`](llms.txt) — compact index for models
- [`github-naming-convention.md`](github-naming-convention.md) — branches, commits, PRs, issues and labels ([`.github/labels.yml`](../.github/labels.yml))
- [`agents-map.json`](agents-map.json) — which docs to review depending on what changes, sensitive paths and required docs
- [`agents/subagent-contract.md`](agents/subagent-contract.md) — rules and output format of the subagents in `.claude/agents/` (implementer, light implementer, reviewer)
- [`agents/lessons.md`](agents/lessons.md) — what was learned from the agents' retros, reviewed in a PR (the raw retros live on the `agents/retros` branch)
- Skills in [`../.claude/skills/`](../.claude/skills/): `plan-feature`, `create-issue`, `implement-issue`, `debug`, `db-migration`, `update-docs`, `review-pr`, `project-status`, `git-workflow`, `improve-skills`, `orchestrate`
- The docs are validated in CI: [`../scripts/agents/check-docs.py`](../scripts/agents/check-docs.py)

---

## How to maintain this section

- Change in **behavior that already runs** → `architecture.md` and, if it applies, `reference/*`.
- Change in **product order** → `roadmap.md`.
- Change in the **narrative of what it is / what exists / what is coming** → `vision.md`.
- A **someday** idea → `horizon.md`, not the code.
- Irreversible decision → new ADR in `decisions/`.
- An ADR and the code do not match → update the ADR or the code; do not leave both.
- New document → add it to this index. It is added to `llms.txt` only once it has content (not just `TODO:`).

Do not duplicate canonical lists (endpoints, tables): they live in a single file and the rest link to it.
