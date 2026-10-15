#!/usr/bin/env python3
"""Last guard before the PR: depending on what changed, decides what to verify and runs it.

Checks are configured in the "verify" section of docs/agents-map.json:
  {"name": "tests", "always": true, "run": "npm test"}
  {"name": "migrations", "when": ["db/schema/**"], "run": "…"}
A check runs if it is "always" or if any changed file matches "when".
In "run" you can use {base} (the base branch reference, e.g. origin/main)
and {files} (the matching changed files, quoted).
A "run" that starts with "TODO" is reported as not configured and is not executed.

Usage:
  verify.py                 # against the base branch (BASE, <BASE_BRANCH> or the remote default)
  verify.py --base develop
  verify.py --list          # shows what would run, without running anything
Exits with 1 if any check fails.
"""
import json
import os
import shlex
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agents_map import RAIZ, archivos_cambiados, coincide, existe, rama_base  # noqa: E402


def referencia_base(args, base):
    return f"origin/{base}" if existe(f"origin/{base}") else base


def main():
    args = sys.argv[1:]
    os.chdir(RAIZ)
    ruta_mapa = os.path.join(RAIZ, "docs", "agents-map.json")
    if not os.path.exists(ruta_mapa):
        print("verify.py: docs/agents-map.json does not exist.", file=sys.stderr)
        sys.exit(2)
    reglas = json.load(open(ruta_mapa, encoding="utf-8")).get("verify", [])
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

    plan = []
    for r in reglas:
        # In the ones that always run (no "when"), {files} are all the changed files.
        tocados = [a for a in cambiados if coincide(a, r["when"])] if r.get("when") else list(cambiados)
        if r.get("always") or tocados:
            motivo = "always" if r.get("always") and not r.get("when") else f"{len(tocados)} file(s): {', '.join(tocados[:3])}"
            cmd = r["run"].replace("{base}", base).replace("{files}", " ".join(shlex.quote(a) for a in tocados))
            plan.append((r["name"], motivo, cmd))

    print(f"Changes against {base}: {len(cambiados)} file(s). Checks: {len(plan)}.\n")
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
        print("\nSome checks fail: fix them before opening the PR. Do not disable them.")
        sys.exit(1)
    if sin_config:
        print(f"\nEverything configured passed, but {', '.join(sin_config)} was not verified: the command is missing in "
              "docs/agents-map.json. Do not say the change is verified.")
        return
    print("\nAll verified.")


if __name__ == "__main__":
    main()
