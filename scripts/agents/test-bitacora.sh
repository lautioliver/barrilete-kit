#!/usr/bin/env bash
# shellcheck disable=SC2319,SC2154,SC2164  # "<condición>; tap_check $?" es el patrón de los tests (tap.sh); tap_run asigna out y orden; un pushd que falla corta la corrida (tap.sh)
# Tests de scripts/agents/bitacora.py (#339): arma .barrilete/bitacora.html con las retros que escribe retro.sh
# en agents/retros y los PRs de gh, con el diseño de barrilete o el del proyecto.
# No usa GitHub: las retros van a un remoto local y gh es un falso en PATH.
# Uso: bash scripts/agents/test-bitacora.sh
set -uo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
. "$RAIZ/scripts/agents/tap.sh"
tap_begin "$0"
BITACORA="$RAIZ/scripts/agents/bitacora.py"
RETRO="$RAIZ/.claude/skills/improve-skills/retro.sh"
CSS="$RAIZ/scripts/agents/bitacora/barrilete.css"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.test
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-bitacora-XXXXXX")
TMP=$(cd "$TMP" && pwd)   # sin la doble barra de un TMPDIR que termina en /
# shellcheck disable=SC2016  # se expande al salir, no ahora
tap_at_exit 'rm -rf "$TMP"'

# gh falso: anota cómo lo llamaron en $GH_LOG y responde como `gh api graphql` con el PR 42; como el real, si le
# piden un número que no es un PR, da los datos que tiene y sale con 1. El que falla simula gh sin sesión o sin red.
mkdir -p "$TMP/bin" "$TMP/bin-roto"
export GH_LOG="$TMP/gh.log"
cat >"$TMP/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$GH_LOG"
echo '{"data":{"repository":{"p42":{"number":42,"title":"Agregar la bitácora de prueba","state":"MERGED","url":"https://example.test/pull/42"},"p77":null}},"errors":[{"type":"NOT_FOUND"}]}'
exit 1
EOF
printf '#!/bin/sh\necho "gh: sin sesión" >&2\nexit 1\n' >"$TMP/bin-roto/gh"
chmod +x "$TMP/bin/gh" "$TMP/bin-roto/gh"
export PATH="$TMP/bin:$PATH"

# Un proyecto con remoto local y una retro escrita con retro.sh (el contrato que lee la bitácora).
git init -q --bare -b main "$TMP/remoto.git"
git clone -q "$TMP/remoto.git" "$TMP/p" 2>/dev/null
git -C "$TMP/p" commit -q --allow-empty -m base
git -C "$TMP/p" push -q origin HEAD:main 2>/dev/null
cat >"$TMP/r.md" <<'EOF'
---
skill: implement-issue
issue: 7
pr: 42
area: area:infra
paths: scripts/agents/bitacora.py
model: sonnet
role: implementer
---
**Deviations:** Desvío de prueba <script>alert(1)</script>
**Decisions not covered:** none
**What the review found:** nothing
EOF
pushd "$TMP/p" >/dev/null
"$RETRO" "$TMP/r.md" >/dev/null 2>&1
popd >/dev/null

pagina="$TMP/p/.barrilete/bitacora.html"

# 1. La retro de retro.sh aparece con su rol, su modelo y su PR, y el título del PR sale de gh.
tap_run out 0 python3 -I "$BITACORA" -C "$TMP/p"
grep -qF 'data-role="implementer"' "$pagina"; tap_check $? "la retro de retro.sh aparece con su rol"
grep -qF 'data-model="sonnet"' "$pagina"; tap_check $? "la retro de retro.sh aparece con su modelo"
grep -qF 'data-pr="42"' "$pagina"; tap_check $? "la retro de retro.sh aparece agrupada en su PR"
grep -qF 'Agregar la bitácora de prueba' "$pagina"; tap_check $? "el título del PR sale de gh"
grep -qF 'Desvío de prueba' "$pagina"; tap_check $? "las secciones de la retro aparecen en la tarjeta"
grep -qF '<script>alert(1)</script>' "$pagina"; es=$?; [ "$es" = 1 ]; tap_check $? "el texto de una retro no se interpreta como HTML"
[ "$out" = "ok: $pagina" ]; tap_check $? "dice en una línea dónde dejó la página" "$out"

