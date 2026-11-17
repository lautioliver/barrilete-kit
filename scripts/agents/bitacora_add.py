#!/usr/bin/env python3
"""Stub de #343 para el rojo: todavía no busca ni inserta nada; add solo deja docs/bitacora.html vacío."""
import os
import subprocess
import sys


def main(argv):
    repo = argv[argv.index("-C") + 1] if "-C" in argv else "."
    r = subprocess.run(["git", "-C", repo, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    raiz = r.stdout.strip() if r.returncode == 0 else repo
    if "add" in argv:
        os.makedirs(os.path.join(raiz, "docs"), exist_ok=True)
        open(os.path.join(raiz, "docs", "bitacora.html"), "a", encoding="utf-8").close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
