#!/usr/bin/env python3
"""Validates the documentation as infrastructure for agents. Exits with 1 if there are errors.

Checks:
- Relative Markdown links ([text](path)) that point to missing files.
- Paths in backticks (`dir/file.ext`) whose first directory exists but the file does not.
- Mentions of ADR-NNN with no file in docs/decisions/.
- ADRs missing from docs/README.md or docs/llms.txt.
- Required documents and paths of docs/agents-map.json that do not exist.
- Example paths (TODO/...) and checks without a command left in docs/agents-map.json
  after the init.
- Map paths (docs, sensitive, verify) that match no file (except the ones marked as optional
  with a leading "?"); warns about code folders the map does not cover.
- What AGENTS.md says is ignored (`.env*`...) and git does not ignore.
- Skills (.claude/skills/*/SKILL.md) over 120 lines, and docs/agents/lessons.md over 40.
- Subagents (.claude/agents/*.md) without name, description or tools, with a model that is not
  opus, sonnet or haiku, or that do not point to the common contract (docs/agents/subagent-contract.md).
- Language siblings (ADR-001), only with "parity": true in the map: every X.md has its X.es.md (and the
  other way around; the Spanish sibling of an agent lives in .claude/i18n/agents/) with the same number of headings and code blocks. "parity_ignore" in the map lists
  the exceptions (globs). The ignore_check paths do NOT exempt: profiles/ has siblings too.
- Members of .github/team.json that are repeated or have areas that are not in labels.yml.
The paths in "ignore_check" of the map (for example, historical logs) are not validated.

If .agent-kit.json exists, the .md files are validated only if they belong to the kit (the ones listed in
"files") or are in docs/, plus AGENTS.md and llms.txt. If install.py put the kit in a repo that already had its
own code (`"installed": true`), docs/ is not included: only the kit's .md files, AGENTS.md and llms.txt.
Without it (the template), everything is checked. `--list <glob>` prints the kit files that match the glob
(for example '*.sh'): docs.yml uses it so shellcheck and the tests run only on the kit.
"""
import fnmatch
import json
import os
import re
import subprocess
import sys

RAIZ = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
os.chdir(RAIZ)

LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
BACKTICK = re.compile(r"`(\.?[\w.-]+(?:/[\w.-]+)+)`")
ADR = re.compile(r"\bADR-(\d{3})\b")
EXT = re.compile(r"\.(md|txt|ya?ml|json|sh|py|ts|tsx|js|mjs|sql|toml)$")
IGNORAR_DIRS = {".git", "node_modules", ".turbo", ".next", "dist", "build", ".pnpm-store"}

errores = []


def archivos_del_kit():
    """Kit paths according to .agent-kit.json, or None if it does not exist (the template: everything is kit)."""
    if not os.path.exists(".agent-kit.json"):
        return None
    try:
        with open(".agent-kit.json", encoding="utf-8") as fh:
            archivos = json.load(fh)["files"]
        if not isinstance(archivos, dict):
            raise ValueError("'files' must be a path → hash object")
    except (ValueError, KeyError, OSError) as e:
        # Without failing, an empty list would leave shellcheck and the tests unrun, in green.
        print(f".agent-kit.json: cannot read the list of kit files ({e!r}).", file=sys.stderr)
        sys.exit(1)
    return set(archivos)


def instalado():
    """True if install.py put the kit in a repo that already had its own code (the registry says so)."""
    try:
        with open(".agent-kit.json", encoding="utf-8") as fh:
            return bool(json.load(fh).get("installed"))
    except (ValueError, OSError):
        return False


KIT = archivos_del_kit()
INSTALADO = KIT is not None and instalado()
if "--list" in sys.argv[1:]:
    if sys.argv[1:2] != ["--list"] or len(sys.argv) != 3:
        print("Usage: check-docs.py [--list <glob>]", file=sys.stderr)
        sys.exit(2)
    if KIT is None:
        r = subprocess.run(["git", "ls-files"], capture_output=True, text=True)
        if r.returncode != 0:
            print(f"git ls-files failed: {r.stderr.strip()}", file=sys.stderr)
            sys.exit(1)
        todos = r.stdout.splitlines()
    else:
        todos = sorted(a for a in KIT if os.path.isfile(a))
    print("\n".join(a for a in todos if fnmatch.fnmatch(a, sys.argv[2])))
    sys.exit(0)

