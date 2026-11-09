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
MAPA = "docs/agents-map.json"
# RED_AGREGADA and RED_GUIA (and `con_red`, in update.py and install.py) are copies in update.py, grow.py and install.py: they run on their own, so change all three.
RED_AGREGADA = ("docs/agents-map.json had no `red` section (ADR-002 D8): I added the kit's `bash` entry, which runs the test-*.sh "
                "files a commit adds or changes. red.sh needs the section and rejects a map without it.")
RED_GUIA = ("To configure your stack's entry, see docs/guides/red-per-runner.md (in the kit, "
            "https://github.com/lautioliver/barrilete-kit, if your project does not have the guides).")


# The glossary and the map of contexts (ADR-003 D2, D5). LINK, `enlaza` and `avisos_enlaces` are copies in update.py, grow.py and install.py: they run on their own, so change all of them.
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
# docs/ of the small profile → where the full profile keeps them (D2).
GLOSARIO_Y_CONTEXTOS = (("docs/glossary.md", "docs/reference/glossary.md"), ("docs/contexts.md", "docs/reference/contexts.md"))
SIN_RUTA_DEPENDE = {"", "-", "—", "none", "n/a", "ninguno", "ninguna", "ningún"}


def enlaza(indice, ruta):
    """True if the index links ruta (any spelling: ./a.md, <a.md>, a.md#section; not in a code block or inline code)."""
    try:
        with open(indice, encoding="utf-8") as f:
            texto = re.sub(r"```.*?```", "", f.read(), flags=re.S)
    except (OSError, UnicodeDecodeError):
        return True  # it cannot be read: there is nothing to say about it
    for linea in texto.splitlines():
        for d in LINK.findall(re.sub(r"`[^`]*`", "", linea)):
            d = d.strip("<>")
            local = d.split("#")[0]
            if not re.match(r"^[a-z]+:", d) and local and os.path.normpath(os.path.join(os.path.dirname(indice), local)) == os.path.normpath(ruta):
                return True
    return False


def avisos_enlaces(chico, existe=os.path.exists):
    """What the docs indexes do not link of the glossary and the map of contexts: the text of a warning for each one that
    exists (`existe`) and is not linked. As check-docs.py reads them: --small in docs/glossary.md and docs/contexts.md, from the READMEs;
    full in docs/reference/, from the READMEs and the llms.txt."""
    rutas = ["docs/glossary.md", "docs/contexts.md"] if chico else ["docs/reference/glossary.md", "docs/reference/contexts.md"]
    indices = ["docs/README.md", "docs/README.es.md"] + ([] if chico else ["docs/llms.txt", "docs/llms.es.txt"])
    avisos = []
    for ruta in rutas:
        for indice in indices:
            if existe(ruta) and os.path.exists(indice) and not enlaza(indice, ruta):
                titulo = "Glossary" if "glossary" in ruta else "Contexts"
                avisos.append(f"{indice} does not link {ruta}: add a link to it, for example "
                              f"[{titulo}]({os.path.relpath(ruta, os.path.dirname(indice))})")
    return avisos


def completar_mapa(texto, kit):
    """The full map with the project's sections on top: what the project had (its `red` above all) is kept and the
    sections it lacks come from the kit. ValueError if either is not a JSON object."""
    try:
        mio, completo = json.loads(texto), json.loads(kit)
    except ValueError as e:
        raise ValueError(f"it is not valid JSON ({e})")
    if not isinstance(mio, dict) or not isinstance(completo, dict):
        raise ValueError("it is not a JSON object")
    return json.dumps({**completo, **mio}, ensure_ascii=False, indent=2) + "\n", "red" not in mio


