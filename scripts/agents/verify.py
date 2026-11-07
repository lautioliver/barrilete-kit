#!/usr/bin/env python3
"""Last guard before the PR: depending on what changed, decides what to verify and runs it.

Checks are configured in the "verify" section of docs/agents-map.json:
  {"name": "tests", "always": true, "run": "npm test"}
  {"name": "migrations", "when": ["db/schema/**"], "run": "…"}
A check runs if it is "always" or if any changed file matches "when".
In "run" you can use {base} (the base branch reference, e.g. origin/main)
and {files} (the matching changed files that still exist, quoted: a deleted file
cannot be verified, and a rule with {files} whose only matches were deleted does not run, "always" or not;
verify.py says which ones it skipped). With --pr the files are not filtered: this checkout may not have them.
A "run" that starts with "TODO" is reported as not configured and is not executed.
It also runs the checks of the rules (ADR-006 D8): .barrilete/checks.json, which scripts/agents/sync-rules generates from
barrilete-rules, lists {"id", "rule", "fail_message"}; each one runs scripts/agents/checks/<id> --base <ref>, always, and when it
fails verify.py prints the rule and its fail_message (what to do and when to escalate). A manifest that cannot be read exits with 2.

Usage:
  verify.py                 # against the base branch (BASE, <BASE_BRANCH> or the remote default)
  verify.py --base develop
  verify.py --list          # shows what would run, without running anything
Exits with 1 if any check fails.
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agents_map import RAIZ, archivos_cambiados, coincide, existe, rama_base  # noqa: E402


def referencia_base(args, base):
    return f"origin/{base}" if existe(f"origin/{base}") else base


def checks_de_reglas():
    """The checks of .barrilete/checks.json ([] if there is no manifest). Exits with 2 if it cannot be read."""
    ruta = os.path.join(RAIZ, ".barrilete", "checks.json")
    if not os.path.exists(ruta):
        return []

    def roto(motivo):
        print(f"verify.py: .barrilete/checks.json: {motivo} Run scripts/agents/sync-rules.", file=sys.stderr)
        sys.exit(2)

    try:
        datos = json.load(open(ruta, encoding="utf-8"))
    except (OSError, ValueError) as e:
        roto(f"it cannot be read ({e}).")
    lista = datos.get("checks") if isinstance(datos, dict) else None
    if not isinstance(lista, list):
        roto('it has no "checks" list.')
    for c in lista:
        if not (isinstance(c, dict) and all(isinstance(c.get(k), str) and c.get(k) for k in ("id", "rule", "fail_message"))):
            roto('each check needs "id", "rule" and "fail_message".')
        if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", c["id"]):
            roto(f"the check id {c['id']!r} is not a slug (it names a file in scripts/agents/checks/).")
    return lista


def main():
    args = sys.argv[1:]
    os.chdir(RAIZ)
    ruta_mapa = os.path.join(RAIZ, "docs", "agents-map.json")
    if not os.path.exists(ruta_mapa):
        print("verify.py: docs/agents-map.json does not exist.", file=sys.stderr)
        sys.exit(2)
    reglas = json.load(open(ruta_mapa, encoding="utf-8")).get("verify", [])
    de_reglas = checks_de_reglas()
    if not reglas:
        print("verify.py: the map has no 'verify' section.", file=sys.stderr)
        sys.exit(2)

    rama = rama_base(args)
    if "--base" in args:  # replaced with the resolved one, so the warning is not printed twice
        i = args.index("--base")
        args = args[:i] + args[i + 2:]
    args += ["--base", rama]
    cambiados = archivos_cambiados(args)  # exits with a clear message if the base does not exist
    base = referencia_base(args, rama)

    # A file the change deletes cannot be verified (#274): {files} gets only the changed files that exist. With --pr
    # the files are the PR's, which this checkout may not have, so they are not filtered.
    existen = list(cambiados) if "--pr" in args else [a for a in cambiados if os.path.lexists(a)]
    plan, salteadas = [], []
    for r in reglas:
        # In the ones that always run (no "when"), {files} are all the changed files that exist. A "TODO" rule
        # runs nothing: it is not filtered, so it is still reported as not configured and never skipped.
        filtra = "{files}" in r["run"] and not r["run"].startswith("TODO")
        candidatos = existen if filtra else cambiados
        presentes = set(candidatos)
        tocados = [a for a in candidatos if coincide(a, r["when"])] if r.get("when") else list(candidatos)
        borrados = [a for a in cambiados if a not in presentes and (not r.get("when") or coincide(a, r["when"]))]
        if not tocados and borrados:
            # Only deleted files matched: there is nothing to run {files} on (shellcheck with no files exits with 3).
            salteadas.append((r["name"], borrados))
            continue
        if r.get("always") or tocados:
            motivo = "always" if r.get("always") and not r.get("when") else f"{len(tocados)} file(s): {', '.join(tocados[:3])}"
            cmd = r["run"].replace("{base}", base).replace("{files}", " ".join(shlex.quote(a) for a in tocados))
            plan.append((r["name"], motivo, cmd))

    # The checks of the rules always run: they look at the branch and the PR, not at the files.
    mensajes = {}
    for c in de_reglas:
        nombre = f"check:{c['id']}"
        mensajes[nombre] = (c["rule"], c["fail_message"])
        plan.append((nombre, f"rule {c['rule']}", shlex.join([f"scripts/agents/checks/{c['id']}", "--base", base])))

    print(f"Changes against {base}: {len(cambiados)} file(s). Checks: {len(plan)}.\n")
    for nombre, borrados in salteadas:
        print(f"Skipped: {nombre} (only deleted files matched: {', '.join(borrados[:3])})")
    if salteadas:
        print()
    if "--list" in args:
        for nombre, motivo, cmd in plan:
            print(f"- {nombre} ({motivo})\n    {cmd}")
        return

    resultados = []
    for nombre, motivo, cmd in plan:
        if cmd.startswith("TODO"):
            resultados.append((nombre, "not configured", 0))
            continue
        print(f"▶ {nombre} ({motivo})\n  $ {cmd}", flush=True)
        t0 = time.time()
        ok = subprocess.run(cmd, shell=True).returncode == 0
        resultados.append((nombre, "ok" if ok else "FAILED", time.time() - t0))
        print(flush=True)

    print("Result:")
    for nombre, resultado, seg in resultados:
        print(f"  {resultado:15} {nombre}" + (f" ({seg:.0f}s)" if seg else ""))
    sin_config = [n for n, e, _ in resultados if e == "not configured"]
    if any(e == "FAILED" for _, e, _ in resultados):
        for nombre, (regla, mensaje) in mensajes.items():
            if ("FAILED" == next((e for n, e, _ in resultados if n == nombre), None)):
                print(f"\n{nombre} (rule {regla}): {mensaje}")
        print("\nSome checks fail: fix them before opening the PR. Do not disable them.")
        sys.exit(1)
    if sin_config:
        print(f"\nEverything configured passed, but {', '.join(sin_config)} was not verified: the command is missing in "
              "docs/agents-map.json. Do not say the change is verified.")
        return
    print("\nAll verified.")


if __name__ == "__main__":
    main()
