#!/usr/bin/env python3
"""Moves a project started with --small to the template's full mode.

Usage: python3 scripts/grow.py [--releases] [--template <url or path>]

Clones the template, initializes it in full mode with the data in .agent-kit.json
and, for each file:
  - if the project does not have it → adds it;
  - if the project has it unchanged since the init → replaces it;
  - if the project modified it → does NOT overwrite it: leaves the full version in
    .agent-kit/pending/<path> to integrate by hand (or with the update-docs skill).
It does not commit: the changes stay in the working tree to review them and open a PR.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

PLANTILLA = os.environ.get("AGENT_KIT_TEMPLATE", "https://github.com/lautioliver/barrilete-kit")
NO_TRAER = {"README.md", "README.es.md", "README.en.md", "LICENSE", ".agent-kit.json", "scripts/grow.py", ".github/team.json"}  # the full README explains the template, not the project; the team belongs to the project
PENDIENTES = ".agent-kit/pending"


def salir(msg):
    print(f"grow.py: {msg}", file=sys.stderr)
    sys.exit(1)


def verificar_claves(kit):
    """.agent-kit.json of 0.9 (Spanish keys): update.py migrates it; grow.py does not."""
    if "archivos" in kit and "files" not in kit:
        salir(".agent-kit.json uses the 0.9 keys (proyecto, rama_base, modo, fecha, archivos): this project "
              "was created before the English renames. update.py migrates it (names, keys and labels; see the CHANGELOG): "
              "download scripts/update.py from the new template version outside the repo (for example to /tmp/update.py, "
              "from raw.githubusercontent.com/lautioliver/barrilete-kit/<tag>/scripts/update.py) and run "
              "python3 /tmp/update.py from the project root. After that, grow.py works.")


def sh(*cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        salir(f"{' '.join(cmd[:3])}… failed: {(r.stderr or r.stdout).strip()}")
    return r.stdout


def huella(ruta):
    return hashlib.sha1(open(ruta, "rb").read()).hexdigest()


def archivos(raiz):
    for base, dirs, files in os.walk(raiz):
        dirs[:] = [d for d in dirs if d != ".git"]
        for n in files:
            yield os.path.relpath(os.path.join(base, n), raiz)


def main():
    args = sys.argv[1:]
    plantilla = args[args.index("--template") + 1] if "--template" in args else PLANTILLA
    os.chdir(sh("git", "rev-parse", "--show-toplevel").strip())

    if not os.path.exists(".agent-kit.json"):
        salir("cannot find .agent-kit.json: this repo was not created with the template (or predates grow.py).")
    kit = json.load(open(".agent-kit.json", encoding="utf-8"))
    verificar_claves(kit)
    if kit.get("mode") != "small":
        salir(f"the project is already in {kit.get('mode')} mode.")
    if sh("git", "status", "--porcelain").strip():
        salir("there are uncommitted changes. Commit or stash them before growing.")
    releases = "--releases" in args
    if releases and kit["base_branch"] == "main":
        salir("--releases needs the develop base branch.")

    tmp = tempfile.mkdtemp(prefix="agent-kit-")
    try:
        print(f"Cloning the template from {plantilla}…")
        sh("git", "clone", "-q", "--depth", "1", plantilla, tmp)
        clonado = sh("git", "rev-parse", "HEAD", cwd=tmp).strip()  # the commit the files come from
        etiquetas = [t for t in sh("git", "tag", "--points-at", "HEAD", cwd=tmp).split() if re.fullmatch(r"v\d+\.\d+\.\d+", t)]
        etiqueta = max(etiquetas, key=lambda t: tuple(int(x) for x in t[1:].split("."))).lstrip("v") if etiquetas else None
        init = ["./scripts/init-template.sh", kit["project"], kit["base_branch"]] + (["releases"] if releases else [])
        if kit.get("language"):
            with open(os.path.join(tmp, "scripts", "init-template.sh"), encoding="utf-8") as fh:
                if not re.search(r"^\s*--lang\)", fh.read(), re.M):
                    salir(f"the template at {plantilla} predates --lang, and the project was installed in {kit['language']}.")
            init += ["--lang", kit["language"]]  # grow keeps the language the project was installed in
        sh(*init, cwd=tmp)
        for viejo, nuevo in kit.get("renames", {}).items():  # a workflow the installer put under another name
            if os.path.isfile(os.path.join(tmp, viejo)):
                os.makedirs(os.path.dirname(os.path.join(tmp, nuevo)), exist_ok=True)
                os.replace(os.path.join(tmp, viejo), os.path.join(tmp, nuevo))
        version = json.load(open(os.path.join(tmp, ".agent-kit.json"), encoding="utf-8")).get("version")

        agregados, reemplazados, pendientes, iguales, retenidos, errores = [], [], [], 0, [], []
        registradas = kit.get("files", {})

        # The small mode architecture is project content: it is moved to where full mode expects it.
        movido = None
        if os.path.exists("docs/architecture.md") and not os.path.exists("docs/development/architecture.md"):
            os.makedirs("docs/development", exist_ok=True)
            sh("git", "mv", "docs/architecture.md", "docs/development/architecture.md")
            movido = "docs/architecture.md → docs/development/architecture.md"

        for ruta in sorted(archivos(tmp)):
            if ruta in NO_TRAER:
                continue
            origen = os.path.join(tmp, ruta)
            if movido and ruta == "docs/development/architecture.md":
                continue
            if ruta in kit.get("withheld", []) and not os.path.lexists(ruta):
                retenidos.append(ruta)  # the installer left it out on purpose
                continue
            if not os.path.exists(ruta):
                try:
                    os.makedirs(os.path.dirname(ruta) or ".", exist_ok=True)
                    shutil.copy2(origen, ruta)
                except OSError as e:
                    errores.append(f"{ruta}: {e}")
                    continue
                agregados.append(ruta)
            elif huella(ruta) == huella(origen):
                iguales += 1
            elif registradas.get(ruta) == huella(ruta):
                shutil.copy2(origen, ruta)
                reemplazados.append(ruta)
            else:
                destino = os.path.join(PENDIENTES, ruta)
                os.makedirs(os.path.dirname(destino), exist_ok=True)
                shutil.copy2(origen, destino)
                pendientes.append(ruta)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # Registry: the files the template brought are recorded as "untouched" from now on.
    for ruta in agregados + reemplazados:
        registradas[ruta] = huella(ruta)
    if movido:
        registradas.pop("docs/architecture.md", None)
    kit.update({"mode": "full", "releases": releases, "files": dict(sorted(registradas.items()))})
    if kit.get("ref"):
        # Installed repo: the files now come from the commit grow cloned, so that is the origin. Keeping the
        # install's ref would let update.py go to a tag older than these files and downgrade them. The default
        # branch's VERSION may not match any tag, so the version is only the one of a tag on that commit.
        kit["ref"] = clonado
        kit["version"] = etiqueta
    elif version:
        kit["version"] = version
    json.dump(kit, open(".agent-kit.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    os.remove("scripts/grow.py")

    print(f"\nDone: {len(agregados)} added, {len(reemplazados)} replaced (you had not touched them), "
          f"{iguales} already equal, {len(pendientes)} pending.")
    if movido:
        print(f"Moved: {movido}")
    if pendientes:
        print(f"\nPending: you modified them, so I did not overwrite them. The full version is in {PENDIENTES}/:")
        for p in pendientes:
            print(f"  - {p}")
        print("Integrate what is useful (for example, the new sections of AGENTS.md) and delete the .agent-kit/ folder.")
    if retenidos:
        print("\nLeft out on purpose by the installer (you do not have them, so I did not bring them):")
        for r in retenidos:
            print(f"  - {r}")
    if errores:
        print("\nCould not add (the rest was applied):")
        for e in errores:
            print(f"  - {e}")
    print("\nNext steps:")
    print("  1. python3 scripts/agents/check-docs.py → flags the TODO/ paths of docs/agents-map.json and the")
    print("     links to the old architecture. Fill in the map with the real paths of the project.")
    print("  2. Review the diff, commit and open a PR.")
    print("  3. After the merge, run the Labels workflow to create the new labels.")
    print("  4. The blocking and epic skills need GitHub sub-issues and dependencies enabled.")


if __name__ == "__main__":
    main()