MAPA = json.load(open("docs/agents-map.json", encoding="utf-8")) if os.path.exists("docs/agents-map.json") else {}
IGNORAR = []
avisos = []
if MAPA:
    # Without a map (small mode) there are no paths to validate and agents_map.py is not needed.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from agents_map import glob_a_regex, hermano_de_idioma  # noqa: E402
    IGNORAR = [glob_a_regex(g) for g in MAPA.get("ignore_check", [])]


def del_alcance(ruta):
    """With .agent-kit.json, only the kit .md files, AGENTS.md and llms.txt, and docs/ unless the kit was installed
    in an existing repo (install.py): there docs/ also has the project's own guides, and their broken links are
    not the kit's CI to fail. A project created from the template keeps docs/ checked: its docs/ is the kit's."""
    return KIT is None or ruta in KIT or ruta in ("AGENTS.md", "llms.txt") or (ruta.startswith("docs/") and not INSTALADO)


def md_files(aplicar_ignore=True):
    for base, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in IGNORAR_DIRS and not d.startswith(".claude/worktrees")]
        if "/.claude/worktrees" in base:
            continue
        for f in files:
            if f.endswith(".md") or f in ("llms.txt", "llms.es.txt"):
                ruta = os.path.normpath(os.path.join(base, f))
                if not (aplicar_ignore and any(r.match(ruta) for r in IGNORAR)) and del_alcance(ruta):
                    yield ruta


def sin_codigo(texto):
    """Removes ``` blocks so examples are not validated."""
    return re.sub(r"```.*?```", "", texto, flags=re.S)


adrs = {m.group(1): f for f in os.listdir("docs/decisions") if (m := re.match(r"ADR-(\d{3})-", f))} \
    if os.path.isdir("docs/decisions") else {}

for archivo in md_files():
    with open(archivo, encoding="utf-8") as fh:
        texto = sin_codigo(fh.read())
    carpeta = os.path.dirname(archivo)
    for n, linea in enumerate(texto.splitlines(), 1):
        prosa = re.sub(r"`[^`]*`", "", linea)  # links and ADRs inside `code` are examples
        for destino in LINK.findall(prosa):
            if re.match(r"^[a-z]+:", destino) or destino.startswith("#") or "<" in destino:
                continue
            ruta = destino.split("#")[0]
            if ruta and not os.path.exists(os.path.normpath(os.path.join(carpeta, ruta))):
                errores.append(f"{archivo}:{n}: broken link → {destino}")
        for ruta in BACKTICK.findall(linea):
            if "*" in ruta or not EXT.search(ruta):
                continue
            primero = ruta.lstrip("./").split("/")[0]
            if os.path.isdir(primero) and not os.path.exists(ruta) \
                    and not os.path.exists(os.path.join(carpeta, ruta)):
                errores.append(f"{archivo}:{n}: missing path → `{ruta}`")
        for num in set(ADR.findall(prosa)):
            if num != "000" and num not in adrs:
                errores.append(f"{archivo}:{n}: ADR-{num} does not exist in docs/decisions/")

# In an installed repo every ADR is the project's (the kit's own are not installed) and its indices are the
# project's too: the kit does not require them to list its ADRs.
for indice in ("docs/README.md", "docs/llms.txt"):
    if os.path.exists(indice) and not INSTALADO:
        contenido = open(indice, encoding="utf-8").read()
        for num, f in adrs.items():
            if num != "000" and f not in contenido:
                errores.append(f"{indice}: the ADR {f} is missing from the index")

