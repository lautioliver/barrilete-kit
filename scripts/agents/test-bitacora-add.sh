#!/usr/bin/env bash
# shellcheck disable=SC2319,SC2154  # "<condición>; tap_check $?" es el patrón de los tests (tap.sh); tap_run asigna out
# Tests de scripts/agents/bitacora_add.py (#343): /bitacora <tema> suma entradas a docs/bitacora.html, un archivo
# por proyecto y versionado. find dice si el tema ya tiene sección (o una parecida); add solo inserta: sección nueva
# al final, entrada al final de su sección, link al final del índice. Nunca reescribe lo que había.
# No usa red ni GitHub. Uso: bash scripts/agents/test-bitacora-add.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
ADD="$RAIZ/scripts/agents/bitacora_add.py"
CSS="$RAIZ/scripts/agents/bitacora/barrilete.css"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-bitacora-add-XXXXXX")
TMP=$(cd "$TMP" && pwd)
# shellcheck disable=SC2016  # se expande al salir, no ahora
tap_at_exit 'rm -rf "$TMP"'
HOY=$(date +%F)

git init -q "$TMP/p"
git -C "$TMP/p" commit -q --allow-empty -m base
mkdir -p "$TMP/p/sub"
pagina="$TMP/p/docs/bitacora.html"
printf '<p>Primera entrada: decidimos <strong>docs/bitacora.html</strong>.</p>\n' >"$TMP/e1.html"
printf '<div class="kpis"><div class="kpi ok"><b>3</b> hechos</div></div>\n<p>Segunda entrada del mismo tema.</p>\n' >"$TMP/e2.html"
printf '<table class="tbl"><tr><th>antes</th><th>después</th></tr><tr><td>114 tarjetas</td><td>secciones</td></tr></table>\n' >"$TMP/e3.html"

# Lee la página y resume su forma: secciones en orden con cuántas entradas tiene cada una, el orden del índice
# y si alguna entrada no tiene fecha.
cat >"$TMP/forma.py" <<'EOF'
import re, sys
p = open(sys.argv[1], encoding="utf-8").read()
nav = re.search(r"<nav\b.*?</nav>", p, re.S)
links = re.findall(r'href="#([^"]+)"', nav.group(0)) if nav else []
secs = re.findall(r'<section id="([^"]+)"(.*?)</section>', p, re.S)
ENTRADA = r'<article class="entrada"'   # fuera del f-string: con la barra adentro no corre antes de Python 3.12
resumen = " ".join(f"{i}:{len(re.findall(ENTRADA, c))}" for i, c in secs)
sin_fecha = sum(1 for _, c in secs for a in re.findall(r'<article class="entrada".*?</article>', c, re.S)
                if not re.search(r'<time datetime="\d{4}-\d{2}-\d{2}"', a))
print(resumen)
print("indice=" + ("igual" if links and links == [i for i, _ in secs] else " ".join(links)))
print(f"sin_fecha={sin_fecha}" if secs else "sin_secciones")
EOF
forma() { tap_run forma_out 0 python3 -I "$TMP/forma.py" "$pagina"; }

# Compara la versión anterior con la nueva: ok si la nueva solo agrega líneas (lo anterior queda byte a byte) y agrega algo.
cat >"$TMP/inserta.py" <<'EOF'
import difflib, sys
a = open(sys.argv[1], encoding="utf-8").read().splitlines(keepends=True)
b = open(sys.argv[2], encoding="utf-8").read().splitlines(keepends=True)
ops = [op for op in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes() if op[0] != "equal"]
malas = [op for op in ops if op[0] != "insert"]
print("ok" if ops and not malas and len(b) > len(a) else f"ops={ops[:3]}")
EOF

# 1. Sin el archivo: add lo crea con la sección al final, con fecha, el índice y el ancla del tema.
tap_run out 0 python3 -I "$ADD" -C "$TMP/p/sub" add --topic "Decidir la ruta" --entry "$TMP/e1.html"
[ -s "$pagina" ]; tap_check $? "sin archivo, add crea docs/bitacora.html en la raíz del repo"
grep -qF '<section id="decidir-la-ruta" data-topic="Decidir la ruta">' "$pagina"; tap_check $? "la sección se puede enlazar con el slug de su tema"
grep -qF '<a href="#decidir-la-ruta">Decidir la ruta</a>' "$pagina"; tap_check $? "el índice enlaza la sección nueva"
grep -qF "<time datetime=\"$HOY\"" "$pagina"; tap_check $? "la entrada nueva lleva la fecha de hoy"
grep -qF 'decidimos <strong>docs/bitacora.html</strong>' "$pagina"; tap_check $? "la entrada lleva el fragmento tal cual"
[ "$out" = "ok: new decidir-la-ruta $pagina" ]; tap_check $? "add dice en una línea qué hizo y dónde" "$out"

