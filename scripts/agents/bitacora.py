#!/usr/bin/env python3
"""Bitácora de agentes (#339): una página con lo que hizo cada agente en cada PR, armada con las retros.

Lee las retros que retro.sh guarda en la rama agents/retros (la del remoto origin si existe; si no, la local) y los
PRs de `gh pr list`, y escribe .barrilete/bitacora.html (ignorado por git): una tarjeta por PR con cada agente que lo
tocó (rol y modelo) y su reporte. Si gh falla, la página sale igual, sin títulos ni estado de los PRs.

Uso: python3 scripts/agents/bitacora.py [-C <repo>] [--theme barrilete|<ruta.css>] [--out <ruta>]

  -C        el repo (por defecto, el de la carpeta actual).
  --theme   el diseño. Por defecto, el de barrilete (bitacora/barrilete.css) más .barrilete/bitacora.css del
            proyecto si existe, que va después y pisa los tokens que define. `barrilete` ignora el del proyecto;
            una ruta usa ese archivo en su lugar.
  --out     dónde escribir la página (por defecto, .barrilete/bitacora.html del repo).

Las etiquetas siguen "language" de .agent-kit.json (en o es; sin él, en).
El formato de las retros que lee y el contrato de tokens del diseño: docs/agents/bitacora.md.
Imprime "ok: <ruta>" y termina con 0; con un error de uso, una línea y 64.
"""
import argparse
import html
import json
import os
import re
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
TEMA_BARRILETE = os.path.join(AQUI, "bitacora", "barrilete.css")
RAMA = "agents/retros"
FUENTES = ("https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@600;800"
           "&family=JetBrains+Mono:wght@400;500;700&display=swap")

TEXTOS = {
    "en": {
        "title": "Agent log", "sub": "What each agent did in each change, from the retros on <code>agents/retros</code>.",
        "empty": "There are no retros yet: agents leave one with <code>retro.sh</code> when they finish.",
        "filter": "Filter by PR, issue, agent or text", "none": "Nothing matches the filter.",
        "pr": "PR", "issue": "issue", "no_pr": "no PR",
        "state": {"MERGED": "merged", "OPEN": "open", "CLOSED": "closed"},
        "roles": {"implementer": "implementer", "implementer-light": "light implementer", "reviewer": "reviewer",
                  "orchestrator": "orchestrator", "session": "session"},
        "skills": {"implement-issue": "implemented", "review-pr": "reviewed", "orchestrate": "orchestrated",
                   "improve-skills": "improved the skills"},
        "sections": {"Desvíos": "Deviations", "Decisiones no cubiertas": "Decisions not covered",
                     "Lo que encontró la revisión": "What the review found", "Propuesta": "Proposal"},
        "report": "Report",
    },
    "es": {
        "title": "Bitácora de agentes",
        "sub": "Lo que hizo cada agente en cada cambio, según las retros de <code>agents/retros</code>.",
        "empty": "Todavía no hay retros: los agentes dejan una con <code>retro.sh</code> al terminar.",
        "filter": "Filtrar por PR, issue, agente o texto", "none": "Nada coincide con el filtro.",
        "pr": "PR", "issue": "issue", "no_pr": "sin PR",
        "state": {"MERGED": "mergeado", "OPEN": "abierto", "CLOSED": "cerrado"},
        "roles": {"implementer": "implementador", "implementer-light": "implementador liviano", "reviewer": "revisor",
                  "orchestrator": "orquestador", "session": "sesión"},
        "skills": {"implement-issue": "implementó", "review-pr": "revisó", "orchestrate": "orquestó",
                   "improve-skills": "mejoró las skills"},
        "sections": {"Deviations": "Desvíos", "Decisions not covered": "Decisiones no cubiertas",
                     "What the review found": "Lo que encontró la revisión", "Proposal": "Propuesta"},
        "report": "Reporte",
    },
}
ESTADO_CLASE = {"MERGED": "ok", "OPEN": "warn", "CLOSED": "danger"}

# La estructura de la página: solo usa los tokens del contrato (docs/agents/bitacora.md).
ESTRUCTURA = """
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:400 14px/1.55 var(--font-mono)}
main{max-width:960px;margin:0 auto;padding:32px 16px 64px}
h1{font:800 clamp(28px,5vw,40px)/1.1 var(--font-display);margin:0 0 8px}
h2{font:600 18px/1.3 var(--font-display);margin:0}
a{color:var(--accent)}
code{background:var(--surface);padding:1px 5px;border-radius:4px}
.sub{color:var(--muted);margin:0 0 20px}
#filtro{width:100%;font:inherit;color:var(--ink);background:var(--card);border:1px solid var(--muted);
  border-radius:8px;padding:10px 12px;margin-bottom:16px}
.cambio{background:var(--card);border:1px solid var(--surface);border-radius:12px;padding:16px;margin-bottom:14px}
.cabeza{display:flex;flex-wrap:wrap;gap:8px 12px;align-items:baseline;margin-bottom:10px}
.meta{color:var(--muted)}
.estado{font-weight:700}
.estado.ok{color:var(--ok)}.estado.warn{color:var(--warn)}.estado.danger{color:var(--danger)}
.agente{background:var(--surface);border-radius:8px;padding:10px 12px;margin-top:8px}
.etiqueta{font-weight:700;color:var(--accent)}
.agente h3{font:700 12px/1.4 var(--font-mono);text-transform:uppercase;letter-spacing:.04em;color:var(--muted);
  margin:10px 0 2px}
.agente p{margin:0;overflow-wrap:anywhere}
"""

