---
name: create-issue
description: Opens loose GitHub issues from a chat request, following the project convention (title, labels, body), turns audits into issues and marks blockers between existing issues ("blocked by"). Use with "open an issue", "create a ticket", "log this as a bug", "turn this audit into issues", "this depends on #12", "block #30 until #25 closes". To plan a feature with several issues, use plan-feature; for "what can I do now?", use project-status.
---

# Create an issue

It turns a natural-language request into one or several issues that follow `docs/github-naming-convention.md` §4–5, and records which issue blocks which with GitHub's native dependencies.

It is not for:
- Planning a feature across several issues (epic, sub-issues, order) → skill `plan-feature`.
- "What can I do now?" → skill `project-status` (`available.sh`).

## Requirements

- `gh` authenticated (`gh auth status`). If it is not, ask the user to run `gh auth login`; do not go on.
- Read `.github/labels.yml` every time: it is the only valid list of labels. **Never** create new labels or use one that is not there.

## Steps

1. **Understand the request.** Work out how many issues there are: a request can bring several problems, and an audit brings one per finding. If something essential is missing (what fails, or what needs to be achieved), ask once; do not invent data.
   Also detect **dependencies**: phrases like "depends on", "after", "first we need", "blocked by", "once #12 is done". Note which one blocks which (see [Blockers](#blockers-between-issues)).

2. **Look for duplicates.**
   ```bash
   gh issue list --state all --search "<keywords>" --limit 10
   ```
   If there is a similar open one, show it and ask whether to comment there instead of opening another.

3. **Pick the type** (exactly one `type:` label):
   | Request | Label | Body template |
   |---|---|---|
   | Something does not work as defined | `type:bug` | `.github/ISSUE_TEMPLATE/1-bug.yml` |
   | New functionality or visible change | `type:feature` | `2-feature.yml` |
   | Technical work with no visible change | `type:task` | `3-task.yml` |
   | Finding from an audit | `type:audit` | `4-audit.yml` |
   | Documentation | `type:docs` | `3-task.yml` |

4. **Write the title.**
   - Imperative, no prefix or brackets, no final period, understandable months later: `Unify accounts by email`.
   - Bug: the symptom is accepted: `The QR does not validate offline`.
   - Audit: `Audit <area>: <finding>`.

5. **Pick the rest of the labels** (only from `labels.yml`):
   - `area:` — 1 or 2, depending on which part of the product it touches. If you are not sure, none.
   - `priority:` — only if the user gave it or it is obvious (breaks production, money or data → `priority:critical`). Otherwise, set no priority and add `status:triage`.
   - `business-logic` — if it asks to change a rule already defined in an ADR, audit or plan. Cite which one in the body.
   - `breaking-change` — if it breaks a public contract.

   **Assignee:** `python3 scripts/agents/team.py suggest --labels "<comma-separated labels>"` returns who to assign it to according to `.github/team.json` (by area and load). If it returns nothing, the team is empty: the issue stays unassigned (suggest `/add-member`). If the user asked for another person, the user wins.

6. **Write the body** with the sections of the chosen template, as Markdown (`## What happens`, `## What should happen`…). Rules:
   - Links to files with a repo-relative path and, if useful, the line.
   - If it comes from an audit or ADR, the link to the document and the ID of the finding or rule.
   - Never secrets, tokens or real personal data.
   - At the end: `_Opened from the chat with Claude Code at the request of @<user>._` (`gh api user -q .login`).

7. **Show the draft and wait for confirmation.** Opening an issue publishes content in the repo. Show the title, labels, **assignee**, body and **blockers** (`#B blocked by #A`) of each issue and ask for an explicit "yes". With several issues, show them all together and confirm the batch once.

8. **Create.** Write the body to a temporary file so the escaping does not break:
   ```bash
   gh issue create --title "<title>" --body-file <file> \
     --label "type:bug" --label "area:api" --label "status:triage" --assignee "<assignee>"
   ```
   Without an assignee, omit `--assignee`. Optional, only if the user asked for them: `--milestone "<name>"`, `--project "<name>"`.

9. **Sub-issues** (link an issue to an epic that already exists; to build a new epic with several issues, use `plan-feature`):
   ```bash
   child_id=$(gh api repos/{owner}/{repo}/issues/<child_n> -q .id)
   gh api repos/{owner}/{repo}/issues/<parent_n>/sub_issues -X POST -F sub_issue_id=$child_id
   ```

10. **Blockers.** If there are dependencies, record them after creating all the issues of the batch (the new ones have no number before). See [Blockers between issues](#blockers-between-issues).

11. **Reply** with the link of each issue created and the blockers that were left. If something failed (nonexistent label, permissions), say so with the error; do not retry with other labels without telling.

## Audit → issues

When the request is "turn audit X into issues":
- One issue per finding, with `type:audit` and the title `Audit <area>: <finding>`.
- The body links `docs/development/<audit>.md` and the finding ID (`AUD-07`).
- If the document has no IDs, propose adding them before opening the issues.
- After creating them, offer to note the issue number next to each finding in the document.

## Blockers between issues

An issue **blocked by** another cannot be started (or finished) until the other is closed. Example: "Migrate payments to the new table" is blocked by "Create the new payments table". GitHub shows it on both issues ("Blocked by" / "Blocking") and in the Project.

Do not confuse with sub-issues: a **sub-issue** is a part of the parent's work; a **blocker** is an order between two pieces of work that may be independent. An epic can have sub-issues that also block each other.

### When to mark a blocker

- The user asks for it ("#30 depends on #25", "X cannot be done until Y").
- When creating a batch where the order is obvious (schema before migration, API before the screen that consumes it). In that case **propose it** in the draft; do not mark it without confirmation.
- Do not mark it just because two issues touch the same area.

### How

Dependencies use the internal `id` of the blocking issue (not the number):

```bash
# #B becomes blocked by #A
id_a=$(gh api repos/{owner}/{repo}/issues/<A> -q .id)
gh api repos/{owner}/{repo}/issues/<B>/dependencies/blocked_by -X POST -F issue_id=$id_a

# See what blocks #B and what #A blocks
gh api repos/{owner}/{repo}/issues/<B>/dependencies/blocked_by -q '.[] | "#\(.number) \(.state) \(.title)"'
gh api repos/{owner}/{repo}/issues/<A>/dependencies/blocking  -q '.[] | "#\(.number) \(.state) \(.title)"'

# Remove the blocker
gh api repos/{owner}/{repo}/issues/<B>/dependencies/blocked_by/$id_a -X DELETE
```

Also:
- When blocking an **open** issue by another **open** one, add the `status:blocked` label and a line at the end of the body: `Blocked by #A: <why>`. The `.github/workflows/unblock.yml` workflow removes the label on its own when all its blockers are closed.
- If the blocking one is already closed, the blocker makes no sense: say so instead of creating it.
- **No cycles.** Before creating `B blocked by A`, check that A is not blocked (directly or indirectly) by B, walking A's `blocked_by`. If there is a cycle, do not create it and explain it.
- For blockers on **existing** issues (not just created), show the change (`#B blocked by #A`) and ask for confirmation as when creating an issue.
- If the API answers 404 or 422 (repo without dependencies enabled, issue from another repo without permission), say so with the error and leave the blocker written in the issue body as a fallback.
