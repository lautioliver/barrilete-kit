#!/usr/bin/env python3
"""Cross-checks the changed files with docs/agents-map.json.

Says which documents to review and which sensitive paths were touched.
Usage:
  agents_map.py                      # branch changes against the base (BASE, <BASE_BRANCH> or the remote default)
  agents_map.py --base develop       # against another base
  agents_map.py --pr 42              # files of a PR
  agents_map.py --json               # JSON output
"""
import json
import os
import re
import subprocess
import sys

RAIZ = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."


def glob_a_regex(glob):
    """Git-style glob: ** crosses directories, * does not. A leading "?" marks the path as
    optional (check-docs does not fail if it is missing); it is ignored for matching."""
    glob = glob[1:] if glob.startswith("?") else glob
    r, i = "", 0
    while i < len(glob):
        if glob.startswith("**/", i):
            r += "(?:.*/)?"
            i += 3
        elif glob.startswith("**", i):
            r += ".*"
            i += 2
        elif glob[i] == "*":
            r += "[^/]*"
            i += 1
        else:
            r += re.escape(glob[i])
            i += 1
    return re.compile(r + "$")


def coincide(ruta, globs):
    return [g for g in globs if glob_a_regex(g).match(ruta)]


def salir(mensaje):
    """Explained error, no traceback: an agent that sees a stack trace tends to improvise."""
    print(f"agents_map.py: {mensaje}", file=sys.stderr)
    sys.exit(2)


def existe(ref):
    return subprocess.run(["git", "rev-parse", "-q", "--verify", f"{ref}^{{commit}}"],
                          capture_output=True).returncode == 0


def rama_base(args):
    """--base, BASE or the value the init leaves. In the uninitialized template (the value
    is still a <…> placeholder), uses the remote default branch and says so."""
    base = args[args.index("--base") + 1] if "--base" in args else os.environ.get("BASE", "<BASE_BRANCH>")
    if not base.startswith("<"):
        return base
    r = subprocess.run(["git", "symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"],
                       capture_output=True, text=True)
    defecto = r.stdout.strip().removeprefix("origin/")
    if not defecto:
        r = subprocess.run(["git", "ls-remote", "--symref", "origin", "HEAD"], capture_output=True, text=True)
        m = re.search(r"^ref: refs/heads/(\S+)\s+HEAD", r.stdout, re.M)
        defecto = m.group(1) if m else ""
    if not defecto:
        salir(f"the base branch is not configured ({base}): the template was not initialized and I could not "
              "read the default branch of origin. Pass --base <branch> or set BASE.")
    print(f"Warning: the base branch is not configured ({base}); using the remote default branch, "
          f"{defecto}. For another one, pass --base or BASE.", file=sys.stderr)
    return defecto


def archivos_cambiados(args):
    if "--pr" in args:
        n = args[args.index("--pr") + 1]
        r = subprocess.run(["gh", "pr", "diff", n, "--name-only"], capture_output=True, text=True)
        if r.returncode != 0:
            salir(f"could not read PR #{n} ({r.stderr.strip() or 'gh failed'}). Does it exist, and is gh authenticated?")
        return [l for l in r.stdout.splitlines() if l]
    base = rama_base(args)
    ref = f"origin/{base}" if existe(f"origin/{base}") else base
    if not existe(ref):
        salir(f"cannot find branch '{base}' or 'origin/{base}'. "
              f"Run 'git fetch origin {base}' or pass --base <branch>.")
    # With -z the names arrive literal: without -z, git quotes and escapes the ones with
    # spaces or accents, and they match no glob in the map.
    r = subprocess.run(["git", "diff", "--name-only", "-z", f"{ref}...HEAD"], capture_output=True, text=True)
    if r.returncode != 0:
        salir(f"git diff against '{ref}' failed: {r.stderr.strip()}. Do they share history? Try --base.")
    nombres = set(r.stdout.split("\0"))
    # With -uall, a new untracked folder is listed file by file (otherwise, only "folder/").
    entradas = iter(subprocess.run(["git", "status", "--porcelain", "-z", "-uall"], capture_output=True, text=True).stdout.split("\0"))
    for e in entradas:
        nombres.add(e[3:])
        if "R" in e[:2] or "C" in e[:2]:
            next(entradas, None)  # rename or copy: the next entry is the old name
    return sorted(n for n in nombres if n)