# 2. El mismo tema otra vez: una entrada más abajo, en la misma sección, sin tocar lo anterior.
cp "$pagina" "$TMP/v1.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/p" add --topic "Decidir la ruta" --entry "$TMP/e2.html"
tap_run ins 0 python3 -I "$TMP/inserta.py" "$TMP/v1.html" "$pagina"
[ "$ins" = ok ]; tap_check $? "agregar una entrada deja byte a byte igual lo anterior" "mismo tema: $ins"
[ "$out" = "ok: append decidir-la-ruta $pagina" ]; tap_check $? "add dice que sumó la entrada a la sección" "$out"

# 3. Otro tema: otra sección al final y su link al final del índice.
cp "$pagina" "$TMP/v2.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/p" add --topic "Otro tema" --entry "$TMP/e3.html"
tap_run ins 0 python3 -I "$TMP/inserta.py" "$TMP/v2.html" "$pagina"
[ "$ins" = ok ]; tap_check $? "agregar una entrada deja byte a byte igual lo anterior" "tema nuevo: $ins"
forma
[ "$(sed -n 1p <<<"$forma_out")" = "decidir-la-ruta:2 otro-tema:1" ]; tap_check $? "dos temas son dos secciones y el mismo tema dos veces una sección con dos entradas" "$forma_out"
[ "$(sed -n 2p <<<"$forma_out")" = "indice=igual" ]; tap_check $? "el índice lista las secciones en su orden" "$forma_out"
[ "$(sed -n 3p <<<"$forma_out")" = "sin_fecha=0" ]; tap_check $? "cada entrada lleva su fecha" "$forma_out"

# 4. find: el tema exacto (mismo slug, aunque cambien mayúsculas y acentos), uno nuevo y uno parecido (sale con 3).
tap_run out 0 python3 -I "$ADD" -C "$TMP/p" find --topic "decidir LA rúta"
[ "$out" = "exact decidir-la-ruta" ]; tap_check $? "find reconoce el tema por su slug" "$out"
tap_run out 0 python3 -I "$ADD" -C "$TMP/p" find --topic "Tema sin relación"
[ "$out" = "none tema-sin-relacion" ]; tap_check $? "find con un tema nuevo dice none y el slug" "$out"
tap_run out 3 python3 -I "$ADD" -C "$TMP/p" find --topic "Decidir las rutas"
[ "$TAP_RC" = 3 ]; tap_check $? "find con un nombre parecido sale con 3" "rc=$TAP_RC"
grep -qxF "similar decidir-la-ruta	Decidir la ruta" <<<"$out"; tap_check $? "find lista la sección parecida con su slug y su tema" "$out"
tap_run out 3 python3 -I "$ADD" -C "$TMP/p" find --topic "Otro"
grep -qxF "similar otro-tema	Otro tema" <<<"$out"; tap_check $? "un slug que contiene al otro también es parecido" "$out"

