#!/usr/bin/env python3
"""Brings a new version of the template into the project.

Usage: python3 scripts/update.py [--version vX.Y.Z] [--template <url or path>]

Clones the template, initializes it with the data in .agent-kit.json (same mode, base branch and
date) at the requested version (by default, the latest vX.Y.Z tag; without tags, the default branch) and
also at the project's origin version. For each template file:
  - if the project does not have it → adds it (unless the project deleted it);
  - if the project did not touch it → replaces it (content and permissions);
  - if it touched it → merges it with `git merge-file` against the origin version. If the merge has
    conflicts, it does NOT overwrite it: it leaves the result with markers in .agent-kit/pending/<path>;
  - if the template removed it → deletes it if the project did not touch it; if it did, it warns.
Without an origin version (projects from before versions existed) it cannot merge: what was modified
goes whole to .agent-kit/pending/, as grow.py does.
It does not commit: the changes stay in the working tree to review them and open a PR.
"""
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

PLANTILLA = os.environ.get("AGENT_KIT_TEMPLATE", "https://github.com/lautioliver/barrilete-kit")
# The project's, even if the template has them too: the template README explains the template itself.
NO_TRAER = {"README.md", "README.en.md", "LICENSE", ".agent-kit.json", ".github/team.json"}
PENDIENTES = ".agent-kit/pending"
USO = "Usage: python3 scripts/update.py [--version vX.Y.Z] [--template <url or path>]"


def salir(msg):
    print(f"update.py: {msg}", file=sys.stderr)
    sys.exit(1)


def verificar_claves(kit):
    """.agent-kit.json de 0.9 (claves en español): error claro; la migración es el issue #116."""
    if "archivos" in kit and "files" not in kit:
        salir(".agent-kit.json uses the 0.9 keys (proyecto, rama_base, modo, fecha, archivos): this project "
              "was created with a version before the English renames. Migrating it is not supported by "
              "this version of the script yet (issue #116).")


def sh(*cmd, cwd=None, env=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, env=env)
    if r.returncode != 0:
        salir(f"{' '.join(cmd[:3])}… failed: {(r.stderr or r.stdout).strip()}")
    return r


