#!/usr/bin/env bash
# shellcheck disable=SC2319,SC2154  # "<condición>; tap_check $?" es el patrón de los tests (tap.sh); tap_run asigna out
# Tests de scripts/agents/bitacora_add.py (#343, #365): /bitacora <tema> suma entradas a la bitácora del proyecto,
# versionada y partida por mes: docs/bitacora.html es la portada (el índice de meses y el de temas) y las entradas van a
# la página de su mes, docs/bitacora/AAAA-MM.html. find dice si el tema ya existe (o uno parecido); add solo inserta:
# sección nueva al final, entrada al final de su sección, link al final del índice. Nunca reescribe lo que había.
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
MES=${HOY%-*}

git init -q "$TMP/p"
git -C "$TMP/p" commit -q --allow-empty -m base
mkdir -p "$TMP/p/sub"
# La portada y la página del mes en curso, que es donde quedan las entradas (#365).
portada="$TMP/p/docs/bitacora.html"
pagina="$TMP/p/docs/bitacora/$MES.html"
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

# 1. Sin la bitácora: add crea la portada y la página del mes, con la sección al final, con fecha, el índice y el
# ancla del tema.
tap_run out 0 python3 -I "$ADD" -C "$TMP/p/sub" add --topic "Decidir la ruta" --entry "$TMP/e1.html"
[ -s "$portada" ]; tap_check $? "sin archivo, add crea docs/bitacora.html en la raíz del repo"
[ -s "$pagina" ]; tap_check $? "sin archivo, add crea la página del mes en docs/bitacora/ de la raíz del repo"
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
cp -R "$TMP/p/docs" "$TMP/v3"
tap_run out 3 python3 -I "$ADD" -C "$TMP/p" add --topic "Decidir las rutas" --entry "$TMP/e1.html"
[ "$TAP_RC" = 3 ]; tap_check $? "add con un nombre parecido no escribe sin --new ni --into" "rc=$TAP_RC"
diff -rq "$TMP/v3" "$TMP/p/docs" >/dev/null; tap_check $? "add con un nombre parecido deja el archivo igual"
tap_run out 0 python3 -I "$ADD" -C "$TMP/p" add --topic "Decidir las rutas" --into decidir-la-ruta --entry "$TMP/e1.html"
forma
[ "$(sed -n 1p <<<"$forma_out")" = "decidir-la-ruta:3 otro-tema:1" ]; tap_check $? "add --into suma la entrada a la sección elegida" "$forma_out"
tap_run out 0 python3 -I "$ADD" -C "$TMP/p" add --topic "Decidir las rutas" --new --entry "$TMP/e1.html"
forma
[ "$(sed -n 1p <<<"$forma_out")" = "decidir-la-ruta:3 otro-tema:1 decidir-las-rutas:1" ]; tap_check $? "add --new crea otra sección aunque haya una parecida" "$forma_out"
cp -R "$TMP/p/docs" "$TMP/v4"
tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic "Otro tema" --new --entry "$TMP/e1.html"
[ "$TAP_RC" = 64 ]; tap_check $? "add --new con un tema que ya existe es un error de uso" "rc=$TAP_RC"
tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic "x" --into no-existe --entry "$TMP/e1.html"
[ "$TAP_RC" = 64 ]; tap_check $? "add --into una sección que no existe es un error de uso" "rc=$TAP_RC"
diff -rq "$TMP/v4" "$TMP/p/docs" >/dev/null; tap_check $? "un error de uso deja el archivo igual"

# 6. Lo que la entrada no puede traer: script, manejadores on…=, javascript:, cierres de la estructura y los marcadores.
for malo in '<script>x()</script>' '<img src=x onerror=x()>' '<p ONCLICK = "x()">' '<a href="javascript:x()">a</a>' \
            '</section><section id="falsa">' '</main>' '</article>' '<!-- bitacora:main -->' '<style>body{}</style>' '<iframe src=x>'; do
  printf '%s\n' "$malo" >"$TMP/malo.html"
  tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic "Otro tema" --entry "$TMP/malo.html"
  [ "$TAP_RC" = 64 ]; tap_check $? "add rechaza una entrada con HTML que rompe la página" "$malo: rc=$TAP_RC"
  diff -rq "$TMP/v4" "$TMP/p/docs" >/dev/null; tap_check $? "una entrada rechazada deja el archivo igual" "$malo"
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
grep -qF '&lt;b&gt;Ruta&lt;/b&gt; &amp; &quot;otra&quot;' "$portada"; tap_check $? "el tema se escribe escapado" "portada"
grep -qF '<b>Ruta</b>' "$pagina" "$portada"; es=$?; [ "$es" = 1 ]; tap_check $? "el tema no se interpreta como HTML"
tap_run out 64 python3 -I "$ADD" -C "$TMP/p" add --topic '¡¡ !!' --entry "$TMP/e1.html"
[ "$TAP_RC" = 64 ]; tap_check $? "un tema sin letras ni números es un error de uso" "rc=$TAP_RC"

# 8. Un docs/bitacora.html que no tiene los marcadores (editado a mano) no se toca ni se mueve: sale con 65 y lo dice.
git init -q "$TMP/roto"
mkdir -p "$TMP/roto/docs"
printf '<html><body><main><p>a mano</p></main></body></html>\n' >"$TMP/roto/docs/bitacora.html"
cp -R "$TMP/roto/docs" "$TMP/roto-antes"
tap_run out 65 python3 -I "$ADD" -C "$TMP/roto" add --topic "x" --entry "$TMP/e1.html"
[ "$TAP_RC" = 65 ]; tap_check $? "un archivo sin los marcadores no se toca y sale con 65" "rc=$TAP_RC"
diff -rq "$TMP/roto-antes" "$TMP/roto/docs" >/dev/null; tap_check $? "un archivo sin los marcadores queda igual"

