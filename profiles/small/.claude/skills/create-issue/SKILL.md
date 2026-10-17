---
name: create-issue
description: Opens GitHub issues from a chat request, with title, labels and body following the project convention. Use with "open an issue", "create a ticket", "log this as a bug", "turn these pending items into issues".
---

# Create an issue

Requires an authenticated `gh` (`gh auth status`). The valid labels are only those in `.github/labels.yml`; do not create others.

1. **Understand the request.** Separate how many issues it is. If something essential is missing, ask once; do not make up data.
2. **Look for duplicates:** `gh issue list --state all --search "<keywords>" --limit 10`. If a similar one is open, propose commenting there.
3. **Type** (exactly one `type:`) and **body sections:**

   | Request | Label | Sections |
   |---|---|---|
   | Something does not work | `type:bug` | What happens · What should happen · How to reproduce it |
   | Something new or a visible change | `type:feature` | Goal · Scope · Done when |
   | Technical work | `type:task` | What needs to be done · Why · Done when |
   | Documentation | `type:docs` | What needs to be done · Why |

4. **Title** in the imperative, no prefix or final period: `Add login with Google`. For bugs the symptom works.
5. **Priority** only if the user gave it or it is obvious (it breaks something in use → `priority:high`).
6. **Owner:** `python3 scripts/agents/team.py suggest --labels "<comma-separated labels>"` returns who to assign it to according to `.github/team.json` (by area and load). If it returns nothing, the team is empty: the issue stays unassigned (suggest `/add-member`). If the user asked for someone else, the user wins.
7. **Body:** the sections of the type, links to files with a relative path, no secrets or personal data.
8. **Show the draft (with the owner) and wait for a "yes".** Opening an issue publishes content.
9. **Create** with the body in a temporary file:
   ```bash
   gh issue create --title "<title>" --body-file <file> --label "type:bug" --label "priority:high" --assignee "<owner>"
   ```
10. **Reply** with the link, or with the error if it failed.

If an issue depends on another, say so in the body: `After #12: <why>`.
