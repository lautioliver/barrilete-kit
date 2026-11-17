#!/usr/bin/env python3
"""Bitácora de agentes (#339). Stub del rojo: todavía no lee las retros."""
import os
import sys
import time

raiz = sys.argv[sys.argv.index("-C") + 1] if "-C" in sys.argv else "."
os.makedirs(os.path.join(raiz, ".barrilete"), exist_ok=True)
with open(os.path.join(raiz, ".barrilete", "bitacora.html"), "w", encoding="utf-8") as f:
    f.write(str(time.time_ns()))