# 9. Idioma de la instalación: inglés por defecto, español con "language": "es" en .agent-kit.json.
grep -qF '<html lang="en">' "$pagina"; tap_check $? "sin idioma, la página va en inglés"
grep -qF '>Contents<' "$pagina"; tap_check $? "en inglés, el índice se llama Contents"
git init -q "$TMP/es"
printf '{"language": "es"}\n' >"$TMP/es/.agent-kit.json"
tap_run out 0 python3 -I "$ADD" -C "$TMP/es" add --topic "Tema" --entry "$TMP/e1.html"
grep -qF '<html lang="es">' "$TMP/es/docs/bitacora.html"; tap_check $? "con language es, la página va en español"
grep -qF '<html lang="es">' "$TMP/es/docs/bitacora/$MES.html"; tap_check $? "con language es, la página va en español" "la del mes"
grep -qF '>Índice<' "$TMP/es/docs/bitacora/$MES.html"; tap_check $? "en español, el índice se llama Índice"
grep -qF '>Meses<' "$TMP/es/docs/bitacora.html"; tap_check $? "en español, el índice de la portada se llama Meses"

# 10. Diseño: uno solo para todos los proyectos, el de barrilete (#361); un .barrilete/bitacora.css no entra.
grep -qF '<style id="theme-barrilete">' "$pagina"; tap_check $? "la página lleva el tema de barrilete"
git init -q "$TMP/tema"
mkdir -p "$TMP/tema/.barrilete"
printf ':root { --accent: #0E9F6E; }\n@media (prefers-color-scheme: dark) { :root { --bg: #121418; } }\n' >"$TMP/tema/.barrilete/bitacora.css"
tap_run out 0 python3 -I "$ADD" -C "$TMP/tema" add --topic "Tema" --entry "$TMP/e1.html"
grep -qF -- '#0E9F6E' "$TMP/tema/docs/bitacora.html" "$TMP/tema/docs/bitacora/$MES.html"; es=$?; [ "$es" = 1 ]; tap_check $? "el CSS de un proyecto no cambia el diseño de la página"
grep -qiF 'prefers-color-scheme' "$TMP/tema/docs/bitacora.html" "$TMP/tema/docs/bitacora/$MES.html"; es=$?; [ "$es" = 1 ]; tap_check $? "aunque el proyecto traiga modo oscuro, la página nueva es siempre clara"
grep -qF 'display=swap' "$pagina"; tap_check $? "las fuentes de Google se cargan sin dejar el texto invisible"
grep -qiF '<script' "$pagina" "$portada"; es=$?; [ "$es" = 1 ]; tap_check $? "la página no lleva scripts"
grep -qF '.tbl tr:first-child th:first-child{border-top-left-radius' "$pagina"; tap_check $? "las esquinas del encabezado de la tabla siguen el borde redondeado"
grep -qF '.tbl tr:first-child th:last-child{border-top-right-radius' "$pagina"; tap_check $? "las esquinas del encabezado de la tabla siguen el borde redondeado" "derecha"
for clase in kpis kpi cards card tbl note ok warn danger; do
  grep -qE "\.${clase}[^a-z-]" "$pagina"; tap_check $? "la página trae los estilos de los componentes de una entrada" ".$clase"
done

# 11. Contraste AA del texto y los colores de estado (la página es siempre clara); sin red, fuentes del sistema.
cat >"$TMP/contraste.py" <<'EOF'
"""Lee los tokens de barrilete.css (modo claro) y dice qué pares no llegan a WCAG AA (4.5:1)."""
import re, sys
css = open(sys.argv[1], encoding="utf-8").read()
TOKENS = ["--bg", "--surface", "--card", "--ink", "--muted", "--accent", "--ok", "--warn", "--danger"]
def bloque(texto):
    return dict(re.findall(r"(--[a-z-]+)\s*:\s*(#[0-9A-Fa-f]{6})", texto))
def lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)
# La página es siempre clara (#361): un solo juego de tokens.
t = bloque(css)
malos = [f"faltan {' '.join(k for k in TOKENS if k not in t)}"] if any(k not in t for k in TOKENS) else []
for texto in ["--ink", "--muted", "--accent", "--ok", "--warn", "--danger"] if not malos else []:
    for fondo in ["--bg", "--surface", "--card"]:
        r = ratio(t[texto], t[fondo])
        if r < 4.5:
            malos.append(f"{texto} sobre {fondo} {r:.2f}")
print("ok" if not malos else "; ".join(malos))
EOF
tap_run out 0 python3 -I "$TMP/contraste.py" "$CSS"
[ "$out" = ok ]; tap_check $? "el texto y los colores de estado de barrilete cumplen AA en modo claro" "$out"
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
cat >"$TMP/a-crlf.py" <<'EOF'
import sys
for p in sys.argv[1:]:
    t = open(p, newline="").read()
    open(p, "w", newline="").write(t.replace("\n", "\r\n"))
EOF
tap_run out 0 python3 -I "$TMP/a-crlf.py" "$TMP/crlf/docs/bitacora.html" "$TMP/crlf/docs/bitacora/$MES.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/crlf" find --topic "Tema"
[ "$out" = "exact tema" ]; tap_check $? "con CRLF, find encuentra la sección" "$out"
tap_run out 0 python3 -I "$ADD" -C "$TMP/crlf" add --topic "Tema" --entry "$TMP/e2.html"
tap_run forma_out 0 python3 -I "$TMP/forma.py" "$TMP/crlf/docs/bitacora/$MES.html"
[ "$(sed -n 1p <<<"$forma_out")" = "tema:2" ]; tap_check $? "con CRLF, la entrada se suma a la sección que ya estaba" "$forma_out"