# 5. add con un nombre parecido: sin --new ni --into no escribe y sale con 3; con --into suma a esa; con --new crea otra.
cp "$pagina" "$TMP/v3.html"
tap_run out 3 python3 -I "$ADD" -C "$TMP/p" add --topic "Decidir las rutas" --entry "$TMP/e1.html"
[ "$TAP_RC" = 3 ]; tap_check $? "add con un nombre parecido no escribe sin --new ni --into" "rc=$TAP_RC"
cmp -s "$TMP/v3.html" "$pagina"; tap_check $? "add con un nombre parecido deja el archivo igual"
tap_run out 0 python3 -I "$ADD" -C "$TMP/p" add --topic "Decidir las rutas" --into decidir-la-ruta --entry "$TMP/e1.html"
forma
[ "$(sed -n 1p <<<"$forma_out")" = "decidir-la-ruta:3 otro-tema:1" ]; tap_check $? "add --into suma la entrada a la sección elegida" "$forma_out"
tap_run out 0 python3 -I "$ADD" -C "$TMP/p" add --topic "Decidir las rutas" --new --entry "$TMP/e1.html"
forma
[ "$(sed -n 1p <<<"$forma_out")" = "decidir-la-ruta:3 otro-tema:1 decidir-las-rutas:1" ]; tap_check $? "add --new crea otra sección aunque haya una parecida" "$forma_out"
cp "$pagina" "$TMP/v4.html"
tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic "Otro tema" --new --entry "$TMP/e1.html"
[ "$TAP_RC" = 64 ]; tap_check $? "add --new con un tema que ya existe es un error de uso" "rc=$TAP_RC"
tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic "x" --into no-existe --entry "$TMP/e1.html"
[ "$TAP_RC" = 64 ]; tap_check $? "add --into una sección que no existe es un error de uso" "rc=$TAP_RC"
cmp -s "$TMP/v4.html" "$pagina"; tap_check $? "un error de uso deja el archivo igual"

# 6. Lo que la entrada no puede traer: script, manejadores on…=, javascript:, cierres de la estructura y los marcadores.
for malo in '<script>x()</script>' '<img src=x onerror=x()>' '<p ONCLICK = "x()">' '<a href="javascript:x()">a</a>' \
            '</section><section id="falsa">' '</main>' '</article>' '<!-- bitacora:main -->' '<style>body{}</style>' '<iframe src=x>'; do
  printf '%s\n' "$malo" >"$TMP/malo.html"
  tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic "Otro tema" --entry "$TMP/malo.html"
  [ "$TAP_RC" = 64 ]; tap_check $? "add rechaza una entrada con HTML que rompe la página" "$malo: rc=$TAP_RC"
  cmp -s "$TMP/v4.html" "$pagina"; tap_check $? "una entrada rechazada deja el archivo igual" "$malo"
done
: >"$TMP/vacia.html"
tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic "Otro tema" --entry "$TMP/vacia.html"
[ "$TAP_RC" = 64 ]; tap_check $? "add rechaza una entrada vacía" "rc=$TAP_RC"
tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic "Otro tema" --entry "$TMP/no-existe.html"
[ "$TAP_RC" = 64 ]; tap_check $? "add con una entrada que no existe es un error de uso" "rc=$TAP_RC"
case "$out" in *Traceback*) tap_fail "un error de uso no da traceback" "$out" ;; *) tap_ok "un error de uso no da traceback" ;; esac

# 7. El tema se escribe como texto; uno que no deja slug es un error de uso.
tap_run out 0 python3 -I "$ADD" -C "$TMP/p" add --topic '<b>Ruta</b> & "otra"' --new --entry "$TMP/e1.html"
grep -qF '&lt;b&gt;Ruta&lt;/b&gt; &amp; &quot;otra&quot;' "$pagina"; tap_check $? "el tema se escribe escapado"
grep -qF '<b>Ruta</b>' "$pagina"; es=$?; [ "$es" = 1 ]; tap_check $? "el tema no se interpreta como HTML"
tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic '¡¡ !!' --entry "$TMP/e1.html"
[ "$TAP_RC" = 64 ]; tap_check $? "un tema sin letras ni números es un error de uso" "rc=$TAP_RC"

# 8. Un archivo que no tiene los marcadores (editado a mano) no se toca: sale con 65 y lo dice.
git init -q "$TMP/roto"
mkdir -p "$TMP/roto/docs"
printf '<html><body><main><p>a mano</p></main></body></html>\n' >"$TMP/roto/docs/bitacora.html"
cp "$TMP/roto/docs/bitacora.html" "$TMP/roto.html"
tap_run out 65 python3 -I "$ADD" -C "$TMP/roto" add --topic "x" --entry "$TMP/e1.html"
[ "$TAP_RC" = 65 ]; tap_check $? "un archivo sin los marcadores no se toca y sale con 65" "rc=$TAP_RC"
cmp -s "$TMP/roto.html" "$TMP/roto/docs/bitacora.html"; tap_check $? "un archivo sin los marcadores queda igual"

