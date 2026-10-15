#!/usr/bin/env python3
"""Installs the kit in a project that already exists, without overwriting anything of its own.

Usage (from the root of the project, with a clean working tree):
  curl -fsSL https://raw.githubusercontent.com/lautioliver/barrilete-kit/main/scripts/install.py | python3 - "Project" main [releases] [--small] [--draft]
  python3 <clone of the template>/scripts/install.py "Project" main      # to read it before running it

  --small           small-project mode (the same as the init's).
  --draft           prints the plan and writes nothing.
  --template <url or path>   where to get the kit from (default: AGENT_KIT_TEMPLATE, the clone this script is in, or GitHub).
  --version vX.Y.Z  kit version (default: the latest tag that includes this script; without one, the default branch).
  -- <options>      everything after `--` goes to scripts/init-template.sh as is (for example `-- --lang es`).

It initializes the kit in a temporary folder with the project data and then, for each file:
  - the project does not have it → adds it (and registers it in .agent-kit.json);
  - it is the same → registers it;
  - README, LICENSE → never touches them;
  - .gitignore → adds what is missing in a `# barrilete` block; CLAUDE.md → adds `@AGENTS.md` if missing;
  - .claude/settings.json → JSON merge: adds the guardrails hook to its hooks;
  - a workflow with the same name → the kit's is installed as barrilete-<name>.yml (`renames` in .agent-kit.json);
  - .github/labels.yml → the kit's labels plus the ones the repo already has (`gh label list`), so the sync deletes none;
  - any other file the project already has → keeps the project's; the kit's version goes to .agent-kit/pending/.
Merged and pending files are not registered: they are the project's, and update.py merges them against the kit.
Does not commit: the changes stay in the working tree to review them and open a PR.
"""
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

PLANTILLA = "https://github.com/lautioliver/barrilete-kit"
NUNCA_TOCAR = {"README.md", "README.en.md", "LICENSE", ".agent-kit.json"}
PENDIENTES = ".agent-kit/pending"
# Labels GitHub creates in every new repo: they stay as the project's own (deleting them is the project's call).
LABELS_GITHUB = {"bug", "documentation", "duplicate", "enhancement", "good first issue", "help wanted", "invalid",
                 "question", "wontfix"}
USO = 'Usage: python3 install.py "Project name" [main|develop] [releases] [--small] [--draft] ' \
      "[--template <url or path>] [--version vX.Y.Z] [-- <init options>]"


def salir(msg):
    print(f"install.py: {msg}", file=sys.stderr)
    sys.exit(1)


def sh(*cmd, cwd=None, env=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, env=env)
    if r.returncode != 0:
        salir(f"{' '.join(cmd[:3])}… failed: {(r.stderr or r.stdout).strip()}")
    return r