# 16. Revisión: el archivo queda legible para todos (umask) y conserva su modo al sumar entradas.
modo() { tap_run modo_out 0 python3 -I -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"; }
git init -q "$TMP/modo"
umask 022
tap_run out 0 python3 -I "$ADD" -C "$TMP/modo" add --topic "Tema" --entry "$TMP/e1.html"
modo "$TMP/modo/docs/bitacora/$MES.html"
[ "$modo_out" = 0o644 ]; tap_check $? "un archivo nuevo sigue el umask" "$modo_out"
modo "$TMP/modo/docs/bitacora.html"
[ "$modo_out" = 0o644 ]; tap_check $? "un archivo nuevo sigue el umask" "portada: $modo_out"
chmod 664 "$TMP/modo/docs/bitacora.html" "$TMP/modo/docs/bitacora/$MES.html"
# Un tema nuevo, para que también se escriba la portada.
tap_run out 0 python3 -I "$ADD" -C "$TMP/modo" add --topic "Otro" --entry "$TMP/e2.html"
modo "$TMP/modo/docs/bitacora/$MES.html"
[ "$modo_out" = 0o664 ]; tap_check $? "sumar una entrada conserva el modo del archivo" "$modo_out"
modo "$TMP/modo/docs/bitacora.html"
[ "$modo_out" = 0o664 ]; tap_check $? "sumar una entrada conserva el modo del archivo" "portada: $modo_out"

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
tap_run out 0 python3 -I "$TMP/a-crlf.py" "$TMP/crlf2/docs/bitacora.html" "$TMP/crlf2/docs/bitacora/$MES.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/crlf2" add --topic "Otro" --entry "$TMP/e2.html"
for f in bitacora.html "bitacora/$MES.html"; do
  tap_run out 0 python3 -I -c 'import sys, re; t=open(sys.argv[1], newline="").read(); print(len(re.findall(r"(?<!\r)\n", t)))' "$TMP/crlf2/docs/$f"
  [ "$out" = 0 ]; tap_check $? "en un archivo CRLF, lo que se inserta también va con CRLF" "$f: saltos sin CR: $out"
done
for f in "$pagina" "$portada"; do
  tap_run out 0 python3 -I -c 'import sys; print(open(sys.argv[1], newline="").read().count("\r"))' "$f"
  [ "$out" = 0 ]; tap_check $? "en un archivo LF, lo que se inserta no trae CR" "${f#"$TMP/p/"}: CR: $out"
done

# 21. Tercera revisión de #344: una entrada que termina en una etiqueta a medias (el navegador se comería el cierre
# del <article> como atributos), una class que no es una lista de clases, un </br> (el navegador lo vuelve un <br>
# y no cierra nada), links a otro sitio sin esquema (//host, \\host) y una portada con un tema sin su marcador.
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
cp -R "$TMP/sinfin/docs" "$TMP/sinfin-antes"
tap_run out 65 python3 -I "$ADD" -C "$TMP/sinfin" add --topic "Otro" --entry "$TMP/e2.html"
[ "$TAP_RC" = 65 ]; tap_check $? "con una sección sin su marcador de fin, add no escribe y dice que el archivo está roto" "rc=$TAP_RC $out"
diff -rq "$TMP/sinfin-antes" "$TMP/sinfin/docs" >/dev/null; tap_check $? "con el archivo roto, add no lo toca"

# 22. #361: la página es siempre clara (también el índice y el pie), hay un diagrama con ramas y un mapa de partes
# que pasan la lista permitida, una página que ya existe no cambia su diseño y el skill pide la idea, no un informe.
grep -qiE 'prefers-color-scheme' "$CSS"; es=$?; [ "$es" = 1 ]; tap_check $? "el diseño de barrilete no tiene modo oscuro"
grep -qE 'color-scheme:[[:space:]]*light[[:space:]]*;' "$CSS"; tap_check $? "el diseño de barrilete le pide al navegador el modo claro"
git init -q "$TMP/claro"
tap_run out 0 python3 -I "$ADD" -C "$TMP/claro" add --topic "Tema" --entry "$TMP/e1.html"
grep -qiE 'prefers-color-scheme' "$TMP/claro/docs/bitacora.html" "$TMP/claro/docs/bitacora/$MES.html"; es=$?; [ "$es" = 1 ]; tap_check $? "una página nueva no cambia a oscuro con el sistema"
grep -qiE 'background:#(14161A|121418)' "$TMP/claro/docs/bitacora.html" "$TMP/claro/docs/bitacora/$MES.html"; es=$?; [ "$es" = 1 ]; tap_check $? "el índice y el pie de una página nueva no son negros"
for clase in branch root opts opt map node edge; do
  grep -qE "\.${clase}[^a-z-]" "$TMP/claro/docs/bitacora/$MES.html"; tap_check $? "la página trae los estilos del diagrama con ramas y del mapa" ".$clase"
done
cat >"$TMP/diagramas.html" <<'EOF'
<div class="branch"><div class="root">¿Dónde se guarda?</div><div class="opts"><div class="opt ok"><h4>Un archivo</h4><p>Elegida.</p></div><div class="opt danger"><h4>Uno por tema</h4><p>Descartada.</p></div></div></div>
<ul class="map"><li><span class="node">El chat</span><span class="edge">escribe en</span><span class="node">La bitácora</span></li></ul>
EOF
tap_run out 0 python3 -I "$ADD" -C "$TMP/claro" add --topic "Tema" --entry "$TMP/diagramas.html"
[ "$TAP_RC" = 0 ]; tap_check $? "add acepta el diagrama con ramas y el mapa de partes" "rc=$TAP_RC $out"
for malo in '<div class="branch" style="--v:1%">x</div>' '<div class="opt" onclick="x()">x</div>' \
            '<ul class="map"><li><svg></svg></li></ul>' '<span class="edge" id="tema">x</span>'; do
  printf '%s\n' "$malo" >"$TMP/malo.html"
  tap_run out 64 python3 -I "$ADD" -C "$TMP/claro" add --topic "Tema" --entry "$TMP/malo.html"
  [ "$TAP_RC" = 64 ]; tap_check $? "dentro de los diagramas se sigue rechazando lo que no está en la lista permitida" "$malo: rc=$TAP_RC"
done
# Una página que nació con otro diseño (con modo oscuro) lo conserva al sumar entradas.
git init -q "$TMP/vieja"
tap_run out 0 python3 -I "$ADD" -C "$TMP/vieja" add --topic "Tema" --entry "$TMP/e1.html"
for f in bitacora.html "bitacora/$MES.html"; do
  tap_run out 0 python3 -I -c 'import sys; p=sys.argv[1]; t=open(p).read(); open(p, "w").write(t.replace("<style id=\"theme-barrilete\">", "<style id=\"theme-barrilete\">\n@media (prefers-color-scheme: dark) { :root { --bg: #121418; } }", 1))' "$TMP/vieja/docs/$f"
done
# Un tema nuevo, para que se escriban las dos: la página del mes y la portada.
tap_run out 0 python3 -I "$ADD" -C "$TMP/vieja" add --topic "Otro" --entry "$TMP/e2.html"
for f in bitacora.html "bitacora/$MES.html"; do
  grep -qF '@media (prefers-color-scheme: dark) { :root { --bg: #121418; } }' "$TMP/vieja/docs/$f"; tap_check $? "una página que ya existe conserva el diseño con el que nació" "$f"
done
# En la plantilla cada archivo va en su idioma (X.md en inglés, X.es.md en español). En un proyecto instalado queda uno
# solo, en el idioma de la instalación ("language" de .agent-kit.json; sin él, inglés, como lo lee bitacora_add.py):
# con --lang es, SKILL.md y docs/agents/bitacora.md traen el texto en español y no quedan sus .es.md.
idioma_inst=en
case "$plantilla" in no) tap_run idioma_inst 0 python3 -I -c '
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        valor = json.load(f).get("language")
except (OSError, ValueError, AttributeError):
    valor = None
