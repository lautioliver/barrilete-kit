#!/usr/bin/env python3
"""Validates the documentation as infrastructure for agents. Exits with 1 if there are errors.

Checks:
- Relative Markdown links ([text](path)) that point to missing files.
- Paths in backticks (`dir/file.ext`) whose first directory exists but the file does not.
- Mentions of ADR-NNN with no file in docs/decisions/ or docs/decisions/kit/.
- ADRs missing from docs/README.md or docs/llms.txt (and from their Spanish siblings, if they exist); a kit ADR with
  `Scope: kit` (the init only deletes `Ámbito: kit`) is a warning.
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
  other way around; the Spanish sibling of an agent lives in .claude/i18n/agents/, and that of an issue form in
  .github/i18n/ISSUE_TEMPLATE/, compared by type/id/labels/required/options) with the same number of headings and code blocks. "parity_ignore" in the map lists
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
hermano_de_idioma = None  # small mode has no agents_map.py nor map: parity (the only user) is off there
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


# The .es.md siblings of an ADR are not ADRs of their own: only X.md counts (and in a fixed order, not the one os.listdir gives).
# The ADRs of the kit that the projects install live in docs/decisions/kit/ (the project numbers its own in docs/decisions/), so the
# same number can exist in both folders: each folder is read on its own and the index asks for each one by its path.
def leer_adrs(carpeta):
    if not os.path.isdir(carpeta):
        return {}
    return {m.group(1): f for f in sorted(os.listdir(carpeta), reverse=True)
            if (m := re.match(r"ADR-(\d{3})-", f)) and not f.endswith(".es.md")}


adrs = leer_adrs("docs/decisions")
adrs_kit = leer_adrs("docs/decisions/kit")

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
            if num != "000" and num not in adrs and num not in adrs_kit:
                errores.append(f"{archivo}:{n}: ADR-{num} does not exist in docs/decisions/ or docs/decisions/kit/")

# In an installed repo every ADR is the project's (the kit's own are not installed) and its indices are the
# project's too: the kit does not require them to list its ADRs.
# The Spanish siblings (docs/README.es.md, docs/llms.es.txt) are the project's indices when it is installed with --lang es:
# the parity check counts headings, not lines, so it would not notice an ADR missing from them.
for indice in ("docs/README.md", "docs/llms.txt", "docs/README.es.md", "docs/llms.es.txt"):
    if os.path.exists(indice) and not INSTALADO:
        contenido = open(indice, encoding="utf-8").read()
        # The path is what is looked for ("decisions/" + name, "decisions/kit/" + name): the name alone would let the index line of
        # one folder cover a file of the other.
        for num, f in adrs.items():
            if num != "000" and f"decisions/{f}" not in contenido:
                errores.append(f"{indice}: the ADR {f} is missing from the index")
        for f in adrs_kit.values():
            if f"decisions/kit/{f}" not in contenido:
                errores.append(f"{indice}: the ADR kit/{f} is missing from the index")

# The init only deletes the ADRs of the kit with the exact line "Ámbito: kit" (it is a literal, it is not translated): one written
# with "Scope: kit" would be installed in every project. Warning, not error: a project may use that line for something else.
# Only where the init is still there (the kit itself): in a project the ADRs are its own and there is nothing left to delete.
KIT_AMBITO = re.compile(r"^Ámbito: kit$", re.M)  # exactly what the init matches (grep -x): trailing spaces or a \r do not count
for f in sorted(os.listdir("docs/decisions") if os.path.exists("scripts/init-template.sh") and os.path.isdir("docs/decisions") else []):
    if not re.match(r"ADR-\d{3}-.*\.md$", f):
        continue
    with open(os.path.join("docs/decisions", f), encoding="utf-8", newline="") as fh:  # newline="": keep the \r of CRLF files
        texto = fh.read()
    if re.search(r"^Scope: kit\s*$", texto, re.M):
        avisos.append(f"docs/decisions/{f} has the line `Scope: kit`, but the init only deletes the ADRs with `Ámbito: kit` "
                      "(a literal that is not translated): this one would be installed in the projects.")
    if re.search(r"^Ámbito: kit[ \t\r]+$", texto, re.M):
        avisos.append(f"docs/decisions/{f} has `Ámbito: kit` with trailing whitespace or a CRLF line ending: the init matches the whole "
                      "line, so it would not delete it (remove the trailing spaces or convert the file to LF).")
    # The init keeps one of the two siblings (the .md with `en`; with `es` the .es.md is moved over the .md) and then deletes the
    # ADRs whose remaining file has the exact `Ámbito: kit` line. If only one of the two has it, the ADR is deleted in one language
    # and installed in the other. A sibling with `Scope: kit` is not compared: its own warning above already covers it.
    hermano_es = os.path.join("docs/decisions", f[:-3] + ".es.md")
    if not f.endswith(".es.md") and os.path.exists(hermano_es):
        with open(hermano_es, encoding="utf-8", newline="") as fh:
            texto_es = fh.read()
        kit_en, kit_es = (bool(KIT_AMBITO.search(t)) for t in (texto, texto_es))
        otro_scope = bool(re.search(r"^Scope: kit\s*$", texto if kit_es else texto_es, re.M))
        if kit_en != kit_es and not otro_scope:
            con, sin = (f, f[:-3] + ".es.md") if kit_en else (f[:-3] + ".es.md", f)
            avisos.append(f"docs/decisions/{con} has `Ámbito: kit` but docs/decisions/{sin} does not: the two siblings must agree "
                          "(the init would delete the ADR in one language and install it in the other).")

# docs/decisions/kit/ holds the kit ADRs that the projects install (ADR-002, D11): the init deletes only the `Ámbito: kit` ones of
# docs/decisions/, so one in kit/ that carries the line (or `Scope: kit`) contradicts itself and would be installed anyway.
for f in sorted(os.listdir("docs/decisions/kit") if os.path.exists("scripts/init-template.sh") and os.path.isdir("docs/decisions/kit") else []):
    if not re.match(r"ADR-\d{3}-.*\.md$", f):
        continue
    with open(os.path.join("docs/decisions/kit", f), encoding="utf-8", newline="") as fh:
        texto = fh.read()
    marca = re.search(r"^(Ámbito|Scope): kit\s*$", texto, re.M)
    if marca:
        avisos.append(f"docs/decisions/kit/{f} has the line `{marca.group(0).strip()}`, but the ADRs of docs/decisions/kit/ are the ones the projects install "
                      "(the init only deletes the ones of docs/decisions/), so this one would be installed anyway: remove the line, or move the ADR out of kit/.")


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
if MAPA.get("parity"):
    pares = [a for a in md_files(aplicar_ignore=False)
             if hermano_de_idioma(a) and not any(r.match(a) for r in EXENTOS)]
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

# Issue forms (.yml): GitHub offers every .yml of .github/ISSUE_TEMPLATE as a form, so the Spanish sibling lives in
# .github/i18n/ISSUE_TEMPLATE/<name>.es.yml (ADR-001, R-1; the rule is hermano_de_idioma() in agents_map.py). They are
# compared by what does not carry prose: type, id, labels, required and the number of options.
FORMS_EN, FORMS_ES = ".github/ISSUE_TEMPLATE", ".github/i18n/ISSUE_TEMPLATE"
# hermano_de_idioma is imported at the top, with the map: small mode deletes agents_map.py and has no map, forms or parity.
# One option of an inline list: a quoted string (it can carry a comma: "Yes, I did") or text up to the next comma.
OPCION = re.compile(r"""\s*(?:"[^"]*"|'[^']*'|[^,"'][^,]*)\s*(?:,|$)""")


