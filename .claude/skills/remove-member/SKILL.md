---
name: remove-member
description: Removes or pauses a team member so they stop getting issues assigned automatically. Use with "/remove-member @user", "take X off the team", "X is going on vacation".
---

# Remove a member

1. **Remove or pause?** If it is temporary (vacation, another priority), pause: they stay on the team but get no new issues.
   ```bash
   python3 scripts/agents/team.py pause <login>    # or: activate <login>
   python3 scripts/agents/team.py remove <login>
   ```
2. **Their open issues stay assigned.** List them (`gh issue list --assignee <login> --state open`) and ask whether to reassign them. To reassign each one to whoever fits according to the team:
   ```bash
   new=$(python3 scripts/agents/team.py suggest --labels "<the issue's labels, comma-separated>")
   gh issue edit <n> --remove-assignee <login> --add-assignee "$new"
   ```
   Show the list of reassignments and wait for a "yes" before applying it.
3. **Commit** `.github/team.json` on a branch and open a PR.