print("es" if valor == "es" else "en")' "$RAIZ/.agent-kit.json" ;; esac
for f in $archivos; do
  idioma=$idioma_inst
  case "$plantilla:$f" in sí:*.es.md) idioma=es ;; sí:*) idioma=en ;; esac
  case "$idioma" in es) camino="de dónde salió"; jerga="sin nombres de archivos" ;; *) camino="where it came from"; jerga="no file names" ;; esac
  for frase in "$camino" "$jerga" 'class="branch"' 'class="map"'; do
    tap_run out 0 python3 -I "$TMP/contiene.py" "$RAIZ/.claude/skills/bitacora/$f" "$frase"
    [ "$out" = sí ]; tap_check $? "el skill pide la idea con gráficos y en lenguaje de persona, no un informe" "$f: $frase: $out"
  done
done
docs_bitacora="docs/agents/bitacora.md"
case "$plantilla" in sí) docs_bitacora="docs/agents/bitacora.md docs/agents/bitacora.es.md" ;; esac
for f in $docs_bitacora; do
  idioma=$idioma_inst
  case "$plantilla:$f" in sí:*.es.md) idioma=es ;; sí:*) idioma=en ;; esac
  case "$idioma" in es) titulo="## Para qué sirve" ;; *) titulo="## What it is for" ;; esac
  tap_run out 0 python3 -I "$TMP/contiene.py" "$RAIZ/$f" "$titulo"
  [ "$out" = sí ]; tap_check $? "la documentación explica qué es la bitácora y para qué sirve" "$f: $out"
done

# 23. #365: la bitácora se parte por mes. docs/bitacora.html es la portada (el índice de meses y el de temas) y cada mes
# tiene su página en docs/bitacora/AAAA-MM.html, con una sección por tema. Las páginas de los meses pasados no cambian
# ni un byte, y en la portada y en el último mes solo se insertan líneas.
# Resume una página de mes: sus secciones en orden con cuántas entradas tiene cada una.
cat >"$TMP/mes.py" <<'EOF'
import os, re, sys
if not os.path.isfile(sys.argv[1]):
    print("no está")
    raise SystemExit
p = open(sys.argv[1], encoding="utf-8").read()
secs = re.findall(r'<section id="([^"]+)"(.*?)</section>', p, re.S)
ENTRADA = r'<article class="entrada"'
print(" ".join(f"{i}:{len(re.findall(ENTRADA, c))}" for i, c in secs) or "sin secciones")
EOF
# Resume la portada en tres líneas: los enlaces a las páginas (en su orden), los de cada tema (la sección con el id
# del tema, en su orden) y cuántas entradas lleva. "anterior" es docs/bitacora-anterior.html.
cat >"$TMP/portada.py" <<'EOF'
import os, re, sys
if not os.path.isfile(sys.argv[1]):
    print("no está")
    raise SystemExit
p = open(sys.argv[1], encoding="utf-8").read()
PAGINA = r"(bitacora/\d{4}-\d{2}\.html|bitacora-anterior\.html)"
def nombre(href):
    return "anterior" if href == "bitacora-anterior.html" else href[len("bitacora/"):-len(".html")]
print("meses: " + " ".join(nombre(h) for h in re.findall(r'href="%s"' % PAGINA, p)))
temas = []
for slug, cuerpo in re.findall(r'<section id="([^"]+)"(.*?)</section>', p, re.S):
    enlaces = re.findall(r'href="%s#([^"]*)"' % PAGINA, cuerpo)
    temas.append(f"{slug}=" + ",".join(nombre(h) + ("" if ancla == slug else f"#{ancla}") for h, ancla in enlaces))
print("temas: " + " ".join(temas))
print("entradas=%d" % len(re.findall(r'<article class="entrada"', p)))
EOF
# Compara dos copias de docs/, archivo por archivo: = igual byte a byte, + nuevo, - borrado, i solo se insertaron
# líneas (lo anterior quedó igual), x se reescribió algo.
cat >"$TMP/cambios.py" <<'EOF'
import difflib, os, sys
def arbol(raiz):
    out = {}
    for carpeta, _, archivos in os.walk(raiz):
        for n in archivos:
            ruta = os.path.join(carpeta, n)
            with open(ruta, "rb") as f:
                out[os.path.relpath(ruta, raiz)] = f.read()
    return out