# Claude Code loads every .md in .claude/agents/ as an agent, so the Spanish sibling of an agent cannot live
# next to it (two agents with the same name): it lives in .claude/i18n/agents/<name>.es.md (ADR-001, R-1).
AGENTES_EN, AGENTES_ES = ".claude/agents/", ".claude/i18n/agents/"


def hermano_de_idioma(ruta):
    """X.md ↔ X.es.md (ADR-001), or None if it is not a prose file. The agents are the exception:
    .claude/agents/<name>.md ↔ .claude/i18n/agents/<name>.es.md."""
    if ruta.endswith(".es.md"):
        if ruta.startswith(AGENTES_ES) and "/" not in ruta[len(AGENTES_ES):]:
            return AGENTES_EN + ruta[len(AGENTES_ES):-len(".es.md")] + ".md"
        return ruta[:-len(".es.md")] + ".md"
    if ruta.endswith(".md"):
        if ruta.startswith(AGENTES_EN) and "/" not in ruta[len(AGENTES_EN):]:
            return AGENTES_ES + ruta[len(AGENTES_EN):-len(".md")] + ".es.md"
        return ruta[:-len(".md")] + ".es.md"
    return None


def pares_sin_actualizar(cambiados):
    """(changed, sibling) for each X.md / X.es.md that exists and changed without its sibling:
    one language went ahead of the other (check-docs.py only compares the structure)."""
    pares = []
    for a in cambiados:
        h = hermano_de_idioma(a)
        if h and h not in cambiados and os.path.exists(os.path.join(RAIZ, a)) and os.path.exists(os.path.join(RAIZ, h)):
            pares.append((a, h))
    return pares


def main():
    args = sys.argv[1:]
    with open(os.path.join(RAIZ, "docs", "agents-map.json")) as f:
        mapa = json.load(f)
    cambiados = archivos_cambiados(args)

    docs = {}
    for regla in mapa.get("docs", []):
        tocados = [a for a in cambiados if coincide(a, regla["when"])]
        if not tocados:
            continue
        for d in regla["review"]:
            entrada = docs.setdefault(d, {"reasons": [], "files": [], "already_changed": d in cambiados})
            if regla["reason"] not in entrada["reasons"]:
                entrada["reasons"].append(regla["reason"])
            entrada["files"] += [a for a in tocados if a not in entrada["files"]]

    sensibles = []
    for s in mapa.get("sensitive", []):
        tocados = [a for a in cambiados if coincide(a, s["paths"])]
        if tocados:
            sensibles.append({"type": s["type"], "files": tocados, "skill": s.get("skill")})

    sin_par = pares_sin_actualizar(cambiados)
    if "--json" in args:
        print(json.dumps({"changed": cambiados, "docs": docs, "sensitive": sensibles,
                          "unpaired": [{"changed": a, "sibling": h} for a, h in sin_par]}, ensure_ascii=False, indent=2))
        return

    print(f"Changed files: {len(cambiados)}")
    print("\n## Docs to review")
    if not docs:
        print("_None according to the map._")
    for d, e in docs.items():
        estado = "already modified in this change" if e["already_changed"] else "NOT MODIFIED"
        print(f"- {d} ({estado}) — {'; '.join(e['reasons'])}: {', '.join(e['files'][:5])}")
    print("\n## Language siblings")
    if not sin_par:
        print("_Every X.md / X.es.md that changed has its sibling in this change._")
    for a, h in sin_par:
        print(f"- {a} changed but its sibling {h} did not (UNPAIRED): update it or say in the PR why it can wait.")
    print("\n## Sensitive paths touched")
    if not sensibles:
        print("_None._")
    for s in sensibles:
        extra = f" → use the {s['skill']} skill" if s["skill"] else ""
        print(f"- {s['type']}: {', '.join(s['files'][:5])}{extra}")
    if sensibles:
        print("\nTouching sensitive paths requires approval (AGENTS.md, Autonomy) and running /security-review.")


if __name__ == "__main__":
    main()