def estructura(ruta):
    """(number of headings, number of code blocks) outside the ``` blocks: a "# comment" inside one is not a heading."""
    encabezados = bloques = 0
    cerco = None  # (character, length) of the open fence; it closes with the same character and at least as long
    with open(ruta, encoding="utf-8") as fh:
        for linea in fh:
            m = re.match(r" {0,3}(`{3,}|~{3,})", linea)
            if cerco is None and m:
                cerco = (m.group(1)[0], len(m.group(1)))
                bloques += 1
            elif cerco is not None:
                if m and m.group(1)[0] == cerco[0] and len(m.group(1)) >= cerco[1] and not linea.strip(cerco[0] + " \n"):
                    cerco = None
            elif re.match(r"#{1,6}\s", linea):
                encabezados += 1
    return encabezados, bloques


# Language siblings (ADR-001): X.md in English and X.es.md in Spanish. Only with "parity": true in the map:
# the template turns it on when its content is translated (#115); the init turns it off in the projects.
EXENTOS = [glob_a_regex(g) for g in MAPA.get("parity_ignore", [])] if MAPA else []
pares = [a for a in md_files(aplicar_ignore=False)
         if (a.endswith(".md") or os.path.basename(a) in ("llms.txt", "llms.es.txt")) and not any(r.match(a) for r in EXENTOS)]
if MAPA.get("parity"):
    for es in sorted(a for a in pares if a.endswith((".es.md", ".es.txt"))):
        en = hermano_de_idioma(es)
        if not os.path.exists(en):
            errores.append(f"{es}: has no English sibling {en} (rename the file or add it).")
    for en in sorted(a for a in pares if not a.endswith((".es.md", ".es.txt"))):
        es = hermano_de_idioma(en)
        if not os.path.exists(es):
            errores.append(f"{en}: missing its Spanish sibling {es}.")
            continue
        (h_en, b_en), (h_es, b_es) = estructura(en), estructura(es)
        if h_es != h_en:
            errores.append(f"{es}: {h_es} headings, but {en} has {h_en} (one of the two is out of date).")
        if b_es != b_en:
            errores.append(f"{es}: {b_es} code blocks, but {en} has {b_en} (one of the two is out of date).")

if MAPA:
    mapa = MAPA
    for f in mapa.get("required", []):
        if not os.path.exists(f):
            errores.append(f"docs/agents-map.json: the required document {f} is missing")
    # After the init (the script deletes itself), a "TODO/" in the map is a path that does not exist:
    # the agent would never mark anything as sensitive. In the uninitialized template it is allowed.
    if not os.path.exists("scripts/init-template.sh"):
        crudo = open("docs/agents-map.json", encoding="utf-8").read()
        pendientes = sorted(set(re.findall(r'"(TODO/[^"]*)"', crudo)))
        if pendientes:
            errores.append("docs/agents-map.json: replace the example paths with the real ones of the project: "
                           + ", ".join(pendientes))
        sin_comando = [v.get("name", "?") for v in mapa.get("verify", []) if v.get("run", "").startswith("TODO")]
        if sin_comando:
            errores.append("docs/agents-map.json: checks without a command (run starts with TODO): "
                           + ", ".join(sin_comando) + ". Put the project command or remove the check.")
    for regla in mapa.get("docs", []):
        for f in regla.get("review", []):
            if not os.path.exists(f):
                errores.append(f"docs/agents-map.json: '{regla.get('reason')}' points to {f}, which does not exist")

    # Map paths that match no file: if src/auth/ was renamed and the map still says
    # src/auth/**, the agent would never see that it touched something sensitive. Only after the init.
    if not os.path.exists("scripts/init-template.sh"):
        r = subprocess.run(["git", "ls-files"], capture_output=True, text=True)
        repo = [l for l in r.stdout.splitlines() if l] if r.returncode == 0 else []
        globs = [("docs", regla.get("reason", ""), g) for regla in mapa.get("docs", []) for g in regla.get("when", [])]
        globs += [("sensitive", s.get("type", ""), g) for s in mapa.get("sensitive", []) for g in s.get("paths", [])]
        globs += [("verify", v.get("name", ""), g) for v in mapa.get("verify", []) for g in v.get("when", [])]
        regex = {g: glob_a_regex(g) for _, _, g in globs}
        for seccion, nombre, g in globs:
            if repo and not g.startswith(("TODO/", "?")) and not any(regex[g].match(a) for a in repo):
                errores.append(f"docs/agents-map.json: {seccion} '{nombre}': the path {g} matches no "
                               "file. If it moved, update it; if it does not apply to the project, remove it.")
        # Code folders that no map path covers: warning, not error.
        codigo = re.compile(r"\.(ts|tsx|js|jsx|mjs|py|go|rb|rs|java|kt|php|cs|swift|sql)$")
        fuera = {".github", ".claude", "docs", "scripts", "profiles"}
        conteo = {}
        for a in repo:
            if codigo.search(a) and a.split("/")[0] not in fuera and not any(rx.match(a) for rx in regex.values()):
                carpeta = "/".join(a.split("/")[:-1][:4])  # up to 4 levels: apps/web/src/components
                if carpeta.count("/") >= 1:  # config files at the root of a package do not count
                    conteo[carpeta] = conteo.get(carpeta, 0) + 1
        top = sorted(conteo.items(), key=lambda x: -x[1])[:6]
        if top:
            avisos.append("code that no map path covers (if it changes, nobody says which doc to review): "
                          + ", ".join(f"{c}/ ({n})" for c, n in top)
                          + (f" and {len(conteo) - 6} more folders" if len(conteo) > 6 else ""))

