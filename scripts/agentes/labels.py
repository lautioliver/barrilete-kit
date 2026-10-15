#!/usr/bin/env python3
"""Combina .github/labels.yml del kit con los labels que ya tiene el repo (#121).

El sync de labels corre con `delete-other-labels: true`: en un repo existente borraría
todos sus labels. Esta función agrega los que ya tiene el repo (`gh label list`) al
archivo, en una sección marcada como propia del proyecto, para que el sync no borre nada.

Uso (lo llama el instalador):
  gh label list --limit 1000 --json name,color,description | python3 scripts/agentes/labels.py .github/labels.yml
Escribe el resultado en la salida estándar.
"""
import json
import re
import sys

MARCA = "# ── propios del proyecto (los que ya tenía el repo) ──────────────"
_NOMBRE = re.compile(r'^- name:\s*["\']?(.*?)["\']?\s*$')
_COLOR = re.compile(r'^(\s+color:\s*)["\']?[0-9A-Fa-f]{3,6}["\']?\s*$')


def _bloque(nombre, color, descripcion):
    return (f"- name: {json.dumps(nombre, ensure_ascii=False)}\n"
            f"  color: {json.dumps(color.lstrip('#').upper())}\n"
            f"  description: {json.dumps(descripcion or '', ensure_ascii=False)}\n")


def combinar(base, existentes):
    """Devuelve `base` más los labels de `existentes` ([{name, color, description}]).

    Sin nombres repetidos (GitHub ignora mayúsculas). Si el nombre ya está en el kit,
    se conserva el color del repo y la descripción del kit. Es idempotente.
    """
    kit = base.split(MARCA)[0].rstrip("\n") + "\n"  # sin la sección propia de una corrida anterior
    por_nombre = {e["name"].lower(): e for e in existentes}

    salida, actual, kit_nombres = [], None, set()
    for linea in kit.splitlines():
        m = _NOMBRE.match(linea)
        if m:
            actual = m.group(1).lower()
            kit_nombres.add(actual)
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
        sys.exit("uso: gh label list --json name,color,description | labels.py <labels.yml>")
    with open(sys.argv[1], encoding="utf-8") as f:
        sys.stdout.write(combinar(f.read(), json.load(sys.stdin)))
