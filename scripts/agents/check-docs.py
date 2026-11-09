#!/usr/bin/env python3
"""Validates the documentation as infrastructure for agents. Exits with 1 if there are errors.

Checks:
- Relative Markdown links ([text](path)) that point to missing files.
- Paths in backticks (`dir/file.ext`) whose first directory exists but the file does not.
- Mentions of ADR-NNN with no file in docs/decisions/ or docs/decisions/kit/.
- ADRs missing from docs/README.md or docs/llms.txt (and from their Spanish siblings, if they exist); a kit ADR with
  `Scope: kit` (the init only deletes `Ámbito: kit`) is a warning, and so is a docs/decisions/kit/ ADR missing from an
  index in a project (no scripts/init-template.sh).
- Required documents and paths of docs/agents-map.json that do not exist.
- The `red` section of the map (ADR-002 D2): an array of stacks with name (unique), when (non-empty list of globs), run
  (with {out}), format (junit) and an optional timeout (positive integer); there is no `report` field.
- The `contexts` section of the map (ADR-003 D3): name unique, paths that match tracked files (unless optional, with ?), and
  depends_on with names of the section and no self-dependency.
- The glossary and the map of contexts (ADR-003 D2, D5): docs/glossary.md and docs/contexts.md in --small, and
  docs/reference/glossary.md and docs/reference/contexts.md in the full profile, present and linked from their index. Their
  content is not checked. An error in the kit itself, a warning in a project (no scripts/init-template.sh).
- Example paths (TODO/...) and checks without a command left in docs/agents-map.json
  after the init.
- Map paths (docs, sensitive, verify) that match no file (except the ones marked as optional
  with a leading "?"); warns about code folders the map does not cover.
- What AGENTS.md says is ignored (`.env*`...) and git does not ignore.
- docs/agents/classes.yml (ADR-006 D4): readable UTF-8 (a BOM is fine), at least one class, only `- id: <kebab-case>` followed by
  `  description: <plain text>` (no quotes or YAML syntax that a real parser would read differently), ids not repeated and not
  a word YAML 1.1 reads as a boolean or null (y, n, yes, no, true, false, on, off, null), one description on each one, and
  `other` (reserved) not listed. One mistake, one error: a quoted id is reported once and still counts as a class. The classes ([id]) that review-pr names exist in it; if the
  file is missing, unreadable or empty, that is its own error and the skill is not blamed for each tag.
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
    """Kit paths according to .agent-kit.json, or None if it does not exist or says `template: true` (the template: everything is kit)."""
    if not os.path.exists(".agent-kit.json"):
        return None
    try:
        with open(".agent-kit.json", encoding="utf-8") as fh:
            manifiesto = json.load(fh)
        if isinstance(manifiesto, dict) and manifiesto.get("template") is True:
            return None  # the template's own manifest (it only names its project): everything is kit
        archivos = manifiesto["files"]
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
hermano_de_idioma = None  # small mode has no agents_map.py and its map has only `red`: parity (the only user) is off there
SOLO_RED = bool(MAPA) and set(MAPA) <= {"red"}  # small mode: its map has only the `red` section, so there are no paths to validate
if MAPA and not SOLO_RED:
    # A full map needs agents_map.py: without it this fails here, closed, and not later.
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

# Not checked in a repo where install.py put the kit (INSTALADO): there every ADR is the project's and its indices are the project's
# too. In a project created from the template the ADRs of docs/decisions/kit/ are installed (kit/ADR-002, D11) and its indices are checked,
# but a kit ADR missing from them is only a warning there (below).
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
                mensaje = f"{indice}: the ADR kit/{f} is missing from the index"
                # Only the kit itself (where the init is still there) requires it as an error. In a project, a three-way merge of
                # update.py can leave the index without the line of a kit ADR: that must not turn its docs CI red after a routine update.
                if os.path.exists("scripts/init-template.sh"):
                    errores.append(mensaje)
                else:
                    avisos.append(mensaje + " (add its line: the update of the kit brings the ADR but may not merge the index)")

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

# docs/decisions/kit/ holds the kit ADRs that the projects install (kit/ADR-002, D11): the init deletes only the `Ámbito: kit` ones of
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
EXENTOS = [glob_a_regex(g) for g in MAPA.get("parity_ignore", [])] if MAPA.get("parity_ignore") else []
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
# hermano_de_idioma is imported at the top, with the map: small mode deletes agents_map.py, its map has only `red`, and it has no forms or parity.
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

RED_CAMPOS = {"name", "when", "run", "format", "timeout"}


def validar_red(red):
    """Errors of the `red` section (ADR-002 D2): an array of stacks with name, when, run ({out}), format, timeout."""
    if not isinstance(red, list):
        return ["docs/agents-map.json: red must be an array of stacks (name, when, run, format, timeout), like verify (ADR-002 D2)"]
    if not red:
        return ["docs/agents-map.json: red is empty: red.sh rejects an empty section. Declare a stack or remove the section (ADR-002 D2)"]
    errs, nombres = [], set()
    for i, e in enumerate(red):
        if not isinstance(e, dict):
            errs.append(f"docs/agents-map.json: red[{i}] must be an object (name, when, run, format, timeout), not {type(e).__name__}")
            continue
        nombre = e.get("name")
        if not isinstance(nombre, str) or not nombre.strip():
            errs.append(f"docs/agents-map.json: red[{i}] needs a 'name' (a non-empty text): red.sh <stack> picks the entry by it")
            ref = f"red[{i}]"
        else:
            ref = f"red '{nombre}'"
            if not re.fullmatch(r"[A-Za-z0-9._-]+", nombre):
                errs.append(f"docs/agents-map.json: {ref}: 'name' must match [A-Za-z0-9._-]+ (letters, digits, dot, underscore, hyphen): it is part of the path of {{out}} and red.sh rejects any other")
            if nombre in nombres:
                errs.append(f"docs/agents-map.json: {ref} appears more than once: red.sh <stack> would be ambiguous")
            nombres.add(nombre)
        pre = f"docs/agents-map.json: {ref}:"
        when = e.get("when")
        if not (isinstance(when, list) and when and all(isinstance(g, str) and g for g in when)):
            errs.append(f"{pre} 'when' must be a non-empty list of globs of test files")
        run = e.get("run")
        if not isinstance(run, str) or "{out}" not in run:
            errs.append(f"{pre} 'run' must be a command that contains {{out}}: red.sh replaces it with the path where the report is written")
        if e.get("format") == "tap":
            # ADR-002 D8: 2.0.0 removed it. The text is the literal red.sh prints.
            errs.append(f'docs/agents-map.json: red stack \'{nombre}\': format "tap" was removed in 2.0.0; use "junit" (docs/guides/red-per-runner.md)'
                        if isinstance(nombre, str) and nombre.strip() else f'{pre} format "tap" was removed in 2.0.0; use "junit" (docs/guides/red-per-runner.md)')
        elif e.get("format") != "junit":
            errs.append(f"{pre} 'format' must be \"junit\" (it is {e.get('format')!r})")
        if "timeout" in e:
            tm = e["timeout"]
            if isinstance(tm, bool) or not isinstance(tm, int) or tm <= 0:
                errs.append(f"{pre} 'timeout' must be a positive integer (seconds), not {tm!r}")
        if "report" in e:
            errs.append(f"{pre} there is no 'report' field: put {{out}} inside 'run' (ADR-002 D2)")
        otros = sorted(set(e) - RED_CAMPOS - {"report"})
        if otros:
            errs.append(f"{pre} unknown field(s): {', '.join(otros)} (valid: {', '.join(sorted(RED_CAMPOS))})")
    return errs


def validar_contextos(contextos):
    """Errors of the `contexts` section of the map (ADR-003 D3): an array of {name, paths, depends_on}; name unique; paths a
    non-empty list whose globs match a tracked file (unless they start with ?); depends_on only names of the section, and no
    context that depends on itself."""
    if not isinstance(contextos, list):
        return ["docs/agents-map.json: contexts must be an array of {name, paths, depends_on} (ADR-003 D3)"]
    r = subprocess.run(["git", "ls-files"], capture_output=True, text=True)
    archivos = [l for l in r.stdout.splitlines() if l] if r.returncode == 0 else None  # None: no git, the paths are not checked
    nombres = {c.get("name") for c in contextos if isinstance(c, dict) and isinstance(c.get("name"), str) and c.get("name").strip()}
    errs, vistos = [], set()
    for i, c in enumerate(contextos):
        if not isinstance(c, dict):
            errs.append(f"docs/agents-map.json: contexts[{i}] must be an object (name, paths, depends_on)")
            continue
        nombre = c.get("name")
        if not isinstance(nombre, str) or not nombre.strip():
            errs.append(f"docs/agents-map.json: contexts[{i}] needs a 'name' (a non-empty text)")
            ref = f"contexts[{i}]"
        else:
            ref = f"context '{nombre}'"
            if nombre in vistos:
                errs.append(f"docs/agents-map.json: {ref} appears more than once: the names of the contexts must be unique")
            vistos.add(nombre)
        pre = f"docs/agents-map.json: {ref}:"
        paths = c.get("paths")
        if not isinstance(paths, list) or not paths:
            errs.append(f"{pre} 'paths' must be a non-empty list of globs")
        else:
            for g in paths:
                if not isinstance(g, str) or not g:
                    errs.append(f"{pre} every path must be a non-empty glob, not {g!r}")
                elif archivos is not None and not g.startswith("?") and not any(glob_a_regex(g).match(a) for a in archivos):
                    errs.append(f"{pre} the path {g} matches no file. If it moved, update it; if it is optional, start it with ?")
        deps = c.get("depends_on", [])
        if not isinstance(deps, list):
            errs.append(f"{pre} 'depends_on' must be a list of context names")
            continue
        for d in deps:
            if not isinstance(d, str):
                errs.append(f"{pre} depends_on must list context names (text), not {d!r}")
                continue
            if d == nombre:
                errs.append(f"{pre} depends on itself (depends_on lists its own name)")
            elif d not in nombres:
                errs.append(f"{pre} depends_on {d!r} is not the name of a context in this section")
    return errs


if MAPA and "red" in MAPA:
    errores.extend(validar_red(MAPA["red"]))
if MAPA and "contexts" in MAPA:
    errores.extend(validar_contextos(MAPA["contexts"]))

# The glossary and the map of contexts (ADR-003 D2 and D5): the files exist at a fixed path and each one is linked from its index.
# --small (the map has only `red`) uses docs/glossary.md and docs/contexts.md; the full profile uses docs/reference/. Their content
# is not checked (D7): only that they exist and are linked. Not checked in a repo where install.py put the kit (INSTALADO), like the
# other index checks above: there docs/README.md is the project's and the kit's goes to .agent-kit/pending/ (ADR-003, Consequences).


def destinos_de(texto):
    """The link destinations of a Markdown text, read like the broken-link check does: no ``` blocks, no `inline code`."""
    destinos = []
    for linea in sin_codigo(texto).splitlines():
        for destino in LINK.findall(re.sub(r"`[^`]*`", "", linea)):
            destinos.append(destino.strip("<>"))  # [x](<a.md>) is a link to a.md
    return destinos


def enlaza(indice, ruta):
    """True if the index links ruta (any spelling: ./a.md, <a.md>, a.md#section)."""
    with open(indice, encoding="utf-8") as fh:
        destinos = destinos_de(fh.read())
    objetivo = os.path.normpath(ruta)
    for d in destinos:
        if re.match(r"^[a-z]+:", d) or d.startswith("#"):
            continue
        local = d.split("#")[0]
        if local and os.path.normpath(os.path.join(os.path.dirname(indice), local)) == objetivo:
            return True
    return False


if MAPA and not INSTALADO:
    indices = ["docs/README.md", "docs/README.es.md"] + ([] if SOLO_RED else ["docs/llms.txt", "docs/llms.es.txt"])
    # Only the kit itself (where the init is still there) requires it as an error. In a project it is a warning, like the ADR index
    # above: after update.py the kit's README may be left in .agent-kit/pending/ and that must not turn its docs CI red.
    problemas = errores if os.path.exists("scripts/init-template.sh") else avisos
    for ruta in (["docs/glossary.md", "docs/contexts.md"] if SOLO_RED else ["docs/reference/glossary.md", "docs/reference/contexts.md"]):
        if not os.path.exists(ruta):
            problemas.append(f"{ruta} is missing: the glossary and the map of contexts are required (ADR-003 D2, D5)")
            continue
        for indice in indices:
            if os.path.exists(indice) and not enlaza(indice, ruta):
                problemas.append(f"{indice}: does not link {ruta} (ADR-003 D2, D5): add the link to the index")

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
    if not os.path.exists("scripts/init-template.sh") and any(k in mapa for k in ("docs", "sensitive", "verify")):
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

# Finding classes (ADR-006 D4): the ids that review-pr tags findings with must exist in docs/agents/classes.yml.
# `other` is reserved (no class fits) and is not listed there. Only the review-pr skill (en and es) is checked; if classes.yml is missing, it is an error only when a line of the skill points to it.
CLASES_YML = "docs/agents/classes.yml"
SKILLS_CLASES = (".claude/skills/review-pr/SKILL.md", ".claude/skills/review-pr/SKILL.es.md")
KEBAB = r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*"
YAML11 = {"y", "n", "yes", "no", "true", "false", "on", "off", "null"}  # kebab-case words YAML 1.1 reads as a boolean or null
ids_clases = None  # None: no usable list of classes (missing, unreadable or empty file), so the skill's tags are not checked
if os.path.exists(CLASES_YML):
    # A strict reader of the file (no YAML library): `- id: <kebab-case>` followed by `  description: <text>`, nothing else.
    ids_leidos = set()
    actual = None  # [id, line, has_description]
    def cerrar():
        if actual and actual[0] and not actual[2]:
            errores.append(f"{CLASES_YML}:{actual[1]}: the class [{actual[0]}] has no description.")
    legible = True
    try:
        with open(CLASES_YML, encoding="utf-8-sig") as f:  # utf-8-sig: a BOM is not part of the first line
            lineas_yml = f.read().splitlines()
    except UnicodeDecodeError as e:
        errores.append(f"{CLASES_YML}: is not valid UTF-8 ({e.reason} at byte {e.start}).")
        lineas_yml, legible = [], False
    except OSError as e:  # a directory, no read permission...: its own error, and the rest of the checks still run
        errores.append(f"{CLASES_YML}: cannot be read ({e.strerror or e}).")
        lineas_yml, legible = [], False
    for n, linea in enumerate(lineas_yml, 1):
        linea = linea.rstrip()  # trailing spaces or a CR (CRLF files) are not part of the value
        if not linea.strip() or linea.lstrip().startswith("#"):
            continue
        m_id = re.fullmatch(r"- id: (" + KEBAB + ")", linea)
        # A plain scalar a real YAML parser reads as the same text (conservative): it starts with a letter or a digit (no quote,
        # flow, tag, "- ", "? ", ", " or "] "), has no ":" before a space or at the end and no "#" after a space or a tab.
        m_desc = re.fullmatch(r"  description: (\w.*)", linea)
        if m_desc and re.search(r":(\s|$)|\s#", m_desc.group(1)):
            m_desc = None
        # A line that tries to be an id but is not well written (quotes, `- ID:`, a comment, two spaces...): one error, and if
        # the id can still be told it counts as a class, so its description is not a second error and the skill is not blamed.
        m_clave = None if m_id else re.match(r"\s*-\s*id\s*:(.*)", linea, re.I)
        if m_id or m_clave:
            cerrar()
            if m_id:
                cid = m_id.group(1)
            else:
                valor = re.sub(r"\s#.*", "", m_clave.group(1)).strip()
                citado = re.fullmatch(r"([\"'])(.*)\1", valor)
                valor = citado.group(2) if citado else valor
                cid = valor if re.fullmatch(KEBAB, valor) else None
                if citado and cid:
                    errores.append(f"{CLASES_YML}:{n}: the id [{cid}] is quoted (unexpected line: write `- id: <kebab-case>`, unquoted).")
                else:
                    errores.append(f"{CLASES_YML}:{n}: unexpected line (expected `- id: <kebab-case>`, unquoted, with one space and no comment).")
            if m_id and cid in YAML11:  # quoted, it is already text: the quotes are the error
                errores.append(f"{CLASES_YML}:{n}: the id [{cid}] is a boolean or null in YAML 1.1, so a YAML parser would not "
                               "read it as text: pick another id.")
            if cid == "other":
                errores.append(f"{CLASES_YML}:{n}: `other` is reserved (review-pr uses it when no class fits): do not list it.")
            if cid and cid in ids_leidos:
                errores.append(f"{CLASES_YML}:{n}: duplicate class id [{cid}].")
            if cid:
                ids_leidos.add(cid)
            actual = [cid, n, False]
        elif m_desc and actual and not actual[2]:
            actual[2] = True
        elif actual and actual[2] and re.fullmatch(r"  description:.*", linea):
            quien = f"the class [{actual[0]}]" if actual[0] else "this entry"
            errores.append(f"{CLASES_YML}:{n}: {quien} has a second description: leave a single valid one.")
        else:
            if actual and re.fullmatch(r"  description:.*", linea):
                actual[2] = True  # one mistake, one error: a bad description is reported as such, not also as a missing one
            errores.append(f"{CLASES_YML}:{n}: unexpected line (expected `- id: <kebab-case>` and `  description: <text>`, unquoted).")
    cerrar()
    if ids_leidos:
        ids_clases = ids_leidos
    elif legible:
        errores.append(f"{CLASES_YML}: lists no classes (expected at least one `- id: <kebab-case>` with its description).")
# A missing classes.yml is reported by the broken-paths check above; an unreadable or empty one, just above.
for ruta in SKILLS_CLASES if ids_clases is not None else ():
    if not os.path.exists(ruta):
        continue
    with open(ruta, encoding="utf-8") as f:
        lineas_skill = f.read().splitlines()
    for n, linea in enumerate(lineas_skill, 1):
        # On the lines of the finding format (they mention file:line or the classes file) every `[...]` is a class,
        # whatever it holds (bold, code span, bare, `[Stale-Doc]`, `[ x y ]`) and must be a known id; a link `[t](u)`,
        # a reference link `[t][r]`, a checkbox `[x]` and `[ ]` are not. `[class]`/`[clase]` are the placeholders.
        if re.search(r"file:line|archivo:línea|\]\s+(?:PR|\S+:\d+):|" + re.escape(CLASES_YML), linea):
            for cid in re.findall(r"(?<!\])\[([^\]\n]+)\](?![(\[])", linea):
                if cid.strip() in ("", "x", "X"):
                    continue
                if cid not in ("other", "class", "clase") and cid not in ids_clases:
                    errores.append(f"{ruta}:{n}: the class [{cid}] is not in {CLASES_YML}. If it is a class, add it there or fix the id; "
                                   "if it is not a class, remove it from this line or write it as a link.")

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