# 9. Idioma de la instalación: inglés por defecto, español con "language": "es" en .agent-kit.json.
grep -qF '<html lang="en">' "$pagina"; tap_check $? "sin idioma, la página va en inglés"
grep -qF '>Contents<' "$pagina"; tap_check $? "en inglés, el índice se llama Contents"
git init -q "$TMP/es"
printf '{"language": "es"}\n' >"$TMP/es/.agent-kit.json"
tap_run out 0 python3 -I "$ADD" -C "$TMP/es" add --topic "Tema" --entry "$TMP/e1.html"
grep -qF '<html lang="es">' "$TMP/es/docs/bitacora.html"; tap_check $? "con language es, la página va en español"
grep -qF '>Índice<' "$TMP/es/docs/bitacora.html"; tap_check $? "en español, el índice se llama Índice"

# 10. Diseño: barrilete por defecto; .barrilete/bitacora.css pisa los tokens, va después y no puede cerrar su bloque.
grep -qF '<style id="theme-barrilete">' "$pagina"; tap_check $? "la página lleva el tema de barrilete"
git init -q "$TMP/tema"
mkdir -p "$TMP/tema/.barrilete"
printf ':root { --accent: #0E9F6E; }\n/* </style><script>x()</script> */\n' >"$TMP/tema/.barrilete/bitacora.css"
tap_run out 0 python3 -I "$ADD" -C "$TMP/tema" add --topic "Tema" --entry "$TMP/e1.html"
grep -qF -- '--accent: #0E9F6E' "$TMP/tema/docs/bitacora.html"; tap_check $? "el CSS del proyecto entra en la página"
tap_run orden 0 awk '/<style id="theme-barrilete">/ && !b {b=NR} /<style id="theme-project">/ && !p {p=NR} END {print (b && p && p > b) ? "después" : "no"}' "$TMP/tema/docs/bitacora.html"
[ "$orden" = "después" ]; tap_check $? "el CSS del proyecto va después del de barrilete"
grep -qF '</style><script>x()</script>' "$TMP/tema/docs/bitacora.html"; es=$?; [ "$es" = 1 ]; tap_check $? "el CSS del proyecto no puede cerrar su bloque de estilo"
grep -qF 'display=swap' "$pagina"; tap_check $? "las fuentes de Google se cargan sin dejar el texto invisible"
grep -qiF '<script' "$pagina"; es=$?; [ "$es" = 1 ]; tap_check $? "la página no lleva scripts"
for clase in kpis kpi cards card tbl note ok warn danger; do
  grep -qE "\.${clase}[^a-z-]" "$pagina"; tap_check $? "la página trae los estilos de los componentes de una entrada" ".$clase"
done

# 11. Contraste AA del texto y los colores de estado en los dos modos; sin red, fuentes del sistema.
cat >"$TMP/contraste.py" <<'EOF'
"""Lee los tokens de barrilete.css (modo claro y oscuro) y dice qué pares no llegan a WCAG AA (4.5:1)."""
import re, sys
css = open(sys.argv[1], encoding="utf-8").read()
TOKENS = ["--bg", "--surface", "--card", "--ink", "--muted", "--accent", "--ok", "--warn", "--danger"]
def bloque(texto):
    return dict(re.findall(r"(--[a-z-]+)\s*:\s*(#[0-9A-Fa-f]{6})", texto))
oscuro = re.search(r"prefers-color-scheme:\s*dark\)\s*\{(.*?)\}\s*\}", css, re.S)
claro = bloque(css[: oscuro.start()] if oscuro else css)
modos = {"claro": claro, "oscuro": {**claro, **bloque(oscuro.group(1))} if oscuro else {}}
def lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)
malos = []
for modo, t in modos.items():
    faltan = [k for k in TOKENS if k not in t]
    if faltan:
        malos.append(f"{modo}: faltan {' '.join(faltan)}")
        continue
    for texto in ["--ink", "--muted", "--accent", "--ok", "--warn", "--danger"]:
        for fondo in ["--bg", "--surface", "--card"]:
            r = ratio(t[texto], t[fondo])
            if r < 4.5:
                malos.append(f"{modo}: {texto} sobre {fondo} {r:.2f}")
print("ok" if not malos else "; ".join(malos))
EOF
tap_run out 0 python3 -I "$TMP/contraste.py" "$CSS"
[ "$out" = ok ]; tap_check $? "el texto y los colores de estado de barrilete cumplen AA en los dos modos" "$out"
grep -qE -- '--font-display:.*(system-ui|sans-serif)' "$CSS"; tap_check $? "sin red, los títulos caen en una fuente del sistema"
grep -qE -- '--font-mono:.*(ui-monospace|monospace)' "$CSS"; tap_check $? "sin red, el texto mono cae en una fuente del sistema"