# Team (.github/team.json): the areas must exist in labels.yml (labels can
# change after someone is added) and each member appears only once.
if os.path.exists(".github/team.json"):
    equipo = json.load(open(".github/team.json", encoding="utf-8"))
    nombres_labels = set()
    if os.path.exists(".github/labels.yml"):
        for linea in open(".github/labels.yml", encoding="utf-8"):
            if linea.strip().startswith("- name:"):
                nombres_labels.add(linea.split(":", 1)[1].strip().strip('"').strip("'"))
    vistos = set()
    for i in equipo.get("members", []):
        login = (i.get("login") or "").lower()
        if not login:
            errores.append(".github/team.json: there is a member without login")
        elif login in vistos:
            errores.append(f".github/team.json: @{login} appears more than once")
        vistos.add(login)
        for a in i.get("areas", []):
            if nombres_labels and a not in nombres_labels:
                errores.append(f".github/team.json: @{login} has the area {a}, which is not in .github/labels.yml")

# Long skills: the agent skips steps precisely because of the amount. If an adjustment
# does not fit in the maximum, something has to go or move to a script.
MAX_SKILL = 120
if os.path.isdir(".claude/skills"):
    for nombre in sorted(os.listdir(".claude/skills")):
        ruta = os.path.join(".claude/skills", nombre, "SKILL.md")
        if os.path.exists(ruta):
            lineas = sum(1 for _ in open(ruta, encoding="utf-8"))
            if lineas > MAX_SKILL:
                errores.append(f"{ruta}: {lineas} lines (maximum {MAX_SKILL}). Move something to a script or remove what adds nothing.")

# What AGENTS.md says is ignored (`.env*` are ignored) must be: the agent
# trusts that sentence and, if it is false, ends up committing a secret.
if os.path.exists("AGENTS.md"):
    NIEGA = re.compile(r"\b(?:no|nunca|not|never)\s+(?:(?:est[aá]n?|es|son|se|is|are|be)\s+)?ignor", re.I)
    for n, linea in enumerate(open("AGENTS.md", encoding="utf-8"), 1):
        if not re.search(r"ignorad|ignored", linea, re.I):
            continue
        # Cada patrón entre backticks se decide por lo que viene después, hasta el siguiente:
        # en "`.env*` está ignorado y `dist/` no está ignorado" se valida .env* y no dist/.
        ms = list(re.finditer(r"`([^`\s]+)`", linea))
        fin = [sig.start() for sig in ms[1:]] + [len(linea)]
        tramos = [(m.group(1), linea[m.end():f]) for m, f in zip(ms, fin)]
        afirmados = [p for p, t in tramos if re.search(r"ignor", t, re.I) and not NIEGA.search(t)]
        if not any(re.search(r"ignor", t, re.I) for _, t in tramos) and not NIEGA.search(linea):
            afirmados = [p for p, _ in tramos]  # "Están ignorados: `.env*`, `x`": la afirmación va antes
        for patron in afirmados:
            ejemplo = patron.replace("*", "")  # .env* → .env
            if not ejemplo:
                continue
            r = subprocess.run(["git", "check-ignore", "-q", "--no-index", ejemplo], capture_output=True)
            if r.returncode == 1:
                errores.append(f"AGENTS.md:{n}: says `{patron}` is ignored, but {ejemplo} is not. "
                               "Add it to .gitignore or fix the sentence.")

