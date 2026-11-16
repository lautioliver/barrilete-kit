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
Each rule check that runs leaves, as soon as it finishes, one check_run event per rule in .barrilete/learning/events.jsonl of
the main checkout (also from a worktree; the folder carries its own .gitignore; #323, phase 0
of the per-project learning, schema v0 until ADR-007): {"v", "ts", "kind", "check", "rule_id", "outcome" (pass, fail, or
skipped when the check could not verify), "branch", and "task_id" (BK_TASK_DIR, ADR-005) and "harness" (BK_HARNESS, or
claude-code with CLAUDECODE=1) only when they are known}. Only metadata: never the fail_message or the check's output.
Recording is best effort: if it cannot write, it says so on stderr and the exit status does not change.

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
        with open(ruta, encoding="utf-8") as fh:
            datos = json.load(fh)
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


RESULTADO_EVENTO = {"ok": "pass", "FAILED": "fail", "not verified": "skipped"}


def carpeta_registro():
    """.barrilete/learning of the main checkout: from a worktree (an agent of /orchestrate or bk) the log goes to the
    main checkout, because the worktree is deleted when the agent finishes."""
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True)
    comun = r.stdout.strip()
    raiz = os.path.dirname(comun) if r.returncode == 0 and os.path.basename(comun) == ".git" else RAIZ
    return os.path.join(raiz, ".barrilete", "learning")


def contexto_evento():
    """The metadata shared by the check_run events: branch, and task_id and harness only when they are known (never guessed)."""
    ctx = {}
    r = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True)
    rama = r.stdout.strip()
    if r.returncode == 0 and rama and rama != "HEAD":
        ctx["branch"] = rama
    tarea = os.environ.get("BK_TASK_DIR")
    if tarea:
        try:
            with open(os.path.join(tarea, "task.json"), encoding="utf-8") as fh:
                datos = json.load(fh)
            tid = datos.get("id") if isinstance(datos, dict) else None
        except (OSError, ValueError):
            tid = None
        if isinstance(tid, str) and tid:
            ctx["task_id"] = tid
    harness = os.environ.get("BK_HARNESS")
    if harness:  # set: it is the only source, and an invalid one leaves the harness out
        if re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", harness):
            ctx["harness"] = harness
    elif os.environ.get("CLAUDECODE") == "1":
        ctx["harness"] = "claude-code"
    return ctx


class Registro:
    """Appends check_run events as each rule check finishes, so a run that dies halfway keeps what already ran.
    Best effort: a write that fails is said once on stderr and never changes the exit status."""

    def __init__(self, mensajes):
        self.mensajes, self.ctx, self.carpeta, self.roto = mensajes, None, None, False

    def anotar(self, nombre, estado):
        if self.roto or nombre not in self.mensajes or estado not in RESULTADO_EVENTO:
            return
        if self.ctx is None:
            self.ctx, self.carpeta = contexto_evento(), carpeta_registro()
        ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        lineas = "".join(json.dumps({"v": 0, "ts": ts, "kind": "check_run", "check": nombre[len("check:"):],
                                     "rule_id": regla, "outcome": RESULTADO_EVENTO[estado], **self.ctx},
                                    ensure_ascii=False) + "\n" for regla, _ in self.mensajes[nombre])
        try:
            os.makedirs(self.carpeta, exist_ok=True)
            ignorar = os.path.join(self.carpeta, ".gitignore")
            if not os.path.exists(ignorar):  # it ignores itself, even if the project's .gitignore lacks the line
                with open(ignorar, "w", encoding="utf-8") as fh:
                    fh.write("# Generated by scripts/agents/verify.py: the learning log never goes into the repo.\n*\n")
            with open(os.path.join(self.carpeta, "events.jsonl"), "a", encoding="utf-8") as fh:
                fh.write(lineas)
        except OSError as e:
            self.roto = True
            print(f"verify.py: could not record the check runs in {self.carpeta}: {e}", file=sys.stderr)


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
    # Two rules can share a check: it runs once and the message of each rule is shown. They look at the branch's PR, not at
    # the one --pr names, so with --pr they are skipped (and said).
    mensajes = {}
    saltados = "--pr" in args and bool(de_reglas)
    if saltados:
        print("Skipped: rule checks (they look at the PR of this checkout's branch, not at the one --pr names)\n")
    else:
        for c in de_reglas:
            nombre = f"check:{c['id']}"
            if nombre not in mensajes:
                mensajes[nombre] = []
                plan.append((nombre, f"rule {c['rule']}", shlex.join([f"scripts/agents/checks/{c['id']}", "--base", base])))
            mensajes[nombre].append((c["rule"], c["fail_message"]))

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
    registro = Registro(mensajes)
    for nombre, motivo, cmd in plan:
        if cmd.startswith("TODO"):
            resultados.append((nombre, "not configured", 0))
            continue
        print(f"▶ {nombre} ({motivo})\n  $ {cmd}", flush=True)
        t0 = time.time()
        rc = subprocess.run(cmd, shell=True).returncode
        # A rule check exits with 4 when it could not verify (no PR yet, gh down): that is not ok, and it is not a failure.
        estado = "ok" if rc == 0 else "not verified" if rc == 4 and nombre in mensajes else "FAILED"
        resultados.append((nombre, estado, time.time() - t0))
        registro.anotar(nombre, estado)
        print(flush=True)

    if saltados:
        resultados.append(("rule checks (skipped with --pr)", "not verified", 0))
    print("Result:")
    for nombre, resultado, seg in resultados:
        print(f"  {resultado:15} {nombre}" + (f" ({seg:.0f}s)" if seg else ""))
    sin_config = [n for n, e, _ in resultados if e in ("not configured", "not verified")]
    if any(e == "FAILED" for _, e, _ in resultados):
        for nombre, reglas_del_check in mensajes.items():
            if "FAILED" == next((e for n, e, _ in resultados if n == nombre), None):
                for regla, mensaje in reglas_del_check:
                    print(f"\n{nombre} (rule {regla}): {mensaje}")
        print("\nSome checks fail: fix them before opening the PR. Do not disable them.")
        sys.exit(1)
    if sin_config:
        print(f"\nEverything that ran passed, but {', '.join(sin_config)} was not verified (a command missing in "
              "docs/agents-map.json, or a rule check that could not read the PR yet). Do not say the change is verified.")
        return
    print("\nAll verified.")


if __name__ == "__main__":
    main()
