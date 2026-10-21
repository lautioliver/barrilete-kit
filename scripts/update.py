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
NO_TRAER = {"README.md", "README.es.md", "README.en.md", "LICENSE", ".agent-kit.json", ".github/team.json"}
PENDIENTES = ".agent-kit/pending"
USO = "Usage: python3 scripts/update.py [--version vX.Y.Z] [--template <url or path>]"
MAPA = "docs/agents-map.json"
# RED_AGREGADA and RED_GUIA (and `con_red`, in update.py and install.py) are copies in update.py, grow.py and install.py: they run on their own, so change all three.
RED_AGREGADA = ("docs/agents-map.json had no `red` section (ADR-002 D8): I added the kit's `bash` entry, which runs the test-*.sh "
                "files a commit adds or changes. red.sh needs the section and rejects a map without it.")
RED_GUIA = ("To configure your stack's entry, see docs/guides/red-per-runner.md (in the kit, "
            "https://github.com/lautioliver/barrilete-kit, if your project does not have the guides).")


def con_red(texto, kit):
    """The project's map with the kit's `red` section added; None if it already has one or there is nothing to add.
    ValueError if the project's map is not a JSON object."""
    try:
        mio, del_kit = json.loads(texto), json.loads(kit)
    except ValueError as e:
        raise ValueError(f"it is not valid JSON ({e})")
    if not isinstance(mio, dict):
        raise ValueError("it is not a JSON object")
    if "red" in mio or not isinstance(del_kit, dict) or "red" not in del_kit:
        return None
    mio["red"] = del_kit["red"]
    return json.dumps(mio, ensure_ascii=False, indent=2) + "\n"


def salir(msg):
    print(f"update.py: {msg}", file=sys.stderr)
    sys.exit(1)


# Projects created with 0.9 (Spanish names). The old names live only here, in the CHANGELOG table and in ADR-001.
# Kit files that exist in a 0.9 project, old path -> new path (the brand and profiles/ are deleted by the init).
RENAMES_0_9 = {
    ".claude/agents/implementador-liviano.md": ".claude/agents/implementer-light.md",
    ".claude/agents/implementador.md": ".claude/agents/implementer.md",
    ".claude/agents/revisor.md": ".claude/agents/reviewer.md",
    ".claude/skills/crear-issue/SKILL.md": ".claude/skills/create-issue/SKILL.md",
    ".claude/skills/estado/disponibles.sh": ".claude/skills/project-status/available.sh",
    ".claude/skills/estado/estado.sh": ".claude/skills/project-status/status.sh",
    ".claude/skills/estado/SKILL.md": ".claude/skills/project-status/SKILL.md",
    ".claude/skills/implement-issue/preparar.sh": ".claude/skills/implement-issue/prepare.sh",
    ".claude/skills/implement-issue/rojo.sh": ".claude/skills/implement-issue/red.sh",
    ".claude/skills/implement-issue/test-preparar.sh": ".claude/skills/implement-issue/test-prepare.sh",
    ".claude/skills/implement-issue/test-rojo.sh": ".claude/skills/implement-issue/test-red.sh",
    ".claude/skills/mejorar-skills/plantilla-retro.md": ".claude/skills/improve-skills/retro-template.md",
    ".claude/skills/mejorar-skills/retro.sh": ".claude/skills/improve-skills/retro.sh",
    ".claude/skills/mejorar-skills/senales.sh": ".claude/skills/improve-skills/signals.sh",
    ".claude/skills/mejorar-skills/SKILL.md": ".claude/skills/improve-skills/SKILL.md",
    ".claude/skills/mejorar-skills/test-retros.sh": ".claude/skills/improve-skills/test-retros.sh",
    ".claude/skills/orquestar/limpiar.sh": ".claude/skills/orchestrate/cleanup.sh",
    ".claude/skills/orquestar/ruteo.py": ".claude/skills/orchestrate/routing.py",
    ".claude/skills/orquestar/SKILL.md": ".claude/skills/orchestrate/SKILL.md",
    ".claude/skills/orquestar/test-orquestar.sh": ".claude/skills/orchestrate/test-orchestrate.sh",
    ".claude/skills/plan-feature/planificar.py": ".claude/skills/plan-feature/planner.py",
    ".github/equipo.json": ".github/team.json",
    ".github/hooks/barandas.json": ".github/hooks/guardrails.json",
    ".github/ISSUE_TEMPLATE/4-auditoria.yml": ".github/ISSUE_TEMPLATE/4-audit.yml",
    ".github/ISSUE_TEMPLATE/5-prueba.yml": ".github/ISSUE_TEMPLATE/5-trial.yml",
    ".github/workflows/desbloquear.yml": ".github/workflows/unblock.yml",
    "docs/agentes/contrato-subagentes.md": "docs/agents/subagent-contract.md",
    "docs/agentes/lecciones.md": "docs/agents/lessons.md",
    "docs/convencion-nombres-github.md": "docs/github-naming-convention.md",
    "docs/decisions/ADR-000-plantilla.md": "docs/decisions/ADR-000-template.md",
    "docs/mapa-agentes.json": "docs/agents-map.json",
    "docs/probar-la-plantilla.md": "docs/try-the-template.md",
    "scripts/actualizar.py": "scripts/update.py",
    "scripts/agentes/barandas.py": "scripts/agents/guardrails.py",
    "scripts/agentes/check-docs.py": "scripts/agents/check-docs.py",
    "scripts/agentes/equipo.py": "scripts/agents/team.py",
    "scripts/agentes/mapa.py": "scripts/agents/agents_map.py",
    "scripts/agentes/test_barandas.py": "scripts/agents/test_guardrails.py",
    "scripts/agentes/test_equipo.py": "scripts/agents/test_team.py",
    "scripts/agentes/test-agentes.sh": "scripts/agents/test-agents.sh",
    "scripts/agentes/test-base.sh": "scripts/agents/test-base.sh",
    "scripts/agentes/verificar.py": "scripts/agents/verify.py",
    "scripts/crecer.py": "scripts/grow.py",
    "scripts/init-plantilla.sh": "scripts/init-template.sh",
    "scripts/test-actualizar.sh": "scripts/test-update.sh",
}
# Old directory prefix -> new one, to rewrite paths inside the project's JSON (globs, commands).
# Not perfiles/: the 0.9 map lists its own entries (`?perfiles/chico/BORRAR`, `perfiles/**`) but the 3-way merge brings the
# new template's values for them, and rewriting by prefix would also touch the project's own `perfiles/` folders.
DIRS_0_9 = (("scripts/agentes/", "scripts/agents/"), ("docs/agentes/", "docs/agents/"))
# JSON keys of agents-map.json and team.json; `name` and `type` also have values to translate.
KEYS_0_9 = {"_ayuda": "_help", "cuando": "when", "revisar": "review", "motivo": "reason", "sensibles": "sensitive",
            "tipo": "type", "rutas": "paths", "verificar": "verify", "nombre": "name", "siempre": "always",
            "correr": "run", "obligatorios": "required", "ignorar_check": "ignore_check",
            "integrantes": "members", "activo": "active"}
