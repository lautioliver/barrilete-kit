---
name: add-member
description: Adds a member to the project team (or edits their areas) so they get issues assigned automatically. Use with "/add-member @user", "add X to the team", "X now covers payments", "list the team".
---

# Add a member

The team lives in `.github/team.json` and `create-issue` and `plan-feature` use it to assign every new issue: among the active members who cover some `area:` of the issue, the one with the fewest open issues; if nobody covers the area, the one with the lowest load in the whole team.

1. **Data:** GitHub user (required), name and the areas they cover (`area:` labels from `.github/labels.yml`). If the user gives no areas, ask; without areas they get issues from any area.
2. **Add or edit** (if they are already there, it updates name or areas):
   ```bash
   python3 scripts/agents/team.py add <login> --name "<Name>" --areas area:x,area:y
   ```
   It validates that the user exists and has access to the repo (GitHub does not let you assign issues to someone who does not). If the invitation is missing, say so; `--force` only if the user confirms the invitation is pending.
3. **See the team:** `python3 scripts/agents/team.py list` (with each member's load).
4. **Commit** `.github/team.json` on a branch and open a PR (`chore: …`): the team is repo configuration and goes in through a PR like everything else.

To pause someone without removing them (vacation, another priority): `team.py pause <login>` / `activate <login>`.