FILTRO_JS = """
(function(){var q=document.getElementById('filtro'),v=document.getElementById('vacio-filtro');if(!q)return;
q.addEventListener('input',function(){var t=q.value.toLowerCase(),n=0;
document.querySelectorAll('.cambio').forEach(function(c){var s=!t||c.textContent.toLowerCase().indexOf(t)>=0;
c.hidden=!s;if(s)n++;});v.hidden=n>0;});})();
"""


class ErrorDeUso(Exception):
    pass


class Argumentos(argparse.ArgumentParser):
    def error(self, message):
        raise ErrorDeUso(message)


def git(repo, *args, check=True):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, check=check)


def punta_retros(repo):
    """El commit de agents/retros: el del remoto origin si existe (lo trae antes), si no, el local; None sin rama."""
    if git(repo, "remote", "get-url", "origin", check=False).returncode == 0:
        git(repo, "fetch", "-q", "origin", f"+refs/heads/{RAMA}:refs/remotes/origin/{RAMA}", check=False)
        r = git(repo, "rev-parse", "-q", "--verify", f"refs/remotes/origin/{RAMA}^{{commit}}", check=False)
        if r.returncode == 0:
            return r.stdout.strip()
    r = git(repo, "rev-parse", "-q", "--verify", f"refs/heads/{RAMA}^{{commit}}", check=False)
    return r.stdout.strip() if r.returncode == 0 else None


def leer_retro(texto, ruta):
    """El frontmatter (claves de retro.sh) y las secciones **Título:** del cuerpo. None si no tiene frontmatter."""
    m = re.match(r"---\r?\n(.*?)\r?\n---\r?\n?(.*)", texto, re.S)
    if not m:
        return None
    meta = {}
    for linea in m.group(1).splitlines():
        if ":" in linea:
            k, v = linea.split(":", 1)
            meta.setdefault(k.strip(), v.strip())
    partes = re.split(r"^\*\*([^*\n]+?):\*\*", m.group(2), flags=re.M)
    secciones = [(partes[i].strip(), partes[i + 1].strip()) for i in range(1, len(partes) - 1, 2)]
    if not secciones and m.group(2).strip():
        secciones = [(None, m.group(2).strip())]
    meta["_secciones"], meta["_archivo"] = secciones, ruta
    return meta


def leer_retros(repo, punta):
    if not punta:
        return []
    rutas = git(repo, "ls-tree", "-r", "-z", "--name-only", punta, "retros/").stdout.split("\0")
    retros = []
    for ruta in sorted(r for r in rutas if r.endswith(".md")):
        texto = git(repo, "show", f"{punta}:{ruta}").stdout
        retro = leer_retro(texto, ruta)
        if retro:
            retros.append(retro)
    return retros


def leer_prs(repo):
    try:
        out = subprocess.run(["gh", "pr", "list", "--state", "all", "--limit", "1000",
                              "--json", "number,title,state,url"],
                             cwd=repo, capture_output=True, text=True, check=True, timeout=60).stdout
        return {str(p["number"]): p for p in json.loads(out) if isinstance(p, dict) and "number" in p}
    except (OSError, subprocess.SubprocessError, ValueError, TypeError):
        return {}


def numero(valor):
    v = (valor or "").strip().lstrip("#")
    return v if v.isdigit() else ""


def texto_html(t):
    t = html.escape(t)
    t = re.sub(r"`([^`\n]+)`", r"<code>\1</code>", t)
    return t.replace("\n", "<br>")


def tarjeta(clave, retros, prs, tx):
    pr, issue = clave
    e = html.escape
    if pr:
        info = prs.get(pr, {})
        url = info.get("url") if str(info.get("url", "")).startswith("https://") else ""
        nombre = f"{tx['pr']} #{pr}"
        titulo = f'<a href="{e(url)}">{e(nombre)}</a>' if url else e(nombre)
        if info.get("title"):
            titulo += f" · {e(info['title'])}"
        estado = str(info.get("state", ""))
        chip = (f'<span class="estado {ESTADO_CLASE[estado]}">{e(tx["state"][estado])}</span>'
                if estado in ESTADO_CLASE else "")
    else:
        titulo, chip = e(tx["no_pr"]), ""
    extra = f'<span class="meta">{e(tx["issue"])} #{e(issue)}</span>' if issue else ""
    agentes = []
    for r in retros:
        rol, modelo = r.get("role") or "session", r.get("model") or "unknown"
        hizo = tx["skills"].get(r.get("skill", ""), r.get("skill", ""))
        secciones = "".join(
            f"<h3>{e(tx['sections'].get(t, t) if t else tx['report'])}</h3><p>{texto_html(c)}</p>"
            for t, c in r["_secciones"])
        agentes.append(
            f'<div class="agente" data-role="{e(rol)}" data-model="{e(modelo)}">'
            f'<span class="etiqueta">{e(tx["roles"].get(rol, rol))} · {e(modelo)}</span> '
            f'<span class="meta">{e(hizo)} · {e(r.get("date", ""))}</span>{secciones}</div>')
    attr = f' data-pr="{e(pr)}"' if pr else ""
    return (f'<article class="cambio"{attr}><div class="cabeza"><h2>{titulo}</h2>{chip}{extra}</div>'
            f'{"".join(agentes)}</article>')