a, b = arbol(sys.argv[1]), arbol(sys.argv[2])
def codigo(n):
    if n not in a:
        return "+"
    if n not in b:
        return "-"
    if a[n] == b[n]:
        return "="
    x, y = (t.decode("utf-8").splitlines(keepends=True) for t in (a[n], b[n]))
    ops = [op for op in difflib.SequenceMatcher(None, x, y, autojunk=False).get_opcodes() if op[0] != "equal"]
    return "i" if all(op[0] == "insert" for op in ops) else "x"
print(" ".join(f"{n}:{codigo(n)}" for n in sorted(set(a) | set(b))) or "vacío")
EOF
cat >"$TMP/igual.py" <<'EOF'
import os, sys
a, b = sys.argv[1:3]
if not (os.path.isfile(a) and os.path.isfile(b)):
    print("no está")
else:
    print("igual" if open(a, "rb").read() == open(b, "rb").read() else "distinto")
EOF
# Le saca un texto a un archivo (para romper una página a propósito).
cat >"$TMP/quita.py" <<'EOF'
import os, sys
ruta, texto = sys.argv[1:3]
if not os.path.isfile(ruta):
    print("no está")
else:
    t = open(ruta, encoding="utf-8").read()
    open(ruta, "w", encoding="utf-8").write(t.replace(texto, ""))
    print("quitado" if texto in t else "no lo tenía")
EOF

# Una bitácora nueva: la entrada va a la página del mes en curso y la portada enlaza ese mes y ese tema.
git init -q "$TMP/n"
tap_run out 0 python3 -I "$ADD" -C "$TMP/n" add --topic "Decidir la ruta" --entry "$TMP/e1.html"
[ "$out" = "ok: new decidir-la-ruta $TMP/n/docs/bitacora/$MES.html" ]; tap_check $? "add dice la página del mes donde dejó la entrada" "$out"
tap_run mes 0 python3 -I "$TMP/mes.py" "$TMP/n/docs/bitacora/$MES.html"
[ "$mes" = "decidir-la-ruta:1" ]; tap_check $? "en una bitácora nueva, la entrada queda en la página del mes en curso" "$mes"
tap_run por 0 python3 -I "$TMP/portada.py" "$TMP/n/docs/bitacora.html"
[ "$(sed -n 1p <<<"$por")" = "meses: $MES" ]; tap_check $? "en una bitácora nueva, la portada enlaza la página del mes" "$por"
[ "$(sed -n 2p <<<"$por")" = "temas: decidir-la-ruta=$MES" ]; tap_check $? "en una bitácora nueva, la portada enlaza el tema con su mes" "$por"
[ "$(sed -n 3p <<<"$por")" = "entradas=0" ]; tap_check $? "la portada no lleva entradas, solo enlaces" "$por"
tap_run out 0 python3 -I "$TMP/contiene.py" "$TMP/n/docs/bitacora/$MES.html" 'href="../bitacora.html"'
[ "$out" = sí ]; tap_check $? "la página de un mes enlaza de vuelta a la portada" "$out"

# Varios meses: enero con dos temas, después febrero, después el mes en curso.
git init -q "$TMP/m"
tap_run out 0 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema uno" --date 2026-01-10 --entry "$TMP/e1.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema dos" --date 2026-01-15 --entry "$TMP/e2.html"
cp -R "$TMP/m/docs" "$TMP/s1"
tap_run out 0 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema uno" --date 2026-02-03 --entry "$TMP/e3.html"
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s1" "$TMP/m/docs"
[ "$cam" = "bitacora.html:i bitacora/2026-01.html:= bitacora/2026-02.html:+" ]; tap_check $? "la primera entrada de un mes nuevo crea su página sin tocar la del mes anterior" "$cam"
tap_run mes 0 python3 -I "$TMP/mes.py" "$TMP/m/docs/bitacora/2026-01.html"
[ "$mes" = "tema-uno:1 tema-dos:1" ]; tap_check $? "la página de un mes tiene una sección por tema con las entradas de ese mes" "enero: $mes"
tap_run mes 0 python3 -I "$TMP/mes.py" "$TMP/m/docs/bitacora/2026-02.html"
[ "$mes" = "tema-uno:1" ]; tap_check $? "la página de un mes tiene una sección por tema con las entradas de ese mes" "febrero: $mes"
tap_run por 0 python3 -I "$TMP/portada.py" "$TMP/m/docs/bitacora.html"
[ "$(sed -n 1p <<<"$por")" = "meses: 2026-02 2026-01" ]; tap_check $? "la portada lista los meses, el más nuevo primero" "$por"
[ "$(sed -n 2p <<<"$por")" = "temas: tema-uno=2026-01,2026-02 tema-dos=2026-01" ]; tap_check $? "en la portada, cada tema enlaza a todos los meses donde tiene entradas" "dos meses: $por"