VALUES_0_9 = {"name": {"preparar": "prepare", "agentes": "agents", "rojo": "red", "orquestar": "orchestrate",
                       "barandas": "guardrails", "actualizar": "update", "migraciones": "migrations",
                       "contrato-api": "api-contract"},
              "type": {"dinero": "money", "dependencias": "dependencies", "api-publica": "public-api"}}
KIT_KEYS_0_9 = {"proyecto": "project", "rama_base": "base_branch", "modo": "mode", "fecha": "date", "archivos": "files"}
MODES_0_9 = {"chico": "small", "completo": "full"}
JSON_0_9 = ("docs/agents-map.json", ".github/team.json")  # new paths; both are migrated in place
HOOKS = (".claude/settings.json", ".codex/hooks.json", ".cursor/hooks.json", ".github/hooks/guardrails.json")


def es_0_9(kit):
    """.agent-kit.json of a 0.9 project: any Spanish key (proyecto, rama_base, modo, fecha, archivos)."""
    return any(k in kit for k in KIT_KEYS_0_9)


def migrar_kit(kit):
    """The 0.9 .agent-kit.json with the new keys (same order). Without `language` it is `en`, as since #130."""
    nuevo = {}
    for k, v in kit.items():
        k = KIT_KEYS_0_9.get(k, k)
        nuevo[k] = MODES_0_9.get(v, v) if k == "mode" else v
    if "language" not in nuevo:  # placed after the mode, as the init writes it
        items = list(nuevo.items())
        i = next((n + 1 for n, (k, _) in enumerate(items) if k == "mode"), len(items))
        nuevo = dict(items[:i] + [("language", "en")] + items[i:])
    return nuevo


def _ruta_0_9():
    """One regex for the kit's old paths: a whole file path or a directory prefix, starting a path (after
    nothing, a space, a quote, `?` or `!`) and not inside another one (`app/perfiles/`, `x.py.sh`)."""
    archivos_ = "|".join(re.escape(v) for v in sorted(RENAMES_0_9, key=len, reverse=True))
    dirs = "|".join(re.escape(v) for v, _ in DIRS_0_9)
    # An optional ./ or ../ in front is kept: `python3 ./scripts/agentes/x.py` is the kit's path too.
    return re.compile(rf"(?<![\w./-])((?:\.\.?/)?)(?:({archivos_})(?![\w-]|\.\w)|({dirs}))")