def huella(ruta):
    with open(ruta, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()


def archivos(raiz):
    for base, dirs, files in os.walk(raiz):
        dirs[:] = [d for d in dirs if d != ".git"]
        for n in files:
            yield os.path.relpath(os.path.join(base, n), raiz)


def leer(ruta):
    with open(ruta, encoding="utf-8") as f:
        return f.read()


def numero(version):
    m = re.match(r"v?(\d+)\.(\d+)\.(\d+)", version or "")
    return tuple(int(x) for x in m.groups()) if m else None


def parsear(args):
    """(positionals, options, init options)."""
    opciones = {"small": False, "draft": False, "template": None, "version": None}
    pos, extra = [], []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            extra = args[i + 1:]
            break
        if a in ("--small", "--draft"):
            opciones[a[2:]] = True
        elif a in ("--template", "--version"):
            if i + 1 >= len(args) or args[i + 1].startswith("--"):
                salir(f"{a} needs a value.\n{USO}")
            opciones[a[2:]] = args[i + 1]
            i += 1
        elif a.startswith("-"):
            salir(f"Unknown option: {a} (the init's options go after --).\n{USO}")
        else:
            pos.append(a)
        i += 1
    if not 1 <= len(pos) <= 3:
        salir(USO)
    return pos, opciones, extra


def origen_plantilla(pedida):
    if pedida:
        return os.path.abspath(pedida) if os.path.exists(pedida) else pedida
    if os.environ.get("AGENT_KIT_TEMPLATE"):
        return os.environ["AGENT_KIT_TEMPLATE"]
    este = globals().get("__file__")  # not defined when it is piped to `python3 -`
    if este:
        raiz = os.path.dirname(os.path.dirname(os.path.abspath(este)))
        if os.path.exists(os.path.join(raiz, ".git")) and os.path.exists(os.path.join(raiz, "scripts", "init-template.sh")):
            return raiz
    return PLANTILLA


def elegir_ref(clon, pedida):
    tags = sorted((t for t in sh("git", "tag", "--list", "v*", cwd=clon).stdout.split()
                   if re.fullmatch(r"v\d+\.\d+\.\d+", t)), key=numero)

    def trae_instalador(ref):
        return subprocess.run(["git", "cat-file", "-e", f"{ref}:scripts/install.py"], cwd=clon,
                              capture_output=True).returncode == 0
    if pedida:
        ref = pedida if pedida.startswith("v") else f"v{pedida}"
        if ref not in tags:
            salir(f"the template does not have version {ref}. Versions: {', '.join(tags) or 'none'}.")
        return ref
    con_instalador = [t for t in tags if trae_instalador(t)]
    if con_instalador:
        return con_instalador[-1]
    print("No release includes the installer yet: using the template's default branch.")
    return "HEAD"


def inicializar(clon, ref, destino, args_init):
    """The kit at `ref`, initialized with the project data, in `destino`."""
    os.makedirs(destino)
    tar = subprocess.run(["git", "archive", ref], cwd=clon, capture_output=True)
    if tar.returncode != 0:
        salir(f"cannot find {ref} in the template: {tar.stderr.decode().strip()}")
    subprocess.run(["tar", "-xf", "-"], cwd=destino, input=tar.stdout, check=True)
    if not os.path.exists(os.path.join(destino, "scripts", "init-template.sh")):
        salir(f"{ref} has no scripts/init-template.sh: that version predates the English names. Use a newer --version.")
    sh("git", "init", "-q", cwd=destino)
    sh("./scripts/init-template.sh", *args_init, cwd=destino)


def leer_labels():
    r = subprocess.run(["gh", "label", "list", "--limit", "1000", "--json", "name,color,description"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        salir("cannot read the repo labels with `gh label list` "
              f"({(r.stderr or r.stdout).strip() or 'gh failed'}). I need them: the label sync deletes every "
              "label that is not in .github/labels.yml, so without them it would delete the repo's own. "
              "Install gh and run `gh auth login` in a repo with a GitHub remote, then try again.")
    try:
        return json.loads(r.stdout)
    except ValueError:
        salir("`gh label list` did not return JSON.")


def combinar_labels(nueva, existentes):
    """(text of labels.yml, names of the repo's own labels)."""
    ruta = os.path.join(nueva, "scripts", "agents", "labels.py")
    if not os.path.exists(ruta):
        salir("this version of the template has no scripts/agents/labels.py (it predates the installer). Use a newer --version.")
    spec = importlib.util.spec_from_file_location("labels_kit", ruta)
    modulo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(modulo)
    try:
        texto = modulo.combinar(leer(os.path.join(nueva, ".github", "labels.yml")), existentes)
    except (ValueError, KeyError, TypeError) as e:
        salir(f"the output of `gh label list` is not what labels.py expects ({e}).")
    propios = []
    if modulo.MARCA in texto:
        propios = [json.loads(m) for m in re.findall(r'^- name: (".*")\s*$', texto.split(modulo.MARCA)[1], re.M)]
    return texto, propios


def fusionar_gitignore(texto, kit):
    hay = {l.strip() for l in texto.splitlines()}
    faltan = [l.strip() for l in kit.splitlines() if l.strip() and not l.strip().startswith("#") and l.strip() not in hay]
    if not faltan:
        return None
    return texto + ("" if texto.endswith("\n") or not texto else "\n") + "\n# barrilete\n" + "\n".join(faltan) + "\n"


def fusionar_claude(texto, kit):
    if "@AGENTS.md" in texto:
        return None
    return texto + ("" if texto.endswith("\n") or not texto else "\n") + "\n@AGENTS.md\n"


def mismo_hook(propio, kit):
    """The same hook, or the same script with another command line (the guardrails hook is installed once)."""
    if propio == kit:
        return True
    guion = re.search(r"scripts/agents/[\w.-]+\.py", str(kit.get("command", "")))
    return bool(guion and isinstance(propio, dict) and guion.group(0) in str(propio.get("command", "")))


def fusionar_settings(texto, kit):
    """JSON merge: the kit's hooks into the project's. None if there is nothing to add; ValueError if it cannot."""
    try:
        usuario, nuevo = json.loads(texto), json.loads(kit)
    except ValueError as e:
        raise ValueError(f"settings.json is not valid JSON ({e})")
    if not isinstance(usuario, dict) or not isinstance(usuario.get("hooks", {}), dict):
        raise ValueError("settings.json has no hooks object")
    hooks = usuario.setdefault("hooks", {})
    cambio = False
    for evento, grupos in nuevo.get("hooks", {}).items():
        propios = hooks.setdefault(evento, [])
        if not isinstance(propios, list):
            raise ValueError(f"hooks.{evento} is not a list")
        for grupo in grupos:
            for hook in grupo.get("hooks", []):
                if any(mismo_hook(h, hook) for g in propios if isinstance(g, dict) for h in g.get("hooks", [])):
                    continue
                destino = next((g for g in propios if isinstance(g, dict) and g.get("matcher") == grupo.get("matcher")
                                and isinstance(g.get("hooks"), list)), None)
                if destino is None:
                    propios.append({k: v for k, v in grupo.items() if k != "hooks"} | {"hooks": []})
                    destino = propios[-1]
                destino["hooks"].append(hook)
                cambio = True
    return json.dumps(usuario, ensure_ascii=False, indent=2) + "\n" if cambio else None


FUSIONES = {".gitignore": fusionar_gitignore, "CLAUDE.md": fusionar_claude, ".claude/settings.json": fusionar_settings}


def es_workflow(ruta):
    return bool(re.fullmatch(r"\.github/workflows/[^/]+\.ya?ml", ruta))


def otra_extension(ruta):
    base, ext = os.path.splitext(ruta)
    return base + (".yaml" if ext == ".yml" else ".yml")


def rename_o_pending(ruta, kit):
    nuevo = os.path.join(os.path.dirname(ruta), "barrilete-" + os.path.basename(ruta))
    ocupado = os.path.lexists(nuevo) or os.path.lexists(otra_extension(nuevo))
    return ("pending" if ocupado else "rename", ruta, kit, nuevo)


def padre_ocupado(ruta):
    """True if a folder of the path is a file (or a link) in the project: the kit file cannot go there."""
    partes = ruta.split("/")[:-1]
    return any(os.path.lexists("/".join(partes[:i + 1])) and not os.path.isdir("/".join(partes[:i + 1]))
               or os.path.islink("/".join(partes[:i + 1])) for i in range(len(partes)))


def planear(nueva, labels_yml):
    """What to do with each kit file, without touching anything: list of (action, project path, kit path, data).

    Actions: add, same (registered), merge, rename (registered under the new name), pending, skip.
    """
    plan = []
    for ruta in sorted(set(archivos(nueva)) - {".agent-kit.json"}):
        kit = os.path.join(nueva, ruta)
        if ruta in NUNCA_TOCAR:
            plan.append(("skip", ruta, kit, None))
        elif ruta == ".github/labels.yml":
            plan.append(("add" if not os.path.lexists(ruta) else "pending", ruta, kit, labels_yml))
        elif padre_ocupado(ruta):
            plan.append(("pending", ruta, kit, None))
        elif not os.path.lexists(ruta) and not (es_workflow(ruta) and os.path.lexists(otra_extension(ruta))):
            plan.append(("add", ruta, kit, None))
        elif not os.path.lexists(ruta):  # the same workflow with the other extension (.yaml / .yml)
            plan.append(rename_o_pending(ruta, kit))
        elif not os.path.isfile(ruta):
            plan.append(("pending", ruta, kit, None))
        elif huella(ruta) == huella(kit):
            plan.append(("same", ruta, kit, None))
        elif ruta in FUSIONES:
            try:
                texto = FUSIONES[ruta](leer(ruta), leer(kit))
            except (ValueError, UnicodeDecodeError):
                plan.append(("pending", ruta, kit, None))
                continue
            plan.append(("merge" if texto is not None else "same-merged", ruta, kit, texto))
        elif es_workflow(ruta):
            plan.append(rename_o_pending(ruta, kit))
        else:
            plan.append(("pending", ruta, kit, None))
    return plan


def escribir(ruta, texto):
    os.makedirs(os.path.dirname(ruta) or ".", exist_ok=True)
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(texto)


def aplicar(plan):
    """Writes the plan; returns the registry (path → hash of what the kit installed) and the renames."""
    registro, renombres = {}, {}
    for accion, ruta, kit, dato in plan:
        if accion in ("add", "same") and not (ruta == ".github/labels.yml"):
            if accion == "add":
                os.makedirs(os.path.dirname(ruta) or ".", exist_ok=True)
                shutil.copy2(kit, ruta)
            registro[ruta] = huella(kit)
        elif accion == "add":  # labels.yml: the combined text, and it is the project's from now on
            escribir(ruta, dato)
        elif accion == "rename":
            os.makedirs(os.path.dirname(dato), exist_ok=True)
            shutil.copy2(kit, dato)
            registro[dato] = huella(kit)
            renombres[ruta] = dato
        elif accion == "merge":
            modo = os.stat(ruta).st_mode
            escribir(ruta, dato)
            os.chmod(ruta, modo)
        elif accion == "pending":
            destino = os.path.join(PENDIENTES, ruta)
            if ruta == ".github/labels.yml":
                escribir(destino, dato)
            else:
                os.makedirs(os.path.dirname(destino), exist_ok=True)
                shutil.copy2(kit, destino)
    return registro, renombres


def resumen(plan, propios, ref, draft):
    def de(*acciones):
        return [(r, d) for a, r, _, d in plan if a in acciones]
    print(f"\n{'Plan (--draft: nothing was written)' if draft else 'Done'}: kit {ref}.")
    print(f"  {len([r for r, _ in de('add') if r != '.github/labels.yml'])} added, "
          f"{len(de('same'))} already equal, {len(de('merge'))} merged, {len(de('rename'))} renamed, "
          f"{len(de('pending'))} left in {PENDIENTES}/.")
    for r, _ in de("merge"):
        print(f"  - Merged into yours (review the diff): {r}")
    for r, d in de("rename"):
        print(f"  - Workflow with the same name: the kit's {os.path.basename(r)} is installed as {os.path.basename(d)}")
    if any(r == ".github/labels.yml" for r, _ in de("add")):
        print(f"  - .github/labels.yml: the kit's labels plus {len(propios)} of the repo's own, so the sync deletes none")
    if propios:
        por_defecto = [n for n in propios if n.lower() in LABELS_GITHUB]
        print(f"    Own labels kept: {', '.join(propios[:12])}{'…' if len(propios) > 12 else ''}")
        if por_defecto:
            print(f"    {len(por_defecto)} are GitHub default labels ({', '.join(por_defecto)}): they stay as yours; "
                  "delete them from the own-labels section of labels.yml if you do not want them.")
    pend = de("pending")
    if any(r == ".github/labels.yml" for r, _ in pend):
        print("  - You already had .github/labels.yml: it is yours, and it does NOT have the repo's labels. "
              f"Merge {PENDIENTES}/.github/labels.yml into it before the first sync: the sync deletes every label "
              "that is not in the file.")
    if pend:
        print(f"\nYou already had these files, so I left yours and put the kit's version in {PENDIENTES}/:")
        for r, _ in pend:
            print(f"  - {r}")
        print("An agent (or you) integrates what is worth keeping into yours in the same PR, then deletes that folder. "
              "update.py will not run while it has files.")
    pasos = ["Review `git status` and the diff (nothing is committed)."]
    if pend:
        pasos.append(f"Integrate what is in {PENDIENTES}/ and delete the folder.")
    pasos += ["Fill in the TODO: markers of the kit files (grep -rn 'TODO:' AGENTS.md docs .github).",
              "Commit on a branch and open a PR. The kit CI only checks the kit's files; your own tests and lint "
              "need a workflow of yours.",
              "After the merge, the Labels workflow syncs .github/labels.yml (it keeps the repo's labels)."]
    print("\nNext steps:")
    for i, paso in enumerate(pasos, 1):
        print(f"  {i}. {paso}")


def main():
    pos, op, extra = parsear(sys.argv[1:])
    proyecto, base = pos[0], (pos[1] if len(pos) > 1 else "main")
    if base not in ("main", "develop"):
        salir(f"the base branch must be main or develop (got {base}).\n{USO}")
    args_init = [proyecto, base] + pos[2:] + (["--small"] if op["small"] else []) + extra

    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if r.returncode != 0:
        salir("this is not a git repository: run it from the root of the project where you want to install the kit.")
    os.chdir(r.stdout.strip())
    if os.path.exists("scripts/install.py") and os.path.exists("scripts/init-template.sh"):
        salir("this is the template itself: run it from the project where you want to install the kit.")
    if os.path.exists(".agent-kit.json"):
        salir("this repo already has the kit (.agent-kit.json). To bring a new version, use scripts/update.py.")
    if sh("git", "status", "--porcelain").stdout.strip():
        salir("there are uncommitted changes. Commit or stash them before installing.")
    existentes = leer_labels()

    tmp = tempfile.mkdtemp(prefix="agent-kit-")
    try:
        plantilla = origen_plantilla(op["template"])
        clon = os.path.join(tmp, "clon")
        print(f"Cloning the template from {plantilla}…")
        sh("git", "clone", "-q", "--", plantilla, clon)
        ref = elegir_ref(clon, op["version"])
        nueva = os.path.join(tmp, "nueva")
        inicializar(clon, ref, nueva, args_init)
        with open(os.path.join(nueva, ".agent-kit.json"), encoding="utf-8") as f:
            registro_kit = json.load(f)
        labels_yml, propios = combinar_labels(nueva, existentes)
        plan = planear(nueva, labels_yml)
        if not op["draft"]:
            try:
                registro, renombres = aplicar(plan)
            except OSError as e:
                salir(f"could not write the files ({e}). The tree may be half installed: `git status` shows what was "
                      "written; discard it with `git clean -fd` and `git checkout .`, then try again.")
            registro_kit["files"] = dict(sorted(registro.items()))
            if renombres:
                registro_kit["renames"] = renombres
            with open(".agent-kit.json", "w", encoding="utf-8") as f:
                json.dump(registro_kit, f, ensure_ascii=False, indent=2)
                f.write("\n")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    resumen(plan, propios, ref if ref != "HEAD" else "from the default branch", op["draft"])


if __name__ == "__main__":
    main()