# 12. El archivo se versiona, el script no suma dependencias y lo de #339 no queda.
grep -qF 'bitacora.html' "$RAIZ/.gitignore"; es=$?; [ "$es" = 1 ]; tap_check $? "la bitácora no está en el .gitignore del kit"
cat >"$TMP/deps.py" <<'EOF'
import ast, sys
# Una lista fija y no sys.stdlib_module_names, que no existe antes de Python 3.10 (el de macOS es 3.9).
ESTANDAR = {"argparse", "datetime", "difflib", "html", "json", "os", "re", "subprocess", "sys", "tempfile", "unicodedata"}
arbol = ast.parse(open(sys.argv[1], encoding="utf-8").read())
mods = {a.name.split(".")[0] for n in ast.walk(arbol) if isinstance(n, ast.Import) for a in n.names}
mods |= {n.module.split(".")[0] for n in ast.walk(arbol) if isinstance(n, ast.ImportFrom) and n.module and not n.level}
print(" ".join(sorted(m for m in mods if m not in ESTANDAR)) or "ok")
EOF
tap_run out 0 python3 -I "$TMP/deps.py" "$ADD"
[ "$out" = ok ]; tap_check $? "bitacora_add.py usa solo la biblioteca estándar" "$out"
[ ! -e "$RAIZ/scripts/agents/bitacora.py" ]; tap_check $? "ya no está scripts/agents/bitacora.py"
[ ! -e "$RAIZ/scripts/agents/test-bitacora.sh" ]; tap_check $? "ya no está scripts/agents/test-bitacora.sh"
cat >"$TMP/nombran.py" <<'EOF'
import os, re, subprocess, sys
raiz = sys.argv[1]
archivos = subprocess.run(["git", "-C", raiz, "ls-files", "-z"], capture_output=True, text=True, check=True).stdout.split("\0")
viejo = re.compile(r"(?<![\w-])(bitacora\.py|test-bitacora\.sh)")
hits = []
for f in archivos:
    ruta = os.path.join(raiz, f)
    if not f or f == "scripts/agents/test-bitacora-add.sh" or not os.path.isfile(ruta):
        continue
    try:
        texto = open(ruta, encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        continue
    if viejo.search(texto):
        hits.append(f)
print(" ".join(hits) or "ok")
EOF
tap_run out 0 python3 -I "$TMP/nombran.py" "$RAIZ"
[ "$out" = ok ]; tap_check $? "ningún archivo nombra bitacora.py ni test-bitacora.sh" "$out"

# 13. El skill /bitacora existe en inglés y español y usa find antes de escribir.
cat >"$TMP/contiene.py" <<'EOF'
import sys
try:
    texto = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    print("no está")
else:
    print("sí" if sys.argv[2] in texto else "no")
EOF
# En la plantilla van los dos idiomas; en un proyecto instalado, el init deja solo SKILL.md (en su idioma).
tap_run plantilla 0 python3 -I -c 'import os, sys; print("sí" if os.path.isdir(sys.argv[1]) else "no")' "$RAIZ/profiles"
archivos="SKILL.md"
case "$plantilla" in sí) archivos="SKILL.md SKILL.es.md" ;; esac
for f in $archivos; do
  tap_run out 0 python3 -I "$TMP/contiene.py" "$RAIZ/.claude/skills/bitacora/$f" "bitacora_add.py find"
  [ "$out" = sí ]; tap_check $? "el skill /bitacora busca la sección con find antes de escribir, en inglés y español" "$f: $out"
  tap_run out 0 python3 -I "$TMP/contiene.py" "$RAIZ/.claude/skills/bitacora/$f" "--into"
  [ "$out" = sí ]; tap_check $? "el skill dice cómo seguir cuando la persona elige la sección parecida" "$f: $out"
done