def claves_de_formulario(ruta):
    """type, id, labels and required lines of an issue form (without the spacing) and the size of each options list."""
    with open(ruta, encoding="utf-8") as fh:
        lineas = fh.read().splitlines()
    claves = [re.sub(r"\s+", " ", l).strip() for l in lineas if re.match(r"^\s*(?:- )?(?:type|id|labels):", l)]
    actual = ""  # the id of the field the line belongs to: two forms that require different fields are not the same
    for l in lineas:
        if re.match(r"^\s*- type:", l):
            actual = ""  # a new field: without its own id it must not inherit the previous one's
        m = re.match(r"^\s*(?:- )?id: *[\"']?([^\"'\s]+)", l)
        if m:
            actual = m.group(1)
        if re.search(r"\brequired: *true\b", l):
            claves.append(f"required:{actual}")
    for i, l in enumerate(lineas):
        m = re.match(r"^(\s*)options:\s*(.*)$", l)
        if not m:
            continue
        if m.group(2).startswith("["):
            claves.append(f"options={len(OPCION.findall(m.group(2).strip().strip('[]')))}")
        else:
            n = 0
            for sig in lineas[i + 1:]:
                if re.match(r"^\s*- ", sig) and len(sig) - len(sig.lstrip()) > len(m.group(1)):
                    n += 1
                elif sig.strip():
                    break
            claves.append(f"options={n}")
    return claves


if os.path.isdir(FORMS_EN):
    for nombre in sorted(os.listdir(FORMS_EN)):
        if nombre.endswith(".es.yml"):
            errores.append(f"{FORMS_EN}/{nombre}: GitHub would offer it as a second form; the Spanish sibling of a form "
                           f"lives in {FORMS_ES}/ (ADR-001, R-1).")
