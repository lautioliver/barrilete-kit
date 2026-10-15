#!/usr/bin/env python3
"""Which implementer an issue gets: the routing rule of epic #33 (decision 2).

Haiku only if the issue is type:docs or type:task, without business-logic or breaking-change and without
sensitive paths (docs/agents-map.json) named in the title or the body. Everything else, Sonnet.
If Haiku later finds sensitive paths with agents_map.py, it escalates (implementer-light.md).

Usage: routing.py <issue number>
Prints the model (haiku or sonnet) on the first line and the reason on the second.
"""
import json
import os
import re
import subprocess
import sys

RAIZ = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
sys.path.insert(0, os.path.join(RAIZ, "scripts", "agents"))

LIVIANOS = {"type:docs", "type:task"}
RIESGO = {"business-logic", "breaking-change"}


def salir(mensaje):
    print(f"routing.py: {mensaje}", file=sys.stderr)
    sys.exit(2)


def sensibles_nombradas(texto, mapa):
    """Paths in the text (with or without backticks) that fall in a sensitive path of the map. It counts each
    word, with or without "/" (package.json, Dockerfile), a folder without a trailing slash (src/auth),
    a path with "./" in front or inside a link (…/blob/main/src/auth/x.ts), case-insensitive.
    Erring towards Sonnet is fine: "infra" in prose also counts."""
    from agents_map import glob_a_regex
    palabras = {c.rstrip(".,;:") for c in re.findall(r"[\w.-]+(?:/[\w.-]*)*", texto)} - {""}
    hallazgos = []
    for s in mapa.get("sensitive", []):
        regex = [re.compile(glob_a_regex(g).pattern, re.I) for g in s.get("paths", [])]
        for palabra in sorted(palabras):
            partes = palabra.removeprefix("./").split("/")
            # The whole path and each suffix after a "/" (covers GitHub links).
            sufijos = ["/".join(partes[i:]) for i in range(len(partes))]
            if any(r.match(c) or r.match(c.rstrip("/") + "/x") for c in sufijos if c for r in regex):
                hallazgos.append(f"{palabra} ({s.get('type', 'sensitive')})")
    return hallazgos


def main():
    if len(sys.argv) != 2 or not sys.argv[1].lstrip("#").isdigit():
        salir("usage: routing.py <issue number>")
    n = sys.argv[1].lstrip("#")
    r = subprocess.run(["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
                       capture_output=True, text=True)
    repo = r.stdout.strip()
    if r.returncode != 0 or not repo:
        salir(f"could not read the GitHub repo ({r.stderr.strip() or 'gh failed'}). Is there a remote and is gh authenticated?")
    r = subprocess.run(["gh", "api", f"repos/{repo}/issues/{n}"], capture_output=True, text=True)
    if r.returncode != 0:
        salir(f"could not read issue #{n} ({r.stderr.strip() or 'gh failed'}).")
    issue = json.loads(r.stdout)
    labels = {l["name"] if isinstance(l, dict) else l for l in issue.get("labels", [])}

    tipo = sorted(l for l in labels if l.startswith("type:"))
    if not tipo or not set(tipo) <= LIVIANOS:
        return print("sonnet", f"motivo: {', '.join(tipo) or 'no type:'} is not only type:docs or type:task", sep="\n")
    riesgo = sorted(RIESGO & labels)
    if riesgo:
        return print("sonnet", f"motivo: it carries {', '.join(riesgo)}", sep="\n")
    ruta_mapa = os.path.join(RAIZ, "docs", "agents-map.json")
    if not os.path.exists(ruta_mapa):
        return print("sonnet", "motivo: there is no docs/agents-map.json to rule out sensitive paths", sep="\n")
    with open(ruta_mapa, encoding="utf-8") as f:
        mapa = json.load(f)
    nombradas = sensibles_nombradas(f"{issue.get('title', '')}\n{issue.get('body') or ''}", mapa)
    if nombradas:
        return print("sonnet", f"motivo: names sensitive paths: {', '.join(nombradas)}", sep="\n")
    print("haiku", f"motivo: {', '.join(tipo)} without business-logic, breaking-change or named sensitive paths", sep="\n")


if __name__ == "__main__":
    main()
