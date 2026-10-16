---
skill: implement-issue | review-pr | improve-skills | orchestrate
issue: <n> (in review-pr, if the PR closes none: "no issue"; in orchestrate, the epic's no.)
run: <YYYYMMDD-HHMM> (orchestrate only, if the run is not for an epic)
pr: <n or "no PR">
area: <area: of the issue, or "none">
paths: <main files or folders it touched, comma-separated>
model: opus | sonnet | haiku (or "unknown")
role: implementer | implementer-light | reviewer | orchestrator | session
---
**Deviations:** where the skill was not followed and why (or "none").
**Decisions not covered:** what had to be decided that the skill did not say.
**What the review found:** findings the implementation did not see — in implement-issue, those from `/code-review` or `/security-review`; in review-pr, the blockers (or "nothing").
**Proposal:** optional, what you would change.