# 2. Correrlo dos veces da la misma página.
cp "$pagina" "$TMP/primera.html"
tap_run out 0 python3 -I "$BITACORA" -C "$TMP/p"
cmp -s "$TMP/primera.html" "$pagina"; tap_check $? "correrlo dos veces da la misma página"

# 3. Sin gh (sin sesión o sin red): la página sale igual, con el PR pero sin su título.
tap_run out 0 env PATH="$TMP/bin-roto:$PATH" python3 -I "$BITACORA" -C "$TMP/p"
grep -qF 'data-pr="42"' "$pagina"; tap_check $? "si gh falla, la página sale igual con el PR"
grep -qF 'Agregar la bitácora de prueba' "$pagina"; es=$?; [ "$es" = 1 ]; tap_check $? "si gh falla, el PR sale sin su título"

# 4. Idioma: inglés por defecto; con "language": "es" en .agent-kit.json, las etiquetas en español.
grep -qF '>implementer · sonnet<' "$pagina"; tap_check $? "en inglés, el agente se etiqueta como implementer"
printf '{"language": "es"}\n' >"$TMP/p/.agent-kit.json"
tap_run out 0 python3 -I "$BITACORA" -C "$TMP/p"
grep -qF '>implementador · sonnet<' "$pagina"; tap_check $? "en español, el agente se etiqueta como implementador"
grep -qF '>Desvíos<' "$pagina"; tap_check $? "en español, las secciones de una retro en inglés se traducen"
grep -qF 'lang="es"' "$pagina"; tap_check $? "en español, la página se declara en español"
rm -f "$TMP/p/.agent-kit.json"

# 5. Tema: barrilete por defecto; .barrilete/bitacora.css pisa lo que define y va después; --theme elige o lo ignora.
printf ':root { --accent: #0E9F6E; }\n/* </style><script>x()</script> */\n' >"$TMP/p/.barrilete/bitacora.css"
tap_run out 0 python3 -I "$BITACORA" -C "$TMP/p"
grep -qF -- '--accent: #0E9F6E' "$pagina"; tap_check $? "el CSS del proyecto entra en la página"
tap_run orden 0 awk '/<style id="theme-barrilete">/ && !b {b=NR} /<style id="theme-project">/ && !p {p=NR} END {print (b && p && p > b) ? "después" : "no"}' "$pagina"
[ "$orden" = "después" ]; tap_check $? "el CSS del proyecto va después del de barrilete"
grep -qF -- '--danger:' "$pagina"; tap_check $? "lo que el proyecto no define queda como barrilete"
grep -qF '</style><script>x()</script>' "$pagina"; es=$?; [ "$es" = 1 ]; tap_check $? "el CSS del proyecto no puede cerrar su bloque de estilo"
tap_run out 0 python3 -I "$BITACORA" -C "$TMP/p" --theme barrilete
grep -qF -- '--accent: #0E9F6E' "$pagina"; es=$?; [ "$es" = 1 ]; tap_check $? "con --theme barrilete se ignora el CSS del proyecto"
printf ':root { --accent: #AA00AA; }\n' >"$TMP/otro.css"
tap_run out 0 python3 -I "$BITACORA" -C "$TMP/p" --theme "$TMP/otro.css"
grep -qF -- '--accent: #AA00AA' "$pagina"; tap_check $? "--theme con una ruta usa ese archivo"
tap_run out 64 python3 -I "$BITACORA" -C "$TMP/p" --theme "$TMP/no-existe.css"
[ "$TAP_RC" = 64 ]; tap_check $? "--theme con un archivo que no existe es un error de uso"
rm -f "$TMP/p/.barrilete/bitacora.css"

# 6. Diseño de barrilete: los tokens del contrato, contraste AA en los dos modos y fuentes del sistema sin red.
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
tap_run out 0 python3 -I "$BITACORA" -C "$TMP/p"
grep -qF 'display=swap' "$pagina"; tap_check $? "las fuentes de Google se cargan sin dejar el texto invisible"

# 7. Sin retros: la página lo dice, en una línea y sin traceback.
: >"$GH_LOG"
git init -q "$TMP/vacio"
git -C "$TMP/vacio" commit -q --allow-empty -m base
tap_run out 0 python3 -I "$BITACORA" -C "$TMP/vacio"
grep -qF 'data-empty' "$TMP/vacio/.barrilete/bitacora.html"; tap_check $? "sin retros, la página dice que no hay"
[ ! -s "$GH_LOG" ]; tap_check $? "sin retros con PR, no llama a gh"
case "$out" in *Traceback*) tap_fail "sin retros, no hay traceback" "$out" ;; *) tap_ok "sin retros, no hay traceback" ;; esac

