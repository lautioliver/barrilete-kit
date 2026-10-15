#!/usr/bin/env python3
"""Combines the kit's .github/labels.yml with the labels the repo already has (#121).

The label sync runs with `delete-other-labels: true`: in an existing repo it would delete
all its labels. This function adds the ones the repo already has (`gh label list`) to the
file, in a section marked as the project's own, so the sync deletes nothing.

Usage (called by the installer):
  gh label list --limit 1000 --json name,color,description | python3 scripts/agents/labels.py .github/labels.yml
Writes the result to standard output only if the input is valid; do not redirect over the
same file that is read (save to a temporary file and move). Everything below the marker
belongs to this script and is regenerated: the project's own goes above it.
"""
import json
import re
import sys

MARCA = "# ── project's own labels (the ones the repo already had) ─────────"
# The 0.9 text of the marker: a labels.yml from 0.9 has its own section under it.
MARCA_0_9 = "# ── propios del proyecto (los que ya tenía el repo) ──────────────"
_ALIAS = re.compile(r'^\s+-\s*["\']?(.*?)["\']?\s*$')
_NOMBRE = re.compile(r'^- name:\s*["\']?(.*?)["\']?\s*$')
_COLOR = re.compile(r'^(\s+color:\s*)["\']?[0-9A-Fa-f]{3,6}["\']?\s*$')


def _bloque(nombre, color, descripcion):
    return (f"- name: {json.dumps(nombre, ensure_ascii=False)}\n"
            f"  color: {json.dumps(color.lstrip('#').upper())}\n"
            f"  description: {json.dumps(descripcion or '', ensure_ascii=False)}\n")


def combinar(base, existentes):
    """Returns `base` plus the labels of `existentes` ([{name, color, description}]).

    No repeated names (GitHub ignores case). If the name is already in the kit (or is an alias of a kit label),
    the repo color and the kit description are kept. It is idempotent.
    """
    kit = base.split(MARCA_0_9)[0].split(MARCA)[0].rstrip("\n") + "\n"  # without the own section of a previous run
    por_nombre = {e["name"].lower(): e for e in existentes}

    salida, actual, kit_nombres, en_aliases = [], None, set(), False
    for linea in kit.splitlines():
        m = _NOMBRE.match(linea)
        if m:
            actual = m.group(1).lower()
            kit_nombres.add(actual)
            en_aliases = False
        elif re.match(r"^\s+aliases:\s*$", linea):
            en_aliases = True
        elif en_aliases and _ALIAS.match(linea):
            # An alias is a kit label (label-sync renames it): it is not the project's own.
            kit_nombres.add(_ALIAS.match(linea).group(1).lower())
        else:
            en_aliases = False
        c = _COLOR.match(linea)
        if c and actual in por_nombre:
            linea = f'{c.group(1)}"{por_nombre[actual]["color"].lstrip("#").upper()}"'
        salida.append(linea)
    texto = "\n".join(salida) + "\n"

    propios = [e for e in existentes if e["name"].lower() not in kit_nombres]
    if propios:
        texto += "\n" + MARCA + "\n" + "".join(
            _bloque(e["name"], e["color"], e.get("description")) for e in propios)
    return texto


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: gh label list --json name,color,description | labels.py <labels.yml>")
    with open(sys.argv[1], encoding="utf-8") as f:
        base = f.read()
    try:
        existentes = json.load(sys.stdin)
        resultado = combinar(base, existentes)
    except (ValueError, KeyError, TypeError) as e:
        sys.exit(f"labels.py: the input is not the output of `gh label list --json name,color,description` ({e}). I wrote nothing.")
    sys.stdout.write(resultado)