# 14. Revisión: solo pasa HTML de la lista permitida, aunque se esconda con /, comillas o entidades.
for malo in '<img/src=x/onerror=x()>' '<img alt=">" onerror=x() src=x>' '<a href="jav&#x61;script:x()">a</a>' \
            '<a href="data:text/html,x">a</a>' '<a href="vbscript:x">a</a>' '<textarea>a</textarea>' \
            '<p style="background:url(x)">a</p>' '<p/onclick=x()>a</p>' '<svg><a>x</a></svg>' '<p id="decidir-la-ruta">a</p>'; do
  printf '%s\n' "$malo" >"$TMP/malo.html"
  tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic "Otro tema" --entry "$TMP/malo.html"
  [ "$TAP_RC" = 64 ]; tap_check $? "add rechaza una entrada con HTML fuera de la lista permitida" "$malo: rc=$TAP_RC"
done
cat >"$TMP/bueno.html" <<'EOF'
<div class="kpis"><div class="kpi ok"><b>12</b> casos</div><div class="kpi warn"><b>2</b> abiertos</div></div>
<div class="cards"><div class="card danger"><h3>Te espera a vos</h3><p>Validar <a href="https://example.test/x">esto</a> y <a href="#otro-tema">aquello</a>.</p></div></div>
<table class="tbl"><thead><tr><th>Antes</th><th>Después</th></tr></thead><tbody><tr><td colspan="2"><code>x</code></td></tr></tbody></table>
<div class="bars"><div class="bar ok"><span>Hecho</span><i style="--v:70%"></i></div></div>
<ol class="flow"><li>issue</li><li>rojo</li></ol>
<div class="note warn"><p><span class="ok">hecho</span><br><em>y</em> <strong>z</strong></p></div>
<ul><li>uno</li></ul>
EOF
tap_run out 0 python3 -I "$ADD" -C "$TMP/p" add --topic "Otro tema" --entry "$TMP/bueno.html"
[ "$TAP_RC" = 0 ]; tap_check $? "add acepta los componentes que lista el skill" "$out"

# 15. Revisión: un archivo con CRLF (checkout de Windows) se lee igual y no duplica la sección.
git init -q "$TMP/crlf"
tap_run out 0 python3 -I "$ADD" -C "$TMP/crlf" add --topic "Tema" --entry "$TMP/e1.html"
tap_run out 0 python3 -I -c 'import sys; p=sys.argv[1]; t=open(p, newline="").read(); open(p, "w", newline="").write(t.replace("\n", "\r\n"))' "$TMP/crlf/docs/bitacora.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/crlf" find --topic "Tema"
[ "$out" = "exact tema" ]; tap_check $? "con CRLF, find encuentra la sección" "$out"
tap_run out 0 python3 -I "$ADD" -C "$TMP/crlf" add --topic "Tema" --entry "$TMP/e2.html"
tap_run forma_out 0 python3 -I "$TMP/forma.py" "$TMP/crlf/docs/bitacora.html"
[ "$(sed -n 1p <<<"$forma_out")" = "tema:2" ]; tap_check $? "con CRLF, la entrada se suma a la sección que ya estaba" "$forma_out"

# 16. Revisión: el archivo queda legible para todos (umask) y conserva su modo al sumar entradas.
modo() { tap_run modo_out 0 python3 -I -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"; }
git init -q "$TMP/modo"
umask 022
tap_run out 0 python3 -I "$ADD" -C "$TMP/modo" add --topic "Tema" --entry "$TMP/e1.html"
modo "$TMP/modo/docs/bitacora.html"
[ "$modo_out" = 0o644 ]; tap_check $? "un archivo nuevo sigue el umask" "$modo_out"
chmod 664 "$TMP/modo/docs/bitacora.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/modo" add --topic "Tema" --entry "$TMP/e2.html"
modo "$TMP/modo/docs/bitacora.html"
[ "$modo_out" = 0o664 ]; tap_check $? "sumar una entrada conserva el modo del archivo" "$modo_out"

# 17. Revisión: un tema no puede tomar el id de un bloque de la página.
for t in "Theme barrilete" "Theme project" "Structure"; do
  tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic "$t" --entry "$TMP/e1.html"
  [ "$TAP_RC" = 64 ]; tap_check $? "un tema con el id de un bloque de la página es un error de uso" "$t: rc=$TAP_RC"
done

# 18. Revisión: el modo --small no lleva este test (no tiene quien lo corra) y el hub de docs lista el skill.
tap_run out 0 python3 -I "$TMP/contiene.py" "$RAIZ/profiles/small/DELETE" "scripts/agents/test-bitacora-add.sh"
# En la plantilla el archivo tiene que estar; "no está" solo vale en un proyecto instalado (sin profiles/).
case "$plantilla:$out" in *:sí|no:"no está") tap_ok "el modo --small no lleva el test de la bitácora" ;; *) tap_fail "el modo --small no lleva el test de la bitácora" "$out" ;; esac
# shellcheck disable=SC2016  # las comillas invertidas son parte del texto que se busca
tap_run out 0 python3 -I "$TMP/contiene.py" "$RAIZ/docs/README.md" '`orchestrate`, `bitacora`'
[ "$out" = sí ]; tap_check $? "el hub de docs lista el skill bitacora" "$out"

