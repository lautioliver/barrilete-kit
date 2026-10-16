---
name: plan-feature
description: Turns an idea or big feature into a researched technical plan and then into an epic with issues and dependencies. It writes no code. Use with "/plan-feature", "plan X", "I want to do X, how do we approach it?" or before any work that does not fit in a single PR.
---

# Plan a feature

It avoids starting to code too early. First you understand what is there, then you decide, and only at the end do you split into issues. **This skill touches no code.**

## 1. Research

Before proposing anything, read:
- `docs/development/architecture.md`, `docs/reference/` (domain, modules, surfaces) and the related ADRs.
- The code of the modules that will be touched: how it is built today, not how it should be.
- `docs/development/roadmap.md` and `horizon.md`: was it already planned? Does it clash with anything?
- Related open issues (`gh issue list --search …`) and `.claude/skills/project-status/available.sh`.

If the idea is vague on something that changes the design (who uses it, what happens in the edge cases), ask now, before writing the plan.

## 2. Technical plan

Write it with these sections. Be concrete: real files and modules, not generic ones.

```markdown
## Goal
What is achieved and for whom. What is explicitly left out.

## Current state
How what will be touched works today (with paths).

## Affected components
Modules, tables, endpoints, screens. Mark the sensitive ones (docs/agents-map.json).

## Decisions needed
What has to be decided before building, with options and a recommendation.
The hard-to-revert ones → propose an ADR.

## Risks
What can go wrong (data, money, security, performance, active users) and how it is mitigated.

## Migrations
Schema changes and their strategy (skill db-migration). "None" if there are none.

## Tests
What has to be tested and at what level.

## Issues
The split into PRs, in order, with their blockers.
```

**Show the plan and stop.** The decisions in the "Decisions needed" section are taken by the user or the team, not the agent. Iterate until they approve it.

## 3. Split into issues

With the plan approved:
- Each issue = one PR that is reviewed on its own and leaves the system working. Typically 3 to 8.
- Blockers only where there really is an order (schema → API → screen). Parallel things, with no blocker.
- If there are pending decisions or an ADR to write, they are the first issue and **are loaded as a blocker** (`blocked_by`) of the issues that depend on that decision. Having the epic say so in its text is not enough: `prepare.sh` only sees loaded blockers.
- No issue goes out with undefined values ("a reasonable window", "an adequate limit"): either the plan fixes them, or the issue carries an **Open decisions** section with the concrete question for the team.
- Destructive migrations in two steps (expand / contract) are two issues.

## 4. Create

The **full technical plan goes in the epic's body**: that way it stays next to the issues and `/implement-issue` reads it when taking each one. Do not create a separate document in `docs/` unless it is an ADR. It is created with `planner.py` (in this folder; requires `python3`):

1. **Write the plan** in a temporary JSON (outside the repo):
   ```json
   {
     "epic": {"title": "Migrate accounts to the new table", "body": "## Goal\n…", "labels": ["type:feature", "area:api"]},
     "issues": [
       {"key": "schema", "title": "Create the accounts table", "body": "…", "labels": ["type:task", "area:infra"]},
       {"key": "api", "title": "Expose accounts in the API", "body": "…", "labels": ["type:task", "area:api"],
        "blocked_by": ["schema"], "reason": "needs the table"},
       {"key": "screen", "title": "Show accounts in the dashboard", "body": "…", "labels": ["type:feature"],
        "blocked_by": ["api", 25], "reason": "consumes the endpoint; #25 defines the design"}
     ]
   }
   ```
   `blocked_by` accepts plan keys or numbers of existing issues. Titles, labels and bodies follow the convention of the `create-issue` skill (steps 3–6).
2. **Validate and show the draft:**
   ```bash
   .claude/skills/plan-feature/planner.py <plan.json> --draft
   ```
   It validates labels against `labels.yml`, exactly one `type:` per issue, existing keys and numbers, and that there are no cycles. It shows the issues in the order they can be done. If it fails, fix the plan; do not skip the validation.
   Show the user that output and ask for an explicit "yes".
3. **Create:**
   ```bash
   .claude/skills/plan-feature/planner.py <plan.json>
   ```
   It creates the epic, each issue in order, links them as sub-issues, records the blockers, adds `status:blocked` and the `Blocked by #N` line where it applies. If it fails halfway, it reports what it managed to create: show it and do not retry the whole plan (it would duplicate issues); create only what is missing.

## 5. Deliver

Link to the epic, the issues in order and what can be started now (`.claude/skills/project-status/available.sh`). The next step is `/implement-issue <n>` on the first available one.