# 8. El kit la instala ignorada por git, y el modo --small (sin retros) no la lleva.
grep -qxF '.barrilete/bitacora.html' "$RAIZ/.gitignore"; tap_check $? "la página va ignorada en el .gitignore del kit"
if [ -f "$RAIZ/profiles/small/DELETE" ]; then
  for r in scripts/agents/bitacora.py scripts/agents/bitacora scripts/agents/test-bitacora.sh; do
    grep -qxF "$r" "$RAIZ/profiles/small/DELETE"; tap_check $? "el modo --small no lleva <r>" "el modo --small no lleva $r"
  done
else
  for r in scripts/agents/bitacora.py scripts/agents/bitacora scripts/agents/test-bitacora.sh; do
    tap_skip "el modo --small no lleva $r" "solo en la plantilla: un proyecto instalado no tiene profiles/"
  done
fi

# 9. Retros 0.9 (rama agentes/retros, claves y valores en español) y valores entre comillas: se leen con la tabla
#    de legacy-names.sh, como las lee /improve-skills, y la primera clave repetida gana.
retro_vieja() {   # retro_vieja <rama> <archivo> <contenido>: la escribe en el remoto sin tocar el clon
  local blob arbol padre commit
  blob=$(printf '%s' "$3" | git --git-dir="$TMP/remoto.git" hash-object -w --stdin)
  padre=$(git --git-dir="$TMP/remoto.git" rev-parse -q --verify "refs/heads/$1" || true)
  arbol=$(GIT_INDEX_FILE="$TMP/idx" sh -c 'rm -f "$GIT_INDEX_FILE"; git --git-dir="$1" read-tree --empty
    [ -z "$2" ] || git --git-dir="$1" read-tree "$2"; git --git-dir="$1" update-index --add --cacheinfo "100644,$3,$4"
    git --git-dir="$1" write-tree' _ "$TMP/remoto.git" "$padre" "$blob" "$2")
  commit=$(git --git-dir="$TMP/remoto.git" commit-tree "$arbol" ${padre:+-p "$padre"} -m retro)
  git --git-dir="$TMP/remoto.git" update-ref "refs/heads/$1" "$commit"
}
retro_vieja agentes/retros retros/2025-09-01-review-pr-77.md '---
skill: review-pr
pr: 77
rol: revisor
modelo: opus
fecha: 2025-09-01
---
**Desvíos:** retro vieja de la 0.9
'
retro_vieja agents/retros retros/2026-01-02-implement-issue-88.md $'---\r\nskill: implement-issue\r\npr: "88"\r\nrole: \'reviewer\'\r\nrole: implementer\r\nmodel: "haiku"\r\ndate: 2026-01-02\r\n---\r\n**Deviations:** con comillas y CRLF\r\n'
tarjeta_de() {   # tarjeta_de <pr>: solo el <article> de ese PR (la página va en una línea)
  python3 -I -c 'import re,sys; print("\n".join(a for a in re.findall(r"<article.*?</article>", open(sys.argv[1], encoding="utf-8").read()) if f"data-pr=\"{sys.argv[2]}\"" in a))' "$pagina" "$1"
}
tap_run out 0 python3 -I "$BITACORA" -C "$TMP/p"
grep -qF 'retro vieja de la 0.9' "$pagina"; tap_check $? "las retros de la rama 0.9 agentes/retros aparecen"
tarjeta_de 77 | grep -qF 'data-role="reviewer" data-model="opus"' ; tap_check $? "en una retro 0.9, rol: y modelo: se leen como role: y model: con sus valores nuevos"
tarjeta_de 77 | grep -qF '· 2025-09-01<'; tap_check $? "en una retro 0.9, fecha: se lee como date:"
tarjeta_de 88 | grep -qF 'data-role="reviewer" data-model="haiku"' ; tap_check $? "los valores entre comillas se leen sin ellas y la primera clave repetida gana"

# 10. Una retro sin PR ni issue es su propia tarjeta, sin un "issue" inventado con su ruta.
retro_vieja agents/retros retros/2026-02-01-orchestrate-3.md '---
skill: orchestrate
run: 3
role: orchestrator
model: opus
date: 2026-02-01
---
**Deviations:** corrida sin PR ni issue
'
# 11. El issue se ve en la tarjeta del PR, y una retro con solo el issue va a la tarjeta del PR de ese issue.
retro_vieja agents/retros retros/2026-02-02-implement-issue-7.md '---
skill: implement-issue
issue: 7
role: implementer
model: sonnet
date: 2026-02-02
---
**Deviations:** retro del issue sin PR todavía
'
# 12. Una retro con bytes que no son UTF-8 no rompe la página.
retro_vieja agents/retros retros/2026-02-03-review-pr-55.md $'---\nskill: review-pr\npr: 55\nrole: reviewer\nmodel: opus\ndate: 2026-02-03\n---\n**Deviations:** Desv\xedo en latin-1\n'
# 13. El texto antes del primer **Título:** no se pierde.
retro_vieja agents/retros retros/2026-02-04-review-pr-66.md '---
skill: review-pr
pr: 66
role: reviewer
model: opus
date: 2026-02-04
---
Resumen antes de las secciones.
**Deviations:** ninguno
'
: >"$GH_LOG"
tap_run out 0 python3 -I "$BITACORA" -C "$TMP/p"
grep -qF 'corrida sin PR ni issue' "$pagina"; tap_check $? "una retro sin PR ni issue aparece"
grep -qF '#retros/' "$pagina"; es=$?; [ "$es" = 1 ]; tap_check $? "una retro sin PR ni issue no muestra su ruta como issue"
tarjeta_de 42 | grep -qF 'issue #7'; tap_check $? "la tarjeta de un PR muestra su issue"
tarjeta_de 42 | grep -qF 'retro del issue sin PR todavía'; tap_check $? "una retro con solo el issue va a la tarjeta del PR de ese issue"
tarjeta_de 55 | grep -qF 'en latin-1'; tap_check $? "una retro que no es UTF-8 aparece igual"
case "$out" in *Traceback*) tap_fail "una retro que no es UTF-8 no da traceback" "$out" ;; *) tap_ok "una retro que no es UTF-8 no da traceback" ;; esac
tarjeta_de 66 | grep -qF 'Resumen antes de las secciones.'; tap_check $? "el texto antes del primer título no se pierde"
pedidos=$({ grep -o 'pullRequest(number:[0-9]*)' "$GH_LOG" || true; } | tr -dc '0-9\n' | sort -n | tr '\n' ' ')
[ "$pedidos" = "42 55 66 77 88 " ]; tap_check $? "a gh le pide solo los PRs que citan las retros" "$pedidos"
[ "$(wc -l <"$GH_LOG" | tr -d ' ')" = 1 ]; tap_check $? "a gh lo llama una vez" "$(cat "$GH_LOG")"