# 19. Revisión de #344: un < escrito como entidad pasa (el skill lo pide así), el texto puede nombrar on…= y
# javascript:, el autocierre de una etiqueta que no es vacía no cuenta como cierre y el rechazo apunta al skill.
git init -q "$TMP/rev"
for bueno in '<p>la latencia baja a &lt; 200 ms</p>' '<p>corré <code>/bitacora &lt;tema&gt;</code></p>' \
             '<p>a &#60; b</p>' '<p>la lista bloquea <code>onclick=</code> y <code>javascript:</code></p>' \
             '<p>online=true</p>'; do
  printf '%s\n' "$bueno" >"$TMP/bueno.html"
  tap_run out 0 python3 -I "$ADD" -C "$TMP/rev" add --topic "Tema" --entry "$TMP/bueno.html"
  [ "$TAP_RC" = 0 ]; tap_check $? "add acepta un < escrito como entidad y texto que nombra on…= o javascript:" "$bueno: rc=$TAP_RC $out"
done
for malo in '<p>a < b</p>' '<p onclick=x()>a</p>' '<p/onclick=x()>a</p>'; do
  printf '%s\n' "$malo" >"$TMP/malo.html"
  tap_run out 64 python3 -I "$ADD" -C "$TMP/rev" add --topic "Tema" --entry "$TMP/malo.html"
  [ "$TAP_RC" = 64 ]; tap_check $? "add sigue rechazando un < suelto y un manejador on…= en una etiqueta" "$malo: rc=$TAP_RC"
done
for malo in '<p><b/>x</p>' '<p><a href="https://example.test/x"/>x</p>' '<div/>' '<ul/>'; do
  printf '%s\n' "$malo" >"$TMP/malo.html"
  tap_run out 64 python3 -I "$ADD" -C "$TMP/rev" add --topic "Tema" --entry "$TMP/malo.html"
  [ "$TAP_RC" = 64 ]; tap_check $? "add rechaza el autocierre de una etiqueta que no es vacía" "$malo: rc=$TAP_RC"
done
printf '<p>uno<br/>dos</p>\n<hr/>\n' >"$TMP/bueno.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/rev" add --topic "Tema" --entry "$TMP/bueno.html"
[ "$TAP_RC" = 0 ]; tap_check $? "add acepta <br/> y <hr/>" "rc=$TAP_RC $out"
printf '<script>x()</script>\n' >"$TMP/malo.html"
tap_run out 64 python3 -I "$ADD" -C "$TMP/rev" add --topic "Tema" --entry "$TMP/malo.html"
case "$out" in *".claude/skills/bitacora/SKILL.md"*) es=sí ;; *) es=no ;; esac
[ "$es" = sí ]; tap_check $? "el rechazo apunta al skill, que también está en el modo --small" "$out"

# 20. Segunda revisión de #344: un link o un title que traen "on…=" en su valor pasan (no son manejadores), y las
# defensas que ningún caso cuidaba: una etiqueta sin cerrar, style fuera del ancho de una barra, declaraciones y
# formas raras que el navegador se come hasta el próximo >, y el fin de línea de lo que se inserta en un archivo CRLF.
git init -q "$TMP/rev2"
for bueno in '<p><a href="https://x.test/list?only=open">lista</a></p>' \
             '<p><a href="https://x.test/?a=1&amp;online=1">lista</a></p>' '<p title="the onion=1">a</p>'; do
  printf '%s\n' "$bueno" >"$TMP/bueno.html"
  tap_run out 0 python3 -I "$ADD" -C "$TMP/rev2" add --topic "Tema" --entry "$TMP/bueno.html"
  [ "$TAP_RC" = 0 ]; tap_check $? "add acepta un valor de atributo que contiene on…=" "$bueno: rc=$TAP_RC $out"