if MAPA.get("parity") and os.path.isdir(FORMS_EN):
    ya_vistos = set()
    for nombre in sorted(os.listdir(FORMS_EN)):
        en = f"{FORMS_EN}/{nombre}"
        es = hermano_de_idioma(en)
        if not es:  # config.yml, or a .es.yml (reported above)
            continue
        ya_vistos.add(es)
        if not os.path.exists(es):
            errores.append(f"{en}: missing its Spanish sibling {es}.")
        elif claves_de_formulario(en) != claves_de_formulario(es):
            errores.append(f"{es}: its type/id/labels/required/options keys differ from {en} (one of the two is out of date).")
    if os.path.isdir(FORMS_ES):
        for nombre in sorted(os.listdir(FORMS_ES)):
            es = f"{FORMS_ES}/{nombre}"
            if hermano_de_idioma(es) and es not in ya_vistos:
                errores.append(f"{es}: has no English sibling {hermano_de_idioma(es)}.")

# labels.yml and labels.es.yml: the same labels, colors and aliases (only the descriptions are translated); if one gets behind,
# a --lang es install would sync a different set of labels and delete the missing ones (delete-other-labels), and a project
# migrating from 0.9 would lose the renames. Parsed per block, so the order of the keys does not matter.
def etiquetas(ruta):
    """(name, color, aliases) of each label of a labels.yml, in order."""
    with open(ruta, encoding="utf-8") as fh:
        texto = fh.read()
    bloques = re.split(r"^- name:", texto, flags=re.M)[1:]
    # The parser reads only this shape: `- name: x` at the start of the line, `  key: value` lines and an `  aliases:` list of
    # `    - "x"` lines. Any other line (inline aliases, an alias with a comment, a bare dash, an indented list, `-   name:`, flow
    # items) would be dropped without a word, so it is an error: the first one is reported, with its line.
    items = len(re.findall(r"^- ", texto, re.M))
    if items != len(bloques) or not bloques:
        errores.append(f"{ruta}: {items} items (`- ` at the start of a line) but {len(bloques)} blocks `- name:` were read: a YAML "
                       "format not supported by this check (write each label as `- name: ...`).")
    valida = (re.compile(r"^\s*(?:#.*)?$"), re.compile(r"^- name: *(?:\"[^\"]*\"|'[^']*'|[^\s#\"'{\[][^#]*?) *$"),
              re.compile(r"^  (?!aliases:)[a-z_]+: *\S.*$"), re.compile(r"^  aliases: *$"))
    alias_ok = re.compile(r"^    - (?:\"[^\"]*\"|'[^']*'|[^\s#\"'{\[][^#]*?) *$")  # exactly one space after the dash: the parser below reads `- ` once
    en_aliases = False  # `    - "x"` lines only count right after `  aliases:` (a stray one would be dropped without a word)
    for n, linea in enumerate(texto.splitlines(), 1):
        if re.match(r"^  aliases: *$", linea):
            en_aliases = True
        elif re.match(r"^(?:- name:|  [a-z_]+:)", linea):
            en_aliases = False
        if not (any(v.match(linea) for v in valida) or (en_aliases and alias_ok.match(linea))):
            errores.append(f"{ruta}:{n}: format not supported by this check (it would be dropped without a word): {linea.strip()[:60]!r}. "
                           "Use `- name:` at the start of the line, `  key: value` lines and `  aliases:` followed by `    - \"x\"` lines.")
            break
    res = []
    for b in bloques:
        nombre = b.splitlines()[0].strip().strip("\"'")
        color = re.search(r"^\s+color: *[\"']?([^\"'\n]+)", b, re.M)
        alias = re.findall(r"^\s+- [\"']?([^\"'\n]+?)[\"']?\s*$", b.split("aliases:", 1)[1], re.M) if "aliases:" in b else []
        res.append((nombre, color.group(1).strip() if color else "", tuple(alias)))
    return res


if MAPA.get("parity"):
    for en in ("profiles/small/.github/labels.yml", ".github/labels.yml"):
        if not os.path.exists(en) or any(r.match(en) for r in EXENTOS):
            continue
        es = hermano_de_idioma(en)
        if not os.path.exists(es):
            errores.append(f"{en}: missing its Spanish sibling {es}.")
        elif etiquetas(en) != etiquetas(es):
            errores.append(f"{es}: its labels (names, colors or aliases) differ from {en} (one of the two is out of date).")

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
    NIEGA = re.compile(r"\b(?:no|nunca|not|never)\s+(?:(?:est[aá]n?|es|son|se|is|are|be)\s+)?ignor|n['’]t\s+(?:be\s+)?ignor", re.I)
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