# 14. El fetch de las retros no se cuelga pidiendo una clave ni esperando una conexión: ssh en modo batch y con
#     tiempo de conexión, sin prompt de git. ssh es un falso en PATH (sin red).
cat >"$TMP/bin/ssh" <<'EOF'
#!/bin/sh
printf 'args: %s\nprompt: %s\n' "$*" "${GIT_TERMINAL_PROMPT-}" >"$TMP_SSH_LOG"
exit 255
EOF
chmod +x "$TMP/bin/ssh"
git clone -q "$TMP/remoto.git" "$TMP/ssh" 2>/dev/null
git -C "$TMP/ssh" remote set-url origin ssh://example.invalid/x.git
tap_run out 0 env -u GIT_SSH_COMMAND -u GIT_SSH TMP_SSH_LOG="$TMP/ssh.log" python3 -I "$BITACORA" -C "$TMP/ssh"
grep -qF 'BatchMode=yes' "$TMP/ssh.log"; tap_check $? "el fetch usa ssh sin pedir clave" "$(cat "$TMP/ssh.log" 2>/dev/null)"
grep -qF 'ConnectTimeout=' "$TMP/ssh.log"; tap_check $? "el fetch usa ssh con tiempo de conexión"
grep -qxF 'prompt: 0' "$TMP/ssh.log"; tap_check $? "el fetch corre sin prompt de git"

tap_done