# El mes en curso: un tema que viene de enero, otra entrada del mismo tema y un tema nuevo.
cp -R "$TMP/m/docs" "$TMP/s2"
tap_run out 0 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema dos" --entry "$TMP/e1.html"
[ "$out" = "ok: append tema-dos $TMP/m/docs/bitacora/$MES.html" ]; tap_check $? "un tema que ya existe en otro mes no es nuevo: add dice append y la página de este mes" "$out"
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s2" "$TMP/m/docs"
[ "$cam" = "bitacora.html:i bitacora/2026-01.html:= bitacora/2026-02.html:= bitacora/$MES.html:+" ]; tap_check $? "sumar una entrada no cambia ningún byte de las páginas de los meses pasados" "$cam"
cp -R "$TMP/m/docs" "$TMP/s3"
tap_run out 0 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema dos" --entry "$TMP/e2.html"
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s3" "$TMP/m/docs"
[ "$cam" = "bitacora.html:= bitacora/2026-01.html:= bitacora/2026-02.html:= bitacora/$MES.html:i" ]; tap_check $? "otra entrada del mismo tema en el mismo mes solo inserta líneas en la página del mes" "$cam"
cp -R "$TMP/m/docs" "$TMP/s4"
tap_run out 0 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema tres" --entry "$TMP/e3.html"
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s4" "$TMP/m/docs"
[ "$cam" = "bitacora.html:i bitacora/2026-01.html:= bitacora/2026-02.html:= bitacora/$MES.html:i" ]; tap_check $? "un tema nuevo solo inserta líneas en la portada y en la página del mes" "$cam"

# find y add miran toda la bitácora: «Tema uno» solo tiene entradas en enero y febrero.
tap_run out 0 python3 -I "$ADD" -C "$TMP/m" find --topic "Tema UNO"
[ "$out" = "exact tema-uno" ]; tap_check $? "find encuentra un tema aunque sus entradas estén en otro mes" "$out"
tap_run out 3 python3 -I "$ADD" -C "$TMP/m" find --topic "Tema unos"
[ "$TAP_RC" = 3 ]; tap_check $? "find avisa de un tema con nombre parecido aunque sus entradas estén en otro mes" "rc=$TAP_RC"
grep -qxF "similar tema-uno	Tema uno" <<<"$out"; tap_check $? "find avisa de un tema con nombre parecido aunque sus entradas estén en otro mes" "$out"
SIN_CAMBIOS="bitacora.html:= bitacora/2026-01.html:= bitacora/2026-02.html:= bitacora/$MES.html:="
cp -R "$TMP/m/docs" "$TMP/s5"
tap_run out 3 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema unos" --entry "$TMP/e1.html"
rc=$TAP_RC
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s5" "$TMP/m/docs"
[ "$rc $cam" = "3 $SIN_CAMBIOS" ]; tap_check $? "add con un nombre parecido a un tema de otro mes no escribe nada y sale con 3" "rc=$rc $cam"
tap_run out 64 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema uno" --new --entry "$TMP/e1.html"
rc=$TAP_RC
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s5" "$TMP/m/docs"
[ "$rc $cam" = "64 $SIN_CAMBIOS" ]; tap_check $? "add --new con un tema que ya existe en otro mes es un error de uso y no escribe nada" "rc=$rc $cam"
tap_run out 0 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema unos" --into tema-uno --entry "$TMP/e1.html"
tap_run mes 0 python3 -I "$TMP/mes.py" "$TMP/m/docs/bitacora/$MES.html"
[ "$mes" = "tema-dos:2 tema-tres:1 tema-uno:1" ]; tap_check $? "add --into un tema de otro mes le abre su sección en la página de este mes" "$mes"
tap_run out 0 python3 -I "$TMP/contiene.py" "$TMP/m/docs/bitacora/$MES.html" '<section id="tema-uno" data-topic="Tema uno">'
[ "$out" = sí ]; tap_check $? "la sección de un tema que viene de otro mes lleva el nombre que el tema ya tenía" "$out"
tap_run por 0 python3 -I "$TMP/portada.py" "$TMP/m/docs/bitacora.html"
[ "$(sed -n 1p <<<"$por")" = "meses: $MES 2026-02 2026-01" ]; tap_check $? "la portada lista los meses, el más nuevo primero" "tres meses: $por"
TEMAS="temas: tema-uno=2026-01,2026-02,$MES tema-dos=2026-01,$MES tema-tres=$MES"
[ "$(sed -n 2p <<<"$por")" = "$TEMAS" ]; tap_check $? "en la portada, cada tema enlaza a todos los meses donde tiene entradas" "tres meses: $por"

# Lo que se rechaza no toca nada: una entrada fuera de la lista permitida, una fecha de un mes que ya tiene uno
# posterior (ese mes está cerrado) y una fecha futura (cerraría todos los meses hasta que llegue).
cp -R "$TMP/m/docs" "$TMP/s6"
printf '<script>x()</script>\n' >"$TMP/malo.html"
tap_run out 64 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema dos" --entry "$TMP/malo.html"
rc=$TAP_RC
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s6" "$TMP/m/docs"
[ "$rc $cam" = "64 $SIN_CAMBIOS" ]; tap_check $? "una entrada rechazada no toca ni la página del mes ni la portada" "rc=$rc $cam"
tap_run out 64 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema uno" --date 2026-01-20 --entry "$TMP/e1.html"
rc=$TAP_RC
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s6" "$TMP/m/docs"
[ "$rc $cam" = "64 $SIN_CAMBIOS" ]; tap_check $? "add --date en un mes que ya tiene uno posterior se rechaza y no toca nada" "rc=$rc $cam"
tap_run out 64 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema uno" --date 2999-01-01 --entry "$TMP/e1.html"
rc=$TAP_RC
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s6" "$TMP/m/docs"
[ "$rc $cam" = "64 $SIN_CAMBIOS" ]; tap_check $? "add --date con una fecha futura se rechaza y no toca nada" "rc=$rc $cam"

# Sin la portada (se borró, o un add se cortó a la mitad), se arma de nuevo con lo que hay en las páginas.
rm -f "$TMP/m/docs/bitacora.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/m" find --topic "Tema uno"
[ "$out" = "exact tema-uno" ]; tap_check $? "sin la portada, find encuentra los temas en las páginas de los meses" "$out"
tap_run out 0 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema tres" --entry "$TMP/e2.html"
tap_run por 0 python3 -I "$TMP/portada.py" "$TMP/m/docs/bitacora.html"
[ "$(sed -n 1p <<<"$por")" = "meses: $MES 2026-02 2026-01" ]; tap_check $? "sin la portada, add la arma de nuevo con todos los meses" "$por"
[ "$(sed -n 2p <<<"$por")" = "$TEMAS" ]; tap_check $? "sin la portada, add la arma de nuevo con cada tema y sus meses" "$por"

