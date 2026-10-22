#!/usr/bin/env python3
"""Flow line (stub of the red commit, #181): the signatures the tests need, with no logic."""
import os
import re
import subprocess  # noqa: F401
import sys
import tempfile

CACHE_TTL = 30
CACHE_NOMBRE = "agent-kit-flow.json"
CACHE_RAMAS = 20
RAMA_RE = re.compile(r"^$")
PASOS = []
CARAS = {}
CARA_DEL_PASO = dict.fromkeys([None, "implement", "review", "merge", "retro", "blocked"], "")
OCUPADO_DIR = os.path.join(tempfile.gettempdir(), "flow")
OCUPADO_MAX = 0


def paso_actual(datos):
    return None


def linea(e, formato):
    return ""


def vista_grande(e, formato):
    return ""


def cara_chica(cara, formato, cuadro=None):
    return ""


def cara_grande(cara, formato):
    return [""]


def duracion(segundos):
    return ""


def guardar(ruta, datos):
    open(ruta, "w").write("{}")


def guardar_rama(ruta, rama, datos, si_sigue=None):
    guardar(ruta, {})


def datos_github(cwd, ruta, rama, issue):
    return {}


def main(argv=None):
    print("{}" if "json" in (argv or sys.argv) else "")
    return 0


if __name__ == "__main__":
    sys.exit(main())
