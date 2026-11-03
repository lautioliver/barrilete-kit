#!/usr/bin/env python3
"""How /orchestrate launches a role: main, bk or sub (kit/ADR-004).

Usage: mode.py <role> [--root DIR]
Prints the mode (main, bk or sub) on stdout. Exit 64: bad usage, an unknown mode or `bk mode` failing.

- Without `bk` in the PATH: everything is `sub` (as before bk existed) and stderr says so.
- With `bk`: the role's line in `<root>/.barrilete/roles.yml` (`<role>: <provider>/<model> [mode]`; no mode
  means bk). If the project's file does not have the role, `bk mode <role>` answers (its own roles.yml).
"""
import os
import re
import shutil
import subprocess
import sys

MODES = ("main", "bk", "sub")


def fail(message):
    print(f"mode.py: {message}", file=sys.stderr)
    sys.exit(64)


def project_mode(role, root):
    """The mode in the project's roles.yml, or None if the file or the role is missing."""
    path = os.path.join(root, ".barrilete", "roles.yml")
    if not os.path.isfile(path):
        return None
    line_re = re.compile(rf"^\s*{re.escape(role)}:\s*(?P<spec>[^#\s]+)(?:\s+(?P<mode>[^#\s]+))?\s*(?:#.*)?$")
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = line_re.match(line.rstrip("\n"))
            if m:
                if m["mode"] and m["mode"] not in MODES:
                    fail(f"{path}: unknown mode '{m['mode']}' for {role} (use main, bk or sub)")
                return m["mode"] or "bk"
    return None


def main():
    args = sys.argv[1:]
    root = os.getcwd()
    if "--root" in args:
        i = args.index("--root")
        if i + 1 >= len(args):
            fail("usage: mode.py <role> [--root DIR]")
        root = args[i + 1]
        del args[i:i + 2]
    if len(args) != 1 or args[0].startswith("-"):
        fail("usage: mode.py <role> [--root DIR]")
    role = args[0]
    if shutil.which("bk") is None:
        print("sub")
        print("mode.py: bk is not installed: every role runs as a subagent (sub)", file=sys.stderr)
        return
    mode = project_mode(role, root)
    if mode is None:
        r = subprocess.run(["bk", "mode", role], capture_output=True, text=True, cwd=root)
        mode = r.stdout.strip()
        if r.returncode != 0 or mode not in MODES:
            fail(f"`bk mode {role}` did not answer main, bk or sub ({r.stderr.strip() or mode or 'no output'})")
    print(mode)


if __name__ == "__main__":
    main()