def texto_nuevo(s):
    """A string of the project's JSON with the kit's old paths and the {archivos} placeholder replaced.
    The project's own paths stay as they are, even if they contain an old name."""
    dirs = dict(DIRS_0_9)
    s = _ruta_0_9().sub(lambda m: m.group(1) + (RENAMES_0_9[m.group(2)] if m.group(2) else dirs[m.group(3)]), s)
    return s.replace("{archivos}", "{files}")


def json_nuevo(o, mapa, clave=None):
    """Keys of both files; the values and paths of the map only (team.json has people's names)."""
    if isinstance(o, dict):
        return {KEYS_0_9.get(k, k): json_nuevo(v, mapa, KEYS_0_9.get(k, k)) for k, v in o.items()}
    if isinstance(o, list):
        return [json_nuevo(v, mapa, clave) for v in o]
    if isinstance(o, str) and (mapa or clave == "_help"):
        return VALUES_0_9.get(clave, {}).get(o, texto_nuevo(o)) if mapa else texto_nuevo(o)
    return o


def generado(ruta):
    """Files that running the project leaves behind (not the project's own)."""
    return "__pycache__" in ruta.split(os.sep) or ruta.endswith((".pyc", ".DS_Store"))


def migrar_arbol(raiz, registradas=None):
    """Moves the 0.9 kit files under `raiz` to their new names and migrates the keys of the JSON ones.
    `registradas` (the project's registry) follows the moves. Returns (moved, blocked, warnings):
    blocked are the files whose new path already exists, which are left where they are."""
    movidos, bloqueados, avisos = [], [], []
    for viejo, nuevo in sorted(RENAMES_0_9.items()):
        v, n = os.path.join(raiz, viejo), os.path.join(raiz, nuevo)
        if os.path.isfile(v):
            if os.path.lexists(n):
                bloqueados.append((viejo, nuevo))
            else:
                try:
                    os.makedirs(os.path.dirname(n), exist_ok=True)
                    os.replace(v, n)
                except OSError as e:
                    avisos.append(f"{viejo}: could not move it to {nuevo} ({e}). Move it by hand.")
                    bloqueados.append((viejo, nuevo))
                else:
                    movidos.append((viejo, nuevo))
                    carpeta = os.path.dirname(v)
                    while carpeta != raiz and os.path.isdir(carpeta) and not os.listdir(carpeta):
                        os.rmdir(carpeta)
                        carpeta = os.path.dirname(carpeta)
        if registradas is not None and viejo in registradas:
            h = registradas.pop(viejo)  # the file stays where it is if it was blocked: it is not the kit's anymore
            if (viejo, nuevo) not in bloqueados:
                registradas[nuevo] = h  # also when the project had deleted it
    for viejo, nuevo in DIRS_0_9:
        carpeta = os.path.join(raiz, viejo)
        if not os.path.isdir(carpeta):
            continue
        if not any(not generado(f) for f in archivos(carpeta)):
            shutil.rmtree(carpeta)  # empty, or only __pycache__ and the like left by running the old tests
        else:
            avisos.append(f"{viejo} still has your own files (not the kit's): they stay there. Move them to {nuevo} "
                          "by hand if you want, and fix the paths that docs/agents-map.json now points to.")
    for ruta in JSON_0_9:
        f = os.path.join(raiz, ruta)
        if not os.path.isfile(f):
            continue
        antes = huella(f)
        try:
            with open(f, encoding="utf-8") as fh:
                datos = json.load(fh)
            texto = json.dumps(json_nuevo(datos, ruta == "docs/agents-map.json"), ensure_ascii=False, indent=2) + "\n"
        except (ValueError, OSError) as e:
            avisos.append(f"{ruta}: could not migrate its keys ({e}). Rename them by hand (see the CHANGELOG table).")
            continue
        with open(f, "w", encoding="utf-8") as fh:
            fh.write(texto)
        if registradas is not None and ruta in registradas:
            # Untouched stays untouched (new hash); a file the project edited loses its entry, as a modified one would.
            if registradas[ruta] == antes:
                registradas[ruta] = huella(f)
            else:
                del registradas[ruta]
    return movidos, bloqueados, avisos


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


