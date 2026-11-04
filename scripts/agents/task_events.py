#!/usr/bin/env python3
"""Task events: Claude Code and Codex hook that records, in the task of a `bk` agent, what happens inside its
session (ADR-005 D1, D4, D5).

The orchestrator (`bk`) creates the task and passes its folder to the agent in BK_TASK_DIR. **Without BK_TASK_DIR
this hook writes nothing and exits 0** (the registration does not even start Python), so a project without `bk`
works as before. It reads the hook JSON from stdin and:

  SessionStart       -> event task.started, status in_progress
  UserPromptSubmit   -> status in_progress (the person answered)
  Stop               -> event turn.waiting, status waiting. It never closes the task (D4): in an interactive
                        session Stop fires at the end of every turn. The agent closes it with `bk done`.
  PostToolUse (Bash) -> `git commit` that worked: event commit (sha); `gh pr create`: event pr.opened (pr).
                        The registration filters in sh before starting Python: other commands cost nothing (D5).

An event records only metadata, never content: no arguments, no tool output, no model text (D5). The sha and
the PR number are read from the output and only they are kept.

The contract it shares with `bk` (lautioliver/bk-shell, lib/tasks.py): task.json is written whole and atomically
(temporary file + rename); every change takes an exclusive flock on <dir>/.lock; `seq` lives in task.json and
grows by one per event, with no gaps; once the status is terminal (completed, failed, incomplete, cancelled)
nothing changes and no event is added; a `pending` task (proposed, not approved) is not touched.

It never blocks the agent: any error exits 0 without writing.
"""
import fcntl
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone

TERMINAL = {"completed", "failed", "incomplete", "cancelled"}
COMMIT_OUT = re.compile(r"^\[[^\]\n]*?\s([0-9a-f]{7,40})\]\s", re.M)   # git commit: "[branch 1a2b3c4] message"
PR_URL = re.compile(r"https://\S+/pull/(\d+)\b")


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def command_of(entry):
    """The shell command of a PostToolUse, or "" (Claude Code: tool_input.command; Codex may send a list)."""
    args = entry.get("tool_input") or {}
    cmd = args.get("command") if isinstance(args, dict) else args
    if isinstance(cmd, list):
        cmd = " ".join(str(c) for c in cmd)
    return cmd if isinstance(cmd, str) else ""


def output_of(entry):
    r = entry.get("tool_response")
    if isinstance(r, dict):
        return "\n".join(str(r.get(k) or "") for k in ("stdout", "output", "stderr"))
    return r if isinstance(r, str) else ""


SEGMENTS = re.compile(r"&&|\|\||[;|\n]")
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def runs(cmd, tool, *sub):
    """True if a segment of the command (split on &&, ||, ;, |, newline) runs `<tool> [options] <sub…>`.

    Linear in the length of the command: no regex with nested repetition. `echo git commit` does not count."""
    for seg in SEGMENTS.split(cmd or ""):
        words = seg.split()
        if not words or os.path.basename(words[0]) != tool:
            continue
        i = 1
        while i < len(words) and words[i].startswith("-"):   # git -C dir commit, gh -R a/b pr create
            i += 2 if words[i] in GIT_OPTS_WITH_VALUE or words[i] in ("-R", "--repo") else 1
        if words[i:i + len(sub)] == list(sub):
            return True
    return False


def change(entry):
    """(new status or None, event type or None, event data) for a hook entry, or None if it records nothing."""
    ev = entry.get("hook_event_name")
    if ev == "SessionStart":
        return "in_progress", "task.started", {}
    if ev == "UserPromptSubmit":
        return "in_progress", None, {}
    if ev == "Stop":
        return "waiting", "turn.waiting", {}
    if ev == "PostToolUse" and entry.get("tool_name") in ("Bash", "shell", "exec_command", None):
        cmd, out = command_of(entry), output_of(entry)
        if runs(cmd, "git", "commit"):
            m = COMMIT_OUT.search(out)
            return (None, "commit", {"sha": m.group(1)}) if m else None
        if runs(cmd, "gh", "pr", "create"):
            m = PR_URL.search(out)
            return (None, "pr.opened", {"pr": int(m.group(1))}) if m else None
    return None


def apply(d, status, etype, data):
    """Applies the change to the task in folder d, under its lock. Returns True if it wrote something."""
    path = os.path.join(d, "task.json")
    if not os.path.isfile(path):
        return False
    fd = os.open(os.path.join(d, ".lock"), os.O_CREAT | os.O_RDWR, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        with open(path) as f:
            task = json.load(f)
        if task.get("status") in TERMINAL or task.get("status") == "pending":
            return False
        if etype is None and (status is None or task.get("status") == status):
            return False
        if status:
            task["status"] = status
        if etype:
            task["seq"] = task.get("seq", 0) + 1
            event = {"seq": task["seq"], "ts": now_iso(), "type": etype, **data}
            with open(os.path.join(d, "events.jsonl"), "a") as f:
                f.write(json.dumps(event, ensure_ascii=False) + "\n")
            task["updated"] = event["ts"]
        tmp_fd, tmp = tempfile.mkstemp(dir=d, prefix=".task.", suffix=".tmp")
        with os.fdopen(tmp_fd, "w") as f:
            json.dump(task, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, path)
        return True
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def main():
    d = os.environ.get("BK_TASK_DIR")
    if not d:
        return 0
    try:
        entry = json.load(sys.stdin)
        c = change(entry) if isinstance(entry, dict) else None
        if c:
            apply(d, *c)
    except Exception:   # a task event is never worth stopping the agent
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