def construir(retros, prs, lang, temas):
    tx = TEXTOS[lang]
    grupos = {}
    for r in retros:
        pr, issue = numero(r.get("pr")), numero(r.get("issue"))
        clave = (pr, "") if pr else ("", issue) if issue else ("", r["_archivo"])
        grupos.setdefault(clave, []).append(r)
    # Lo más reciente arriba: por la fecha de su última retro, y a igual fecha, por número.
    def orden(item):
        (pr, issue), rs = item
        n = int(pr or (issue if issue.isdigit() else 0) or 0)
        return (max(r.get("date", "") for r in rs), n)
    tarjetas = [tarjeta(k, sorted(rs, key=lambda r: r.get("date", "")), prs, tx)
                for k, rs in sorted(grupos.items(), key=orden, reverse=True)]
    if tarjetas:
        cuerpo = (f'<input id="filtro" type="search" placeholder="{html.escape(tx["filter"])}" '
                  f'aria-label="{html.escape(tx["filter"])}">' + "".join(tarjetas)
                  + f'<p id="vacio-filtro" class="sub" hidden>{html.escape(tx["none"])}</p>')
    else:
        cuerpo = f'<p class="sub" data-empty>{tx["empty"]}</p>'
    estilos = "".join(f'<style id="theme-{nombre}">\n{css}\n</style>\n' for nombre, css in temas)
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(tx["title"])}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="{html.escape(FUENTES)}">
{estilos}<style id="structure">{ESTRUCTURA}</style>
</head>
<body>
<main>
<h1>{html.escape(tx["title"])}</h1>
<p class="sub">{tx["sub"]}</p>
{cuerpo}
</main>
<script>{FILTRO_JS}</script>
</body>
</html>
"""


def leer_css(ruta):
    with open(ruta, encoding="utf-8") as f:
        # Un "</style" dentro del CSS cerraría su bloque y lo que sigue sería HTML: se corta con un escape de CSS.
        return re.sub(r"</(style)", r"<\\/\1", f.read(), flags=re.I)


def temas(repo, tema):
    lista = [("barrilete", leer_css(TEMA_BARRILETE))]
    if tema == "barrilete":
        return lista
    ruta = os.path.join(repo, ".barrilete", "bitacora.css") if tema is None else tema
    if tema is not None and not os.path.isfile(ruta):
        raise ErrorDeUso(f"--theme: no encuentro {ruta} (usá una ruta a un .css o `barrilete`)")
    if os.path.isfile(ruta):
        lista.append(("project", leer_css(ruta)))
    return lista


def idioma(repo):
    try:
        with open(os.path.join(repo, ".agent-kit.json"), encoding="utf-8") as f:
            valor = json.load(f).get("language")
    except (OSError, ValueError, AttributeError):
        valor = None
    return valor if valor in TEXTOS else "en"


def main(argv):
    p = Argumentos(prog="bitacora.py", description=__doc__.split("\n")[0])
    p.add_argument("-C", dest="repo", default=".")
    p.add_argument("--theme")
    p.add_argument("--out")
    a = p.parse_args(argv)
    r = git(a.repo, "rev-parse", "--show-toplevel", check=False)
    if r.returncode != 0:
        raise ErrorDeUso(f"{a.repo} no es un repo de git")
    repo = r.stdout.strip()
    # git resuelve los enlaces (/var → /private/var en macOS): si -C ya es la raíz, se usa tal como vino.
    if os.path.samefile(repo, a.repo):
        repo = os.path.abspath(a.repo)
    pagina = construir(leer_retros(repo, punta_retros(repo)), leer_prs(repo), idioma(repo),
                       temas(repo, a.theme))
    salida = a.out or os.path.join(repo, ".barrilete", "bitacora.html")
    os.makedirs(os.path.dirname(os.path.abspath(salida)), exist_ok=True)
    with open(salida, "w", encoding="utf-8") as f:
        f.write(pagina)
    print(f"ok: {salida}")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except ErrorDeUso as err:
        print(f"bitacora.py: {err}", file=sys.stderr)
        sys.exit(64)
    except (OSError, subprocess.CalledProcessError) as err:
        print(f"bitacora.py: {err}", file=sys.stderr)
        sys.exit(1)