# Una página de mes que perdió un marcador (se editó a mano) no se toca, y la portada tampoco.
git init -q "$TMP/rota"
tap_run out 0 python3 -I "$ADD" -C "$TMP/rota" add --topic "Tema" --entry "$TMP/e1.html"
tap_run out 0 python3 -I "$TMP/quita.py" "$TMP/rota/docs/bitacora/$MES.html" "<!-- bitacora:end tema -->"
cp -R "$TMP/rota/docs" "$TMP/s7"
tap_run out 65 python3 -I "$ADD" -C "$TMP/rota" add --topic "Otro" --entry "$TMP/e2.html"
rc=$TAP_RC
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s7" "$TMP/rota/docs"
[ "$rc $cam" = "65 bitacora.html:= bitacora/$MES.html:=" ]; tap_check $? "con la página del mes rota, add no toca ni esa página ni la portada y sale con 65" "rc=$rc $cam"
case "$out" in *"docs/bitacora/$MES.html"*) es=sí ;; *) es=no ;; esac
[ "$es" = sí ]; tap_check $? "el aviso de una página rota dice cuál es" "$out"

# Un add --new que se cortó después de escribir la portada (y antes de la página del mes) se termina repitiéndolo igual.
git init -q "$TMP/corte"
tap_run out 0 python3 -I "$ADD" -C "$TMP/corte" add --topic "Tema" --entry "$TMP/e1.html"
cp "$TMP/corte/docs/bitacora/$MES.html" "$TMP/corte-mes.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/corte" add --topic "Rutas nuevas" --new --entry "$TMP/e2.html"
cp "$TMP/corte-mes.html" "$TMP/corte/docs/bitacora/$MES.html"
tap_run out 0 python3 -I "$ADD" -C "$TMP/corte" add --topic "Rutas nuevas" --new --entry "$TMP/e2.html"
[ "$out" = "ok: new rutas-nuevas $TMP/corte/docs/bitacora/$MES.html" ]; tap_check $? "un add --new cortado después de la portada se termina repitiéndolo" "rc=$TAP_RC $out"
tap_run mes 0 python3 -I "$TMP/mes.py" "$TMP/corte/docs/bitacora/$MES.html"
[ "$mes" = "tema:1 rutas-nuevas:1" ]; tap_check $? "el reintento deja la entrada una sola vez en la página del mes" "$mes"
tap_run por 0 python3 -I "$TMP/portada.py" "$TMP/corte/docs/bitacora.html"
[ "$(sed -n 2p <<<"$por")" = "temas: tema=$MES rutas-nuevas=$MES" ]; tap_check $? "el reintento no repite el tema en la portada" "$por"
tap_run out 64 python3 -I "$ADD" -C "$TMP/corte" add --topic "Rutas nuevas" --new --entry "$TMP/e2.html"
[ "$TAP_RC" = 64 ]; tap_check $? "un add --new que ya se terminó no se repite" "rc=$TAP_RC $out"
# Pero --new con un tema que ya tiene entradas en otro mes se sigue rechazando.
tap_run out 64 python3 -I "$ADD" -C "$TMP/m" add --topic "Tema dos" --new --entry "$TMP/e2.html"
[ "$TAP_RC" = 64 ]; tap_check $? "add --new con un tema que ya tiene entradas se rechaza" "rc=$TAP_RC $out"

# Una portada que perdió el marcador de meses no se toma por una bitácora de antes: el aviso nombra ese marcador.
git init -q "$TMP/sinmeses"
tap_run out 0 python3 -I "$ADD" -C "$TMP/sinmeses" add --topic "Tema" --entry "$TMP/e1.html"
tap_run out 0 python3 -I "$TMP/quita.py" "$TMP/sinmeses/docs/bitacora.html" "<!-- bitacora:months -->"
cp -R "$TMP/sinmeses/docs" "$TMP/s10"
tap_run out 65 python3 -I "$ADD" -C "$TMP/sinmeses" add --topic "Tema" --entry "$TMP/e2.html"
rc=$TAP_RC
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s10" "$TMP/sinmeses/docs"
[ "$rc $cam" = "65 bitacora.html:= bitacora/$MES.html:=" ]; tap_check $? "con la portada sin su marcador de meses, add no toca nada y sale con 65" "rc=$rc $cam"
case "$out" in *"bitacora:months"*) es=sí ;; *) es=no ;; esac
[ "$es" = sí ]; tap_check $? "el aviso de una portada sin su marcador de meses nombra ese marcador" "$out"