def completar_red(kit):
    """The project's map without a `red` section gets the kit's (ADR-002 D8): (added, warning or None).
    `kit` is the map of the initialized template. A map the project deleted on purpose stays deleted."""
    if not os.path.isfile(MAPA) or not os.path.isfile(kit):
        return False, None
    try:
        with open(MAPA, encoding="utf-8") as f, open(kit, encoding="utf-8") as g:
            texto = con_red(f.read(), g.read())
    except (ValueError, OSError) as e:
        return False, f"{MAPA}: could not check its `red` section ({e}). red.sh needs it: add it by hand. " + RED_GUIA
    if texto is None:
        return False, None
    with open(MAPA, "w", encoding="utf-8") as f:
        f.write(texto)
    return True, None


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
                # The folders it leaves empty go too (the corpus of red.sh was 842 of them); a folder with anything else stays.
                carpeta = os.path.dirname(ruta)
                while carpeta and not os.listdir(carpeta):
                    os.rmdir(carpeta)
                    carpeta = os.path.dirname(carpeta)
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
    migracion = es_0_9(kit)
    sin_idioma = migracion and "language" not in kit
    if migracion:
        kit = migrar_kit(kit)
        print("Project from 0.9: it will be migrated to the new names, keys and labels."
              + (" It has no `language`, so it is treated as English (the default now); see Language at the end "
                 "if it is in Spanish." if sin_idioma else ""))
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
        movidos, bloqueados, avisos = [], [], []
        if instalado:  # it exists: it was checked above
            base = os.path.join(tmp, "base")
            inicializar(clon, instalado, base, kit)
            renombrar(base, kit.get("renames", {}))
        elif actual and f"v{actual}" in disponibles:
            base = os.path.join(tmp, "base")
            inicializar(clon, f"v{actual}", base, kit)
            renombrar(base, kit.get("renames", {}))

        registradas = kit.get("files", {})
        if migracion:
            # The origin version (v0.9.0) has the old names: it is put in the new ones so the 3-way merge lines up.
            if base:
                migrar_arbol(base)
            movidos, bloqueados, avisos = migrar_arbol(".", registradas)
        plan = planear(nueva, base, registradas, set(kit.get("withheld", [])))
        hechos, errores = aplicar(plan, nueva)
        red_agregada, aviso_red = completar_red(os.path.join(nueva, MAPA))
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
    if migracion:
        print(f"\nMigrated from 0.9: {len(movidos)} kit files moved to their new names (your changes in them are kept: "
              "they were merged or are in the lists below), and the keys of .agent-kit.json, docs/agents-map.json "
              "and .github/team.json migrated.")
        if bloqueados:
            print("Not moved, because the new path already exists (compare them by hand):")
            for viejo, nuevo in bloqueados:
                print(f"  - {viejo} (new: {nuevo})")
        for a in avisos:
            print(f"Warning: {a}")
        if sin_idioma:
            print("Language: .agent-kit.json had no `language` (projects before #130), so this project is treated as "
                  "English, which is the default now: the kit's prose came in English and the files you had not touched "
                  "were replaced by it. If your project is in Spanish: discard this run (git reset --hard && git clean -fd && "
                  'rm -rf .agent-kit; reset also undoes a git add -A, and .agent-kit/ is ignored, so git clean does not remove it), add "language": "es" to '
                  ".agent-kit.json, commit that change (update.py refuses to run with uncommitted changes) and run "
                  "update.py again.")
        if any(r in hechos.get("conflicto", []) + hechos.get("pendiente", []) for r in HOOKS):
            print("Warning: a hook registration (.claude/settings.json, .codex/hooks.json, .cursor/hooks.json, "
                  ".github/hooks/guardrails.json) is in .agent-kit/pending/: all four must point to "
                  "scripts/agents/guardrails.py, or the hook finds no script and stops nothing.")
        print("Labels: after the merge run the Labels workflow: labels.yml has the old names as `aliases`, so label-sync "
              "renames tipo:x to type:x (and the rest) keeping the ones set on issues and PRs. The old retros branch "
              "agentes/retros stays as it is; if you protect branches, allow pushes to agents/retros.")
    if red_agregada:
        print(f"\nRed: {RED_AGREGADA} If your tests are not bash, replace that entry. {RED_GUIA}")
    if aviso_red:
        print(f"\nWarning: {aviso_red}")
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
    # check-docs.py reads the git index: with files moved or added and not staged it reports false missing paths.
    print("  2. git add -A, then python3 scripts/agents/check-docs.py (it reads the git index), and review the diff.")
    print("  3. Commit and open a PR. If .github/labels.yml changed, run the Labels workflow after the merge.")


if __name__ == "__main__":
    main()