def huella(ruta):
    with open(ruta, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()


def ejecutable(ruta):
    return bool(os.stat(ruta).st_mode & stat.S_IXUSR)


def archivos(raiz):
    for base, dirs, files in os.walk(raiz):
        dirs[:] = [d for d in dirs if d != ".git"]
        for n in files:
            yield os.path.relpath(os.path.join(base, n), raiz)


def numero(version):
    """(X, Y, Z) of "X.Y.Z" or "vX.Y.Z", ignoring suffixes like -rc.1; None if it is not understood."""
    m = re.match(r"v?(\d+)\.(\d+)\.(\d+)", version or "")
    return tuple(int(x) for x in m.groups()) if m else None


def opcion(args, nombre):
    if nombre not in args:
        return None
    i = args.index(nombre)
    if i + 1 >= len(args) or args[i + 1].startswith("--"):
        salir(f"{nombre} needs a value.\n{USO}")
    return args[i + 1]


def tags(clon):
    nombres = sh("git", "tag", "--list", "v*", cwd=clon).stdout.split()
    return sorted((t for t in nombres if re.fullmatch(r"v\d+\.\d+\.\d+", t)), key=numero)


def inicializar(clon, ref, destino, kit):
    """The template at `ref`, initialized with the project data, in `destino`."""
    os.makedirs(destino)
    tar = subprocess.run(["git", "archive", ref], cwd=clon, capture_output=True)
    if tar.returncode != 0:
        salir(f"cannot find {ref} in the template: {tar.stderr.decode().strip()}")
    subprocess.run(["tar", "-xf", "-"], cwd=destino, input=tar.stdout, check=True)
    sh("git", "init", "-q", cwd=destino)
    # The origin version may predate the renames: it has init-plantilla.sh, --chico and AGENT_KIT_FECHA.
    nuevo = os.path.exists(os.path.join(destino, "scripts", "init-template.sh"))
    args = ["./scripts/init-template.sh" if nuevo else "./scripts/init-plantilla.sh", kit["project"], kit["base_branch"]]
    if kit.get("releases"):
        args.append("releases")
    if kit.get("mode") == "small":
        args.append("--small" if nuevo else "--chico")
    # --lang arrived after the renames: an origin version without it installs in English only.
    if kit.get("language") and nuevo:
        with open(os.path.join(destino, "scripts", "init-template.sh"), encoding="utf-8") as fh:
            if re.search(r"^\s*--lang\)", fh.read(), re.M):  # the option branch of its argument parser
                args += ["--lang", kit["language"]]
    sh(*args, cwd=destino, env=dict(os.environ, **{"AGENT_KIT_DATE" if nuevo else "AGENT_KIT_FECHA": kit.get("date", "")}))


def changelog(clon, ref, desde):
    """The CHANGELOG.md sections newer than `desde`."""
    r = subprocess.run(["git", "show", f"{ref}:CHANGELOG.md"], cwd=clon, capture_output=True, text=True)
    if r.returncode != 0:
        return ""
    nuevas = []
    for s in re.split(r"(?m)^(?=## )", r.stdout):
        n = numero(s[3:].strip("[ ")) if s.startswith("## ") else None
        if n and (desde is None or n > desde):
            nuevas.append(s.rstrip())
    return "\n\n".join(nuevas)


def fusionar(proyecto, base, nueva):
    """git merge-file: (merged text or None if it cannot be done, has_conflicts)."""
    r = subprocess.run(["git", "merge-file", "-p", "-L", "project", "-L", "previous version", "-L",
                        "new version", proyecto, base, nueva], capture_output=True)
    if r.returncode < 0 or r.returncode > 127:  # binaries or error: 255
        return None, True
    return r.stdout, r.returncode != 0


def planear(nueva, base, registradas, retenidos=()):
    """What to do with each file, without touching anything yet: list of (action, path, data)."""
    en_nueva = set(archivos(nueva)) - NO_TRAER

    def sin_tocar(ruta):
        """The same as the template left it: in the origin version or when the project was created (which
        can be after the tag, if it was created from main)."""
        if registradas.get(ruta) == huella(ruta):
            return True
        origen = os.path.join(base, ruta) if base else None
        return bool(origen and os.path.exists(origen) and huella(origen) == huella(ruta))

    plan = []
    for ruta in sorted(en_nueva):
        nuevo = os.path.join(nueva, ruta)
        origen = os.path.join(base, ruta) if base else None
        if not os.path.lexists(ruta):
            # The project had it (registry) and no longer does: it deleted it on purpose.
            # `retenidos`: the installer left it out on purpose (and the project still does not have it).
            plan.append(("retener" if ruta in retenidos else "saltar" if ruta in registradas else "agregar", ruta, None))
        elif not os.path.isfile(ruta):
            plan.append(("conflicto", ruta, None))  # in the project it is a directory or something else
        elif huella(ruta) == huella(nuevo):
            if ejecutable(ruta) != ejecutable(nuevo) and sin_tocar(ruta):
                plan.append(("permisos", ruta, None))
            else:
                plan.append(("igual", ruta, None))
        elif sin_tocar(ruta):
            plan.append(("reemplazar", ruta, None))
        elif origen and os.path.exists(origen):
            texto, conflicto = fusionar(ruta, origen, nuevo)
            plan.append(("conflicto" if conflicto else "fusionar", ruta, texto))
        else:
            plan.append(("pendiente", ruta, None))
    # What the template removed: it was in the origin version or in the registry, and is no longer there.
    antes = (set(archivos(base)) if base else set()) | set(registradas)
    for ruta in sorted(antes - en_nueva - NO_TRAER):
        if os.path.isfile(ruta):
            plan.append(("borrar" if sin_tocar(ruta) else "conservar", ruta, None))
    return plan


def renombrar(raiz, renombres):
    """Applies the project's renames (a workflow installed as barrilete-<name>.yml) to an initialized template."""
    for viejo, nuevo in renombres.items():
        if os.path.isfile(os.path.join(raiz, viejo)):
            os.makedirs(os.path.dirname(os.path.join(raiz, nuevo)), exist_ok=True)
            os.replace(os.path.join(raiz, viejo), os.path.join(raiz, nuevo))


def aplicar(plan, nueva):
    """Applies the plan. An error in one file does not stop the rest: it is noted."""
    hechos, errores = {}, []
    for accion, ruta, texto in plan:
        nuevo = os.path.join(nueva, ruta)
        try:
            if accion in ("agregar", "reemplazar"):
                os.makedirs(os.path.dirname(ruta) or ".", exist_ok=True)
                shutil.copy2(nuevo, ruta)
            elif accion == "permisos":
                shutil.copymode(nuevo, ruta)
            elif accion == "fusionar":
                with open(ruta, "wb") as f:
                    f.write(texto)
                shutil.copymode(nuevo, ruta)
            elif accion in ("conflicto", "pendiente"):
                destino = os.path.join(PENDIENTES, ruta)
                os.makedirs(os.path.dirname(destino), exist_ok=True)
                if texto is None:
                    shutil.copy2(nuevo, destino)
                else:
                    with open(destino, "wb") as f:
                        f.write(texto)
            elif accion == "borrar":
                os.remove(ruta)
        except OSError as e:
            errores.append(f"{ruta}: {e}")
            continue
        hechos.setdefault(accion, []).append(ruta)
    return hechos, errores


def main():
    args = sys.argv[1:]
    plantilla = opcion(args, "--template") or PLANTILLA
    if os.path.exists(plantilla):  # a local path, relative to where it was run
        plantilla = os.path.abspath(plantilla)
    pedida = opcion(args, "--version")
    os.chdir(sh("git", "rev-parse", "--show-toplevel").stdout.strip())

    if not os.path.exists(".agent-kit.json"):
        salir("cannot find .agent-kit.json: this repo was not created with the template (or predates that registry).")
    with open(".agent-kit.json", encoding="utf-8") as f:
        kit = json.load(f)
    verificar_claves(kit)
    if sh("git", "status", "--porcelain").stdout.strip():
        salir("there are uncommitted changes. Commit or stash them before updating.")
    if os.path.isdir(PENDIENTES) and any(archivos(PENDIENTES)):
        salir(f"there are files left in {PENDIENTES}/ from a previous update. Integrate them and delete the folder "
              "before updating again.")
    actual = kit.get("version")

    tmp = tempfile.mkdtemp(prefix="agent-kit-")
    try:
        clon = os.path.join(tmp, "clon")
        print(f"Cloning the template from {plantilla}…")
        sh("git", "clone", "-q", plantilla, clon)
        disponibles = tags(clon)
        if pedida:
            ref = pedida if pedida.startswith("v") else f"v{pedida}"
            if ref not in disponibles:
                salir(f"the template does not have version {ref}. Versions: {', '.join(disponibles) or 'none'}.")
        else:
            ref = disponibles[-1] if disponibles else "HEAD"
        r = subprocess.run(["git", "show", f"{ref}:VERSION"], cwd=clon, capture_output=True, text=True)
        objetivo = r.stdout.strip() if r.returncode == 0 else None
        if numero(objetivo) and numero(actual):
            if numero(objetivo) < numero(actual):
                salir(f"{ref} ({objetivo}) is older than the project version ({actual}). "
                      "update.py does not go back.")
            if objetivo == actual and ref != "HEAD":
                print(f"The project is already at template version {actual}. Nothing to update.")
                return
        instalado = kit.get("ref")  # the commit install.py installed from (a repo that had its own code)
        destino = sh("git", "rev-parse", f"{ref}^{{commit}}", cwd=clon).stdout.strip()
        if instalado:
            if destino == instalado:
                print(f"The project is already at the template commit {instalado[:9]}. Nothing to update.")
                return
            if subprocess.run(["git", "cat-file", "-e", f"{instalado}^{{commit}}"], cwd=clon,
                              capture_output=True).returncode != 0:
                salir(f"the template at {plantilla} does not have the commit this project was installed from "
                      f"({instalado[:9]}): it is another template or a fork with another history. Updating from it "
                      "could downgrade the kit. Use the template the project came from (--template).")
            r = subprocess.run(["git", "merge-base", "--is-ancestor", instalado, destino], cwd=clon,
                               capture_output=True, text=True)
            if r.returncode not in (0, 1):
                salir(f"cannot check that {ref} contains the commit this project was installed from "
                      f"({instalado[:9]}): {r.stderr.strip() or 'git merge-base failed'}")
            if r.returncode == 1:
                salir(f"{ref} does not contain the commit this project was installed from ({instalado[:9]}): going to "
                      f"it would downgrade the kit. Wait for a release that includes it, or use a newer --version "
                      f"(versions: {', '.join(disponibles) or 'none'}).")
        notas = changelog(clon, ref, numero(actual)) if actual or not instalado else ""

        nueva = os.path.join(tmp, "nueva")
        inicializar(clon, ref, nueva, kit)
        renombrar(nueva, kit.get("renames", {}))
        base = None
        if instalado:  # it exists: it was checked above
            base = os.path.join(tmp, "base")
            inicializar(clon, instalado, base, kit)
            renombrar(base, kit.get("renames", {}))
        elif actual and f"v{actual}" in disponibles:
            base = os.path.join(tmp, "base")
            inicializar(clon, f"v{actual}", base, kit)
            renombrar(base, kit.get("renames", {}))

        registradas = kit.get("files", {})
        plan = planear(nueva, base, registradas, set(kit.get("withheld", [])))
        hechos, errores = aplicar(plan, nueva)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    for accion in ("agregar", "reemplazar", "permisos"):
        for ruta in hechos.get(accion, []):
            registradas[ruta] = huella(ruta)
    for ruta in hechos.get("borrar", []):
        registradas.pop(ruta, None)
    kit["files"] = dict(sorted(registradas.items()))
    if instalado:
        # The commit is the source of truth; a version only if the target is a tag (the default branch's VERSION
        # may not match any).
        kit["ref"] = destino
        kit["version"] = objetivo if ref != "HEAD" else None
    elif objetivo:
        kit["version"] = objetivo
    if kit.get("withheld"):
        kit["withheld"] = [r for r in kit["withheld"] if not os.path.lexists(r)]
        if not kit["withheld"]:
            del kit["withheld"]
    with open(".agent-kit.json", "w", encoding="utf-8") as f:
        json.dump(kit, f, ensure_ascii=False, indent=2)
        f.write("\n")

    n = {a: len(hechos.get(a, [])) for a in ("agregar", "reemplazar", "permisos", "fusionar", "igual", "borrar")}
    print(f"\nDone: from {actual or 'an unnumbered version'} to {objetivo or ref}.")
    print(f"  {n['agregar']} added, {n['reemplazar'] + n['permisos']} replaced (you had not touched them), "
          f"{n['fusionar']} merged, {n['igual']} already equal, {n['borrar']} deleted.")
    for titulo, accion in (("Merged (review the diff)", "fusionar"),
                           (f"With conflicts: I did not overwrite them, the merge with markers is in {PENDIENTES}/", "conflicto"),
                           ("Modified by you, with no origin version to merge: the new version is in "
                            f"{PENDIENTES}/", "pendiente"),
                           ("The template removed them, but you modified them: decide whether to delete them", "conservar"),
                           ("You had deleted them and the template changed them: I did not bring them", "saltar"),
                           ("Left out on purpose by the installer (you do not have them, so I did not bring them; "
                            f"the kit's version is in {PENDIENTES}/ only if you had a file of your own)", "retener")):
        if hechos.get(accion):
            print(f"\n{titulo}:")
            for ruta in hechos[accion]:
                print(f"  - {ruta}")
    if errores:
        print("\nCould not apply (the rest was applied):")
        for e in errores:
            print(f"  - {e}")
    if notas:
        print(f"\nWhat changed in the template:\n\n{notas}")
    print("\nNext steps:")
    if hechos.get("conflicto") or hechos.get("pendiente"):
        print(f"  1. Integrate what is in {PENDIENTES}/ now and delete the folder. The next update starts from")
        print(f"     version {objetivo or ref}: what you do not integrate from this one will not show up again.")
    else:
        print("  1. Nothing pending to integrate by hand.")
    print("  2. python3 scripts/agents/check-docs.py, and review the diff.")
    print("  3. Commit and open a PR. If .github/labels.yml changed, run the Labels workflow after the merge.")


if __name__ == "__main__":
    main()