done
for malo in '<p>abierta' '<div><p>a</p>' '<i style="position:fixed;inset:0">x</i>' '<!x>' '</ x>' '<!DOCTYPE html>'; do
  printf '%s\n' "$malo" >"$TMP/malo.html"
  tap_run out 64 python3 -I "$ADD" -C "$TMP/rev2" add --topic "Tema" --entry "$TMP/malo.html"
  [ "$TAP_RC" = 64 ]; tap_check $? "add rechaza una etiqueta sin cerrar, un style que no es una barra y las declaraciones" "$malo: rc=$TAP_RC"
done
git init -q "$TMP/crlf2"
tap_run out 0 python3 -I "$ADD" -C "$TMP/crlf2" add --topic "Tema" --entry "$TMP/e1.html"
tap_run out 0 python3 -I -c 'import sys; p=sys.argv[1]; t=open(p, newline="").read(); open(p, "w", newline="").write(t.replace("\n", "\r\n"))' "$TMP/crlf2/docs/bitacora.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/crlf2" add --topic "Otro" --entry "$TMP/e2.html"
tap_run out 0 python3 -I -c 'import sys, re; t=open(sys.argv[1], newline="").read(); print(len(re.findall(r"(?<!\r)\n", t)))' "$TMP/crlf2/docs/bitacora.html"
[ "$out" = 0 ]; tap_check $? "en un archivo CRLF, lo que se inserta también va con CRLF" "saltos sin CR: $out"
tap_run out 0 python3 -I -c 'import sys; print(open(sys.argv[1], newline="").read().count("\r"))' "$pagina"
[ "$out" = 0 ]; tap_check $? "en un archivo LF, lo que se inserta no trae CR" "CR: $out"

# 21. Tercera revisión de #344: una entrada que termina en una etiqueta a medias (el navegador se comería el cierre
# del <article> como atributos), una class que no es una lista de clases, un </br> (el navegador lo vuelve un <br>
# y no cierra nada), links a otro sitio sin esquema (//host, \\host) y un archivo con una sección sin su marcador.
git init -q "$TMP/rev3"
for malo in '<p>a</p><a href="x' '<p>a</p>
<b' '<p>a</p><b ' '<p>a</p></b' '<p>a</p><' '<p class="a;b">x</p>' '<p>a</br>b</p>' \
            '<p><a href="//x.test/y">a</a></p>' '<p><a href="\\x.test\y">a</a></p>' '<p><a href="/\x.test">a</a></p>'; do
  printf '%s\n' "$malo" >"$TMP/malo.html"
  tap_run out 64 python3 -I "$ADD" -C "$TMP/rev3" add --topic "Tema" --entry "$TMP/malo.html"
  [ "$TAP_RC" = 64 ]; tap_check $? "add rechaza una etiqueta a medias al final, una class rara, </br> y links sin esquema a otro sitio" "$malo: rc=$TAP_RC"
done
printf '<p><a href="/docs/x.md">a</a> y <a href="docs/y.md">b</a></p>\n' >"$TMP/bueno.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/rev3" add --topic "Tema" --entry "$TMP/bueno.html"
[ "$TAP_RC" = 0 ]; tap_check $? "add acepta links relativos a la raíz y a la carpeta" "rc=$TAP_RC $out"
git init -q "$TMP/sinfin"
tap_run out 0 python3 -I "$ADD" -C "$TMP/sinfin" add --topic "Tema" --entry "$TMP/e1.html"
tap_run out 0 python3 -I -c 'import sys; p=sys.argv[1]; t=open(p).read(); open(p, "w").write(t.replace("<!-- bitacora:end tema -->", ""))' "$TMP/sinfin/docs/bitacora.html"
cp "$TMP/sinfin/docs/bitacora.html" "$TMP/sinfin-antes.html"
tap_run out 65 python3 -I "$ADD" -C "$TMP/sinfin" add --topic "Otro" --entry "$TMP/e2.html"
[ "$TAP_RC" = 65 ]; tap_check $? "con una sección sin su marcador de fin, add no escribe y dice que el archivo está roto" "rc=$TAP_RC $out"
cmp -s "$TMP/sinfin-antes.html" "$TMP/sinfin/docs/bitacora.html"; tap_check $? "con el archivo roto, add no lo toca"

tap_done