def contextos_de_tabla(texto):
    """The `contexts` entries of the table of docs/contexts.md of the small profile (Context | Responsibility | Own terms |
    Depends on | Code paths): (list, None), or (None, why) if a row cannot be passed. The TODO template row is skipped, so an
    unfilled table gives an empty list. A path of a folder that exists becomes `folder/**`; the others stay as written."""
    # The table is the first block of `|` lines with 5 columns whose second line is the separator (there may be a legend table before it).
    bloques, actual = [], []
    for l in texto.splitlines() + [""]:
        if l.strip().startswith("|"):
            actual.append([c.strip() for c in l.strip().strip("|").split("|")])
        elif actual:
            bloques.append(actual)
            actual = []
    filas = []
    for b in bloques:
        if len(b) >= 2 and len(b[0]) == 5 and all(re.fullmatch(r":?-+:?", c) for c in b[1]):
            filas = b[2:]
            break
    contextos = []
    for f in filas:
        if len(f) < 5:
            return None, f"a row of the table has {len(f)} columns, not 5"
        nombre = f[0].strip("`")
        if nombre.startswith("TODO"):
            continue
        if any(c.startswith("TODO") for c in f):
            return None, f"the row of '{nombre}' still has a TODO"
        rutas = []
        for r in (x.strip().strip("`").strip() for x in f[4].split(",")):
            if r:
                carpeta = not re.search(r"[*?\[]", r) and (r.endswith("/") or os.path.isdir(r))  # `src/a/`, or `src/a` that exists
                rutas.append(r.rstrip("/") + "/**" if carpeta else r)
        if not nombre or not rutas:
            return None, f"the row of '{nombre or '?'}' has no name or no code paths"
        depende = [d for d in (x.strip().strip("`").strip() for x in f[3].split(",")) if d.lower() not in SIN_RUTA_DEPENDE]
        contextos.append({"name": nombre, "paths": rutas, "depends_on": depende})
    return contextos, None


def pasar_contextos(contextos):
    """Writes `contextos` as the `contexts` section of the map; None if it did, or why it could not (not a JSON object,
    or it already has contexts of its own: those are not overwritten)."""
    try:
        with open(MAPA, encoding="utf-8") as f:
            mapa = json.load(f)
        if not isinstance(mapa, dict):
            return "the map is not a JSON object"
        if mapa.get("contexts"):
            return "the map already has contexts of its own"
        mapa["contexts"] = contextos
        with open(MAPA, "w", encoding="utf-8") as f:
            f.write(json.dumps(mapa, ensure_ascii=False, indent=2) + "\n")
    except (ValueError, OSError) as e:
        return f"the map cannot be read or written ({e})"
    return None


def salir(msg):
    print(f"grow.py: {msg}", file=sys.stderr)
    sys.exit(1)