# 24. #365: una bitácora de antes (un solo archivo en docs/bitacora.html). Lo ya escrito queda byte a byte igual, en
# docs/bitacora-anterior.html; la portada lo enlaza y las entradas nuevas van a la página de su mes.
git init -q "$TMP/v"
mkdir -p "$TMP/v/docs"
cat >"$TMP/v/docs/bitacora.html" <<'EOF'
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Bitácora del proyecto · v</title>
<style id="theme-barrilete">
:root{--bg:#F6F7F9}
</style>
<style id="structure">body{margin:0}</style>
</head>
<body>
<nav class="toc" aria-label="Índice">
<h2 class="sr">Índice</h2>
<ol>
<li><a href="#ruta-vieja">01 Ruta vieja</a></li>
<li><a href="#otro-viejo">02 Otro viejo</a></li>
<!-- bitacora:nav -->
</ol>
</nav>
<main class="wrap">
<section id="ruta-vieja" data-topic="Ruta vieja">
<div class="sec-head"><span class="num">&gt;_ 01</span><h2><a href="#ruta-vieja">Ruta vieja</a></h2></div>
<article class="entrada">
<p class="fecha"><time datetime="2026-10-02">2026-10-02</time></p>
<p>Escrita antes de partir la bitácora por mes.</p>
</article>
<article class="entrada">
<p class="fecha"><time datetime="2026-11-05">2026-11-05</time></p>
<p>Otra, del mes siguiente, con un <a href="#otro-viejo">link a otro tema</a>.</p>
</article>
<!-- bitacora:end ruta-vieja -->
</section>
<section id="otro-viejo" data-topic="Otro viejo">
<div class="sec-head"><span class="num">&gt;_ 02</span><h2><a href="#otro-viejo">Otro viejo</a></h2></div>
<article class="entrada">
<p class="fecha"><time datetime="2026-11-06">2026-11-06</time></p>
<p>Una sola.</p>
</article>
<!-- bitacora:end otro-viejo -->
</section>
<!-- bitacora:main -->
</main>
</body>
</html>
EOF
cp "$TMP/v/docs/bitacora.html" "$TMP/v-antes.html"
tap_run out 3 python3 -I "$ADD" -C "$TMP/v" find --topic "Ruta"
grep -qxF "similar ruta-vieja	Ruta vieja" <<<"$out"; tap_check $? "en una bitácora de antes, find ve los temas ya escritos" "$out"
tap_run ig 0 python3 -I "$TMP/igual.py" "$TMP/v-antes.html" "$TMP/v/docs/bitacora.html"
[ "$ig" = igual ]; tap_check $? "en una bitácora de antes, find no mueve ni cambia nada" "$ig"
tap_run out 0 python3 -I "$ADD" -C "$TMP/v" add --topic "Ruta vieja" --entry "$TMP/e1.html"
[ "$out" = "ok: append ruta-vieja $TMP/v/docs/bitacora/$MES.html" ]; tap_check $? "en una bitácora de antes, la entrada de un tema ya escrito es un append en la página de su mes" "$out"
tap_run ig 0 python3 -I "$TMP/igual.py" "$TMP/v-antes.html" "$TMP/v/docs/bitacora-anterior.html"
[ "$ig" = igual ]; tap_check $? "lo ya escrito de una bitácora de antes queda byte a byte igual en docs/bitacora-anterior.html" "$ig"
tap_run mes 0 python3 -I "$TMP/mes.py" "$TMP/v/docs/bitacora/$MES.html"
[ "$mes" = "ruta-vieja:1" ]; tap_check $? "en una bitácora de antes, las entradas nuevas van a la página de su mes" "$mes"
tap_run por 0 python3 -I "$TMP/portada.py" "$TMP/v/docs/bitacora.html"
[ "$(sed -n 1p <<<"$por")" = "meses: $MES anterior" ]; tap_check $? "la portada de una bitácora de antes enlaza lo ya escrito, después de los meses" "$por"
[ "$(sed -n 2p <<<"$por")" = "temas: ruta-vieja=anterior,$MES otro-viejo=anterior" ]; tap_check $? "un enlace viejo a un tema cae en su lugar de la portada, que lleva a lo ya escrito y a sus meses" "$por"
[ "$(sed -n 3p <<<"$por")" = "entradas=0" ]; tap_check $? "la portada de una bitácora de antes no lleva entradas" "$por"
cp -R "$TMP/v/docs" "$TMP/s8"
tap_run out 0 python3 -I "$ADD" -C "$TMP/v" add --topic "Tema nuevo" --entry "$TMP/e2.html"
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s8" "$TMP/v/docs"
[ "$cam" = "bitacora-anterior.html:= bitacora.html:i bitacora/$MES.html:i" ]; tap_check $? "las entradas que siguen no vuelven a tocar lo ya escrito" "$cam"
tap_run out 64 python3 -I "$ADD" -C "$TMP/v" add --topic "Otro viejo" --new --entry "$TMP/e2.html"
[ "$TAP_RC" = 64 ]; tap_check $? "add --new con un tema que solo tiene entradas en otra página se rechaza" "rc=$TAP_RC $out"
# Si docs/bitacora-anterior.html ya existe, no se pisa: no se sabe cuál de los dos es lo ya escrito.
git init -q "$TMP/v2"
mkdir -p "$TMP/v2/docs"
cp "$TMP/v-antes.html" "$TMP/v2/docs/bitacora.html"
printf 'otra cosa\n' >"$TMP/v2/docs/bitacora-anterior.html"
cp -R "$TMP/v2/docs" "$TMP/s9"
tap_run out 65 python3 -I "$ADD" -C "$TMP/v2" add --topic "Ruta vieja" --entry "$TMP/e1.html"
rc=$TAP_RC
tap_run cam 0 python3 -I "$TMP/cambios.py" "$TMP/s9" "$TMP/v2/docs"
[ "$rc $cam" = "65 bitacora-anterior.html:= bitacora.html:=" ]; tap_check $? "si docs/bitacora-anterior.html ya existe, add no pisa nada y sale con 65" "rc=$rc $cam"

# 25. #365: el skill y la documentación cuentan la forma nueva (en la plantilla, en inglés y en español).
for f in $archivos; do
  for frase in 'docs/bitacora/' 'docs/bitacora-anterior.html'; do
    tap_run out 0 python3 -I "$TMP/contiene.py" "$RAIZ/.claude/skills/bitacora/$f" "$frase"
    [ "$out" = sí ]; tap_check $? "el skill cuenta la portada, las páginas por mes y dónde queda lo ya escrito" "$f: $frase: $out"
  done
done
for f in $docs_bitacora; do
  for frase in 'docs/bitacora/' 'docs/bitacora-anterior.html'; do
    tap_run out 0 python3 -I "$TMP/contiene.py" "$RAIZ/$f" "$frase"
    [ "$out" = sí ]; tap_check $? "la documentación cuenta la portada, las páginas por mes y dónde queda lo ya escrito" "$f: $frase: $out"
  done
done

tap_done
