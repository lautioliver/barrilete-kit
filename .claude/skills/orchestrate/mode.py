#!/usr/bin/env python3
"""How /orchestrate launches a role: main, bk or sub (kit/ADR-004).

Usage: mode.py <role> [--root DIR]
Prints the mode (main, bk or sub) on stdout. Exit 64: bad usage, a missing --root, a role line that does not parse, an unknown mode or `bk mode` failing.

- The role's line in `<root>/.barrilete/roles.yml` (`<role>: <provider>/<model> [mode]`; no mode means bk).
  If the project's file does not have the role, `bk mode <role>` answers (its own roles.yml).
- Without `bk` in the PATH: an explicit `main` of the project's file is respected; everything else is `sub`
  (as before bk existed) and stderr says so.
- `reviewer` and `implementer-light` are never `bk` (`bk run` starts a plain /implement-issue session, not their
  agent definition, kit/ADR-004): a `bk` answer becomes `sub`. `main` and `sub` are kept.
"""
import os
import re
import shutil
import subprocess
import sys

MODES = ("main", "bk", "sub")
SUB_ONLY = ("reviewer", "implementer-light")


def fail(message):
    print(f"mode.py: {message}", file=sys.stderr)
    sys.exit(64)


def project_mode(role, root):
    """The mode in the project's roles.yml, or None if the file or the role is missing."""
    path = os.path.join(root, ".barrilete", "roles.yml")
    if not os.path.isfile(path):
        return None
    line_re = re.compile(rf"^\s*{re.escape(role)}:\s*(?P<spec>[^#\s]+)(?:\s+(?P<mode>[^#\s]+))?\s*(?:#.*)?$")
    key_re = re.compile(rf"^\s*{re.escape(role)}:")
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except (OSError, UnicodeDecodeError) as e:
        fail(f"cannot read {path}: {e}")
    for line in lines:
        m = line_re.match(line)
        if m:
            if "/" not in m["spec"].strip("/"):
                fail(f"{path}: the line of {role} has `{m['spec']}` where `<provider>/<model>` goes")
            if m["mode"] and m["mode"] not in MODES:
                fail(f"{path}: unknown mode '{m['mode']}' for {role} (use main, bk or sub)")
            return m["mode"] or "bk"
        if key_re.match(line):
            fail(f"{path}: the line of {role} is not `{role}: <provider>/<model> [mode]`: {line.strip()!r}")
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
    if not os.path.isdir(root):
        fail(f"--root {root} is not a directory")
    mode = project_mode(role, root)
    if shutil.which("bk") is None:
        if mode == "main":
            print("main")
            return
        print("sub")
        print("mode.py: bk is not installed: every role runs as a subagent (sub)", file=sys.stderr)
        return
    if mode is None:
        try:
            r = subprocess.run(["bk", "mode", role], capture_output=True, text=True, cwd=root, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as e:
            fail(f"`bk mode {role}` could not run: {e}")
        mode = r.stdout.strip()
        if r.returncode != 0 or mode not in MODES:
            fail(f"`bk mode {role}` did not answer main, bk or sub ({r.stderr.strip() or mode or 'no output'})")
    if mode == "bk" and role in SUB_ONLY:
        mode = "sub"
    print(mode)


if __name__ == "__main__":
    main()