def verificar_claves(kit):
    """.agent-kit.json of 0.9 (Spanish keys): update.py migrates it; grow.py does not."""
    if any(k in kit for k in ("proyecto", "rama_base", "modo", "fecha", "archivos")):
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
        if kit.get("flow_line"):  # and the flow line it chose (#181)
            init.append("--flow-line")
        sh(*init, cwd=tmp)
        for viejo, nuevo in kit.get("renames", {}).items():  # a workflow the installer put under another name
            if os.path.isfile(os.path.join(tmp, viejo)):
                os.makedirs(os.path.dirname(os.path.join(tmp, nuevo)), exist_ok=True)
                os.replace(os.path.join(tmp, viejo), os.path.join(tmp, nuevo))
        version = json.load(open(os.path.join(tmp, ".agent-kit.json"), encoding="utf-8")).get("version")

        agregados, reemplazados, pendientes, iguales, retenidos, errores = [], [], [], 0, [], []
        completados, red_agregada = [], False
        sin_tocar, sin_mover = [], []
        registradas = kit.get("files", {})

        # The small mode architecture is project content: it is moved to where full mode expects it.
        movido = None
        if os.path.exists("docs/architecture.md") and not os.path.exists("docs/development/architecture.md"):
            os.makedirs("docs/development", exist_ok=True)
            sh("git", "mv", "docs/architecture.md", "docs/development/architecture.md")
            movido = "docs/architecture.md → docs/development/architecture.md"

        # The glossary and the contexts of the small profile (ADR-003 D2). What the project did not touch goes away (the full
        # profile brings its own, with more columns and sections); what it wrote moves to docs/reference/ (the full version of
        # that file goes to pending like any file the project modified), unless something is already there.
        tabla, ruta_tabla, tabla_movida = None, "docs/contexts.md", []
        if os.path.isfile("docs/contexts.md"):
            with open("docs/contexts.md", encoding="utf-8", errors="replace") as f:
                tabla = f.read()
        for viejo, nuevo in GLOSARIO_Y_CONTEXTOS:
            if not os.path.isfile(viejo):
                continue
            if registradas.get(viejo) == huella(viejo):
                os.remove(viejo)
                registradas.pop(viejo)
                sin_tocar.append(viejo)
            elif os.path.exists(nuevo):
                sin_mover.append((viejo, nuevo))
                if viejo == "docs/contexts.md":
                    tabla = None  # the project has two; which one is right is its call: nothing goes to the map from the old one
            else:
                os.makedirs(os.path.dirname(nuevo), exist_ok=True)
                sh("git", "mv", viejo, nuevo)
                tabla_movida.append(f"{viejo} → {nuevo}")
                if viejo == "docs/contexts.md":
                    ruta_tabla = nuevo

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
                if ruta == MAPA:  # the small map has only `red`: it is completed, not left for the project to merge
                    try:
                        with open(ruta, encoding="utf-8") as f, open(origen, encoding="utf-8") as g:
                            texto, sin_red = completar_mapa(f.read(), g.read())
                        with open(ruta, "w", encoding="utf-8") as f:
                            f.write(texto)
                    except (ValueError, OSError):
                        pass  # not JSON, or unreadable: it goes to pending like any modified file
                    else:
                        completados.append(ruta)
                        red_agregada = sin_red
                        continue
                destino = os.path.join(PENDIENTES, ruta)
                os.makedirs(os.path.dirname(destino), exist_ok=True)
                shutil.copy2(origen, destino)
                pendientes.append(ruta)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # The table of contexts of the small profile → the `contexts` section of the full map (ADR-003 D3).
    aviso_tabla, pasados = None, 0
    if tabla is not None:
        contextos, porque = contextos_de_tabla(tabla)
        if contextos:
            porque = pasar_contextos(contextos)
            pasados = 0 if porque else len(contextos)
        if porque:
            aviso_tabla = (f"the table of {ruta_tabla} was not passed to the `contexts` section of {MAPA} ({porque}): fill it in by hand "
                           "(name, paths, depends_on: the _help of the map explains it).")

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
    for viejo, nuevo in GLOSARIO_Y_CONTEXTOS:
        if viejo in sin_tocar:
            print(f"\nRemoved: {viejo} (you had not changed it): the full profile has its own, {nuevo}.")
    if tabla_movida:
        print(f"\nMoved: {', '.join(tabla_movida)}. The links to them in your docs have to point to docs/reference/ now.")
    for viejo, nuevo in sin_mover:
        print(f"\nNot moved: {viejo}, because {nuevo} already exists. Merge them by hand and delete {viejo}"
              + (f"; the `contexts` section of {MAPA} is not filled from it." if viejo == "docs/contexts.md" else "."))
    if pasados:
        print(f"\nContexts: {pasados} row(s) of the table went to the `contexts` section of {MAPA} (a code path that is a folder "
              "became folder/**). Check them with python3 scripts/agents/check-docs.py.")
    if aviso_tabla:
        print(f"\nWarning: {aviso_tabla}")
    enlaces = avisos_enlaces(False)
    if enlaces:
        print("\nThe glossary and the map of contexts have to be linked from the docs index (ADR-003 D2, D5; check-docs.py warns about it):")
        for e in enlaces:
            print(f"Warning: {e}")
    if completados:
        print(f"\nCompleted: {', '.join(completados)} keeps your sections (your `red` among them) and gets the ones of the "
              "full map. Fill in its TODO paths.")
    if red_agregada:
        print(f"\nRed: {RED_AGREGADA} If your tests are not bash, replace that entry. {RED_GUIA}")
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
