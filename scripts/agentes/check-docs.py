#!/usr/bin/env python3
"""Valida la documentación como infraestructura para agentes. Sale con 1 si hay errores.

Revisa:
- Links relativos de Markdown ([texto](ruta)) que apuntan a archivos inexistentes.
- Rutas entre backticks (`dir/archivo.ext`) cuyo primer directorio existe pero el archivo no.
- Menciones a ADR-NNN sin archivo en docs/decisions/.
- ADRs que no figuran en docs/README.md o docs/llms.txt.
- Documentos obligatorios y rutas de docs/mapa-agentes.json que no existen.
- Rutas de ejemplo (TODO/…) y verificaciones sin comando que quedaron en docs/mapa-agentes.json
  después del init.
- Rutas del mapa (docs, sensibles, verificar) que no coinciden con ningún archivo (salvo las
  marcadas como opcionales con "?" al principio); avisa de
  carpetas con código que el mapa no cubre.
- Lo que AGENTS.md dice que está ignorado (`.env*`…) y git no ignora.
- Skills (.claude/skills/*/SKILL.md) de más de 120 líneas, y docs/agentes/lecciones.md de más de 40.
- Subagentes (.claude/agents/*.md) sin name, description o tools, con un model que no es opus,
  sonnet ni haiku, o que no remiten al contrato común (docs/agentes/contrato-subagentes.md).
- Integrantes de .github/equipo.json repetidos o con áreas que no están en labels.yml.
Las rutas de "ignorar_check" del mapa (por ejemplo, bitácoras históricas) no se validan.

Si existe .agent-kit.json (el kit instalado en un repo con código propio), los .md se validan solo
si son del kit (los listados en "archivos") o están en docs/, más AGENTS.md y llms.txt. Sin él (la
plantilla), se revisa todo. `--listar <glob>` imprime los archivos del kit que coinciden con el glob
(por ejemplo '*.sh'): lo usa docs.yml para que shellcheck y los tests corran solo sobre el kit.
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
    """Rutas del kit según .agent-kit.json, o None si no existe (la plantilla: todo es del kit)."""
    if not os.path.exists(".agent-kit.json"):
        return None
    return set(json.load(open(".agent-kit.json", encoding="utf-8")).get("archivos", {}))


KIT = archivos_del_kit()
if len(sys.argv) == 3 and sys.argv[1] == "--listar":
    if KIT is None:
        r = subprocess.run(["git", "ls-files"], capture_output=True, text=True)
        todos = r.stdout.splitlines()
    else:
        todos = sorted(a for a in KIT if os.path.isfile(a))
    print("\n".join(a for a in todos if fnmatch.fnmatch(a, sys.argv[2])))
    sys.exit(0)

MAPA = json.load(open("docs/mapa-agentes.json", encoding="utf-8")) if os.path.exists("docs/mapa-agentes.json") else {}
IGNORAR = []
avisos = []
if MAPA:
    # Sin mapa (modo chico) no hay rutas que validar ni hace falta mapa.py.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from mapa import glob_a_regex  # noqa: E402
    IGNORAR = [glob_a_regex(g) for g in MAPA.get("ignorar_check", [])]


def del_alcance(ruta):
    """Con .agent-kit.json, solo los .md del kit, docs/, AGENTS.md y llms.txt."""
    return KIT is None or ruta in KIT or ruta in ("AGENTS.md", "llms.txt") or ruta.startswith("docs/")


def md_files():
    for base, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in IGNORAR_DIRS and not d.startswith(".claude/worktrees")]
        if "/.claude/worktrees" in base:
            continue
        for f in files:
            if f.endswith(".md") or f == "llms.txt":
                ruta = os.path.normpath(os.path.join(base, f))
                if not any(r.match(ruta) for r in IGNORAR) and del_alcance(ruta):
                    yield ruta


def sin_codigo(texto):
    """Quita bloques ``` para no validar ejemplos."""
    return re.sub(r"```.*?```", "", texto, flags=re.S)


adrs = {m.group(1): f for f in os.listdir("docs/decisions") if (m := re.match(r"ADR-(\d{3})-", f))} \
    if os.path.isdir("docs/decisions") else {}

for archivo in md_files():
    with open(archivo, encoding="utf-8") as fh:
        texto = sin_codigo(fh.read())
    carpeta = os.path.dirname(archivo)
    for n, linea in enumerate(texto.splitlines(), 1):
        prosa = re.sub(r"`[^`]*`", "", linea)  # links y ADRs dentro de `código` son ejemplos
        for destino in LINK.findall(prosa):
            if re.match(r"^[a-z]+:", destino) or destino.startswith("#") or "<" in destino:
                continue
            ruta = destino.split("#")[0]
            if ruta and not os.path.exists(os.path.normpath(os.path.join(carpeta, ruta))):
                errores.append(f"{archivo}:{n}: link roto → {destino}")
        for ruta in BACKTICK.findall(linea):
            if "*" in ruta or not EXT.search(ruta):
                continue
            primero = ruta.lstrip("./").split("/")[0]
            if os.path.isdir(primero) and not os.path.exists(ruta) \
                    and not os.path.exists(os.path.join(carpeta, ruta)):
                errores.append(f"{archivo}:{n}: ruta inexistente → `{ruta}`")
        for num in set(ADR.findall(prosa)):
            if num != "000" and num not in adrs:
                errores.append(f"{archivo}:{n}: ADR-{num} no existe en docs/decisions/")

for indice in ("docs/README.md", "docs/llms.txt"):
    if os.path.exists(indice):
        contenido = open(indice, encoding="utf-8").read()
        for num, f in adrs.items():
            if num != "000" and f not in contenido:
                errores.append(f"{indice}: falta el ADR {f} en el índice")

if MAPA:
    mapa = MAPA
    for f in mapa.get("obligatorios", []):
        if not os.path.exists(f):
            errores.append(f"docs/mapa-agentes.json: falta el documento obligatorio {f}")
    # Después del init (el script se borra solo), un "TODO/" en el mapa es una ruta que no existe:
    # el agente nunca marcaría nada como sensible. En la plantilla sin inicializar se permite.
    if not os.path.exists("scripts/init-plantilla.sh"):
        crudo = open("docs/mapa-agentes.json", encoding="utf-8").read()
        pendientes = sorted(set(re.findall(r'"(TODO/[^"]*)"', crudo)))
        if pendientes:
            errores.append("docs/mapa-agentes.json: completá las rutas de ejemplo con las reales del proyecto: "
                           + ", ".join(pendientes))
        sin_comando = [v.get("nombre", "?") for v in mapa.get("verificar", []) if v.get("correr", "").startswith("TODO")]
        if sin_comando:
            errores.append("docs/mapa-agentes.json: verificaciones sin comando (correr empieza con TODO): "
                           + ", ".join(sin_comando) + ". Poné el comando del proyecto o sacá la verificación.")
    for regla in mapa.get("docs", []):
        for f in regla.get("revisar", []):
            if not os.path.exists(f):
                errores.append(f"docs/mapa-agentes.json: '{regla.get('motivo')}' apunta a {f}, que no existe")

    # Rutas del mapa que no coinciden con ningún archivo: si se renombró src/auth/ y el mapa sigue
    # diciendo src/auth/**, el agente nunca vería que tocó algo sensible. Solo después del init.
    if not os.path.exists("scripts/init-plantilla.sh"):
        r = subprocess.run(["git", "ls-files"], capture_output=True, text=True)
        repo = [l for l in r.stdout.splitlines() if l] if r.returncode == 0 else []
        globs = [("docs", regla.get("motivo", ""), g) for regla in mapa.get("docs", []) for g in regla.get("cuando", [])]
        globs += [("sensibles", s.get("tipo", ""), g) for s in mapa.get("sensibles", []) for g in s.get("rutas", [])]
        globs += [("verificar", v.get("nombre", ""), g) for v in mapa.get("verificar", []) for g in v.get("cuando", [])]
        regex = {g: glob_a_regex(g) for _, _, g in globs}
        for seccion, nombre, g in globs:
            if repo and not g.startswith(("TODO/", "?")) and not any(regex[g].match(a) for a in repo):
                errores.append(f"docs/mapa-agentes.json: {seccion} '{nombre}': la ruta {g} no coincide con ningún "
                               "archivo. Si se movió, actualizala; si no aplica al proyecto, sacala.")
        # Carpetas de código que ninguna ruta del mapa cubre: aviso, no error.
        codigo = re.compile(r"\.(ts|tsx|js|jsx|mjs|py|go|rb|rs|java|kt|php|cs|swift|sql)$")
        fuera = {".github", ".claude", "docs", "scripts", "perfiles"}
        conteo = {}
        for a in repo:
            if codigo.search(a) and a.split("/")[0] not in fuera and not any(rx.match(a) for rx in regex.values()):
                carpeta = "/".join(a.split("/")[:-1][:4])  # hasta 4 niveles: apps/web/src/components
                if carpeta.count("/") >= 1:  # los archivos de config en la raíz de un paquete no cuentan
                    conteo[carpeta] = conteo.get(carpeta, 0) + 1
        top = sorted(conteo.items(), key=lambda x: -x[1])[:6]
        if top:
            avisos.append("código que ninguna ruta del mapa cubre (si cambia, nadie avisa qué doc revisar): "
                          + ", ".join(f"{c}/ ({n})" for c, n in top)
                          + (f" y {len(conteo) - 6} carpetas más" if len(conteo) > 6 else ""))

# Equipo (.github/equipo.json): las áreas tienen que existir en labels.yml (los labels pueden
# cambiar después de cargar a alguien) y cada integrante aparece una sola vez.
if os.path.exists(".github/equipo.json"):
    equipo = json.load(open(".github/equipo.json", encoding="utf-8"))
    nombres_labels = set()
    if os.path.exists(".github/labels.yml"):
        for linea in open(".github/labels.yml", encoding="utf-8"):
            if linea.strip().startswith("- name:"):
                nombres_labels.add(linea.split(":", 1)[1].strip().strip('"').strip("'"))
    vistos = set()
    for i in equipo.get("integrantes", []):
        login = (i.get("login") or "").lower()
        if not login:
            errores.append(".github/equipo.json: hay un integrante sin login")
        elif login in vistos:
            errores.append(f".github/equipo.json: @{login} aparece más de una vez")
        vistos.add(login)
        for a in i.get("areas", []):
            if nombres_labels and a not in nombres_labels:
                errores.append(f".github/equipo.json: @{login} tiene el área {a}, que no está en .github/labels.yml")

# Skills largas: el agente se saltea pasos justamente por la cantidad. Si un ajuste
# no entra en el máximo, hay que sacar algo o pasarlo a un script.
MAX_SKILL = 120
if os.path.isdir(".claude/skills"):
    for nombre in sorted(os.listdir(".claude/skills")):
        ruta = os.path.join(".claude/skills", nombre, "SKILL.md")
        if os.path.exists(ruta):
            lineas = sum(1 for _ in open(ruta, encoding="utf-8"))
            if lineas > MAX_SKILL:
                errores.append(f"{ruta}: {lineas} líneas (máximo {MAX_SKILL}). Pasá algo a un script o sacá lo que no aporta.")

# Lo que AGENTS.md dice que está ignorado (`.env*` están ignorados) tiene que estarlo: el agente
# confía en esa frase y, si es falsa, termina commiteando un secreto.
if os.path.exists("AGENTS.md"):
    NIEGA = re.compile(r"\b(?:no|nunca)\s+(?:est[aá]n?\s+|es\s+|son\s+|se\s+)?ignor", re.I)
    for n, linea in enumerate(open("AGENTS.md", encoding="utf-8"), 1):
        if not re.search(r"ignorad", linea, re.I):
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
                errores.append(f"AGENTS.md:{n}: dice que `{patron}` está ignorado, pero {ejemplo} no lo está. "
                               "Agregalo a .gitignore o corregí la frase.")

# Lecciones de las retros: las lee cada agente antes de empezar, así que tienen que ser cortas.
MAX_LECCIONES, LECCIONES = 40, "docs/agentes/lecciones.md"
if os.path.exists(LECCIONES):
    lineas = sum(1 for _ in open(LECCIONES, encoding="utf-8"))
    if lineas > MAX_LECCIONES:
        errores.append(f"{LECCIONES}: {lineas} líneas (máximo {MAX_LECCIONES}). Sacá la lección más vieja o la que ya pasó a una skill.")

# Subagentes: el orquestador elige el modelo por rol, y todos devuelven la misma salida.
CONTRATO, AGENTES = "docs/agentes/contrato-subagentes.md", ".claude/agents"
if os.path.isdir(AGENTES):
    for nombre in sorted(os.listdir(AGENTES)):
        if not nombre.endswith(".md"):
            continue
        ruta = os.path.join(AGENTES, nombre)
        texto = open(ruta, encoding="utf-8").read()
        m = re.match(r"---\n(.*?)\n---\n", texto, re.S)
        campos = {k: v.strip().strip("'\"") for k, v in re.findall(r"^(\w+): *(.*)$", m.group(1), re.M)} if m else {}
        for campo in ("name", "description", "tools"):
            if not campos.get(campo):
                errores.append(f"{ruta}: falta '{campo}:' en el frontmatter.")
        if campos.get("model") not in ("opus", "sonnet", "haiku"):
            errores.append(f"{ruta}: model '{campos.get('model', '')}' (tiene que ser opus, sonnet o haiku: el modelo es parte del rol, no se hereda).")
        if CONTRATO not in texto:
            errores.append(f"{ruta}: no remite al contrato común ({CONTRATO}).")

for a in avisos:
    print(f"Aviso: {a}")
errores = list(dict.fromkeys(errores))
if errores:
    print(f"Documentación con {len(errores)} problema(s):")
    for e in errores:
        print(f"- {e}")
    sys.exit(1)
print("Documentación OK.")