# Lessons from the retros: every agent reads them before starting, so they must be short.
MAX_LECCIONES, LECCIONES = 40, "docs/agents/lessons.md"
if os.path.exists(LECCIONES):
    lineas = sum(1 for _ in open(LECCIONES, encoding="utf-8"))
    if lineas > MAX_LECCIONES:
        errores.append(f"{LECCIONES}: {lineas} lines (maximum {MAX_LECCIONES}). Remove the oldest lesson or the one that already moved to a skill.")

# Subagents: the orchestrator picks the model by role, and all return the same output.
CONTRATO, AGENTES, AGENTES_ES = "docs/agents/subagent-contract.md", ".claude/agents", ".claude/i18n/agents"
# The Spanish agents (.claude/i18n/agents/<name>.es.md) become .claude/agents/<name>.md with --lang es:
# they have to be valid agents too, and keep the name of their English sibling.
for carpeta, es in ((AGENTES, False), (AGENTES_ES, True)):
    if not os.path.isdir(carpeta):
        continue
    for nombre in sorted(os.listdir(carpeta)):
        if not nombre.endswith(".md"):
            continue
        ruta = os.path.join(carpeta, nombre)
        if nombre.endswith(".es.md") and not es:
            errores.append(f"{ruta}: Claude Code would load it as a second agent with the same name; "
                           f"the Spanish sibling of an agent lives in .claude/i18n/agents/ (ADR-001, R-1).")
            continue
        texto = open(ruta, encoding="utf-8").read()
        m = re.match(r"---\n(.*?)\n---\n", texto, re.S)
        campos = {k: v.strip().strip("'\"") for k, v in re.findall(r"^(\w+): *(.*)$", m.group(1), re.M)} if m else {}
        for campo in ("name", "description", "tools"):
            if not campos.get(campo):
                errores.append(f"{ruta}: '{campo}:' is missing in the frontmatter.")
        if campos.get("model") not in ("opus", "sonnet", "haiku"):
            errores.append(f"{ruta}: model '{campos.get('model', '')}' (must be opus, sonnet or haiku: the model is part of the role, it is not inherited).")
        if CONTRATO not in texto:
            errores.append(f"{ruta}: does not point to the common contract ({CONTRATO}).")
        if es:
            en = os.path.join(AGENTES, nombre[:-len(".es.md")] + ".md")
            if os.path.exists(en):
                m_en = re.match(r"---\n(.*?)\n---\n", open(en, encoding="utf-8").read(), re.S)
                campos_en = {k: v.strip().strip("'\"") for k, v in re.findall(r"^(\w+): *(.*)$", m_en.group(1), re.M)} if m_en else {}
                for campo in ("name", "model", "tools"):
                    if campos.get(campo) != campos_en.get(campo):
                        errores.append(f"{ruta}: '{campo}:' is '{campos.get(campo, '')}' but {en} has '{campos_en.get(campo, '')}'.")

for a in avisos:
    print(f"Warning: {a}")
errores = list(dict.fromkeys(errores))
if errores:
    print(f"Docs with {len(errores)} problem(s):")
    for e in errores:
        print(f"- {e}")
    sys.exit(1)
print("Docs OK.")
