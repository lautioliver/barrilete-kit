#!/usr/bin/env python3
"""Suma entradas a la bitácora del proyecto (docs/bitacora.html), una sección por tema (#343).

Lo usa el skill /bitacora: el chat escribe la entrada (un fragmento HTML) con el contexto de la conversación y este
script la inserta. Solo inserta, nunca reescribe: una sección nueva va al final de <main>, una entrada al final de su
sección y el link al final del índice; lo que ya estaba queda byte a byte igual.

  bitacora_add.py [-C <dir>] find --topic <tema>
      exact <slug>               la sección ya existe (sale con 0)
      none <slug>                no hay sección con ese tema (sale con 0)
      similar <slug>\\t<tema>     una línea por cada sección con un nombre parecido (sale con 3)
  bitacora_add.py [-C <dir>] add --topic <tema> --entry <fragmento.html> [--new | --into <slug>]
      Con un nombre parecido y sin --new ni --into, no escribe y sale con 3 (el skill le pregunta a la persona).

Salidas: 0 bien, 3 hay secciones parecidas, 64 error de uso (también una entrada rechazada), 65 el archivo existe
pero no tiene los marcadores (se editó a mano): no se toca. Contrato del diseño: docs/agents/bitacora.md.
"""
import argparse
import datetime
import difflib
import html
import json
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
from html.parser import HTMLParser

AQUI = os.path.dirname(os.path.abspath(__file__))
TEMA_BARRILETE = os.path.join(AQUI, "bitacora", "barrilete.css")
RUTA = os.path.join("docs", "bitacora.html")
FUENTES = ("https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@600;800"
           "&family=JetBrains+Mono:wght@400;500;700&display=swap")
PARECIDO = 0.8   # SequenceMatcher.ratio() entre slugs desde el que dos temas se consideran parecidos

TEXTOS = {
    "en": {"title": "Project log", "contents": "Contents",
           "sub": "What we talked about and decided, by topic. Each entry is added with <code>/bitacora &lt;topic&gt;</code> "
                  "from the chat and nothing above it is rewritten."},
    "es": {"title": "Bitácora del proyecto", "contents": "Índice",
           "sub": "Lo que se habló y se decidió, por tema. Cada entrada se suma con <code>/bitacora &lt;tema&gt;</code> "
                  "desde el chat y no se reescribe nada de lo anterior."},
}

MARCA_NAV = "<!-- bitacora:nav -->"
MARCA_MAIN = "<!-- bitacora:main -->"
SECCION = re.compile(r'^<section id="([a-z0-9-]+)" data-topic="([^"]*)">$', re.M)

# Lo que una entrada no puede traer: código, estilos o marcos, manejadores on…=, javascript:, comentarios (podrían
# esconder o imitar los marcadores) y etiquetas de la estructura de la página.
PROHIBIDO = re.compile(
    r"<\s*/?\s*(script|style|iframe|object|embed|frame|frameset|base|meta|link|form|html|head|body|header|nav|main"
    r"|section|article|template|svg|math)\b"
    r"|<[^>]*\son[a-z]+\s*="
    r"|javascript\s*:"
    r"|<!--",
    re.I)
VACIAS = {"area", "br", "col", "hr", "img", "input", "source", "track", "wbr"}

# La estructura de la página y los componentes de una entrada: solo usan los tokens del contrato.
ESTRUCTURA = """
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:400 14px/1.6 var(--font-mono)}
header,nav,main{max-width:960px;margin:0 auto;padding:0 16px}
header{padding-top:32px}
h1{font:800 clamp(28px,5vw,40px)/1.1 var(--font-display);margin:0 0 8px}
h2{font:600 22px/1.3 var(--font-display);margin:0 0 12px}
h3{font:600 16px/1.3 var(--font-display);margin:16px 0 6px}
a{color:var(--accent)}
code{background:var(--surface);padding:1px 5px;border-radius:4px}
.sub{color:var(--muted);margin:0 0 20px}
nav{margin-bottom:24px}
nav h2{font:700 12px/1.4 var(--font-mono);text-transform:uppercase;letter-spacing:.06em;color:var(--muted);margin:0 0 6px}
nav ol{margin:0;padding-left:20px}
main{padding-bottom:64px}
main>section{border-top:1px solid var(--surface);padding-top:24px;margin-top:24px}
main>section>h2 a{color:inherit;text-decoration:none}
.entrada{background:var(--card);border:1px solid var(--surface);border-radius:12px;padding:16px;margin-bottom:14px;
  overflow-wrap:anywhere}
.entrada p{margin:0 0 10px}
.fecha{color:var(--muted);font-weight:700}
.ok{color:var(--ok)}.warn{color:var(--warn)}.danger{color:var(--danger)}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px;margin:10px 0}
.kpi{background:var(--surface);border-radius:10px;padding:10px 12px;border-left:4px solid var(--accent);color:var(--ink)}
.kpi b{display:block;font:800 26px/1.1 var(--font-display)}
.kpi.ok{border-left-color:var(--ok)}.kpi.warn{border-left-color:var(--warn)}.kpi.danger{border-left-color:var(--danger)}
.kpi.ok b{color:var(--ok)}.kpi.warn b{color:var(--warn)}.kpi.danger b{color:var(--danger)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;margin:10px 0}
.card{background:var(--surface);border-radius:10px;padding:12px;border-top:4px solid var(--muted);color:var(--ink)}
.card.ok{border-top-color:var(--ok)}.card.warn{border-top-color:var(--warn)}.card.danger{border-top-color:var(--danger)}
.card h3{margin-top:0}
.tbl{display:block;overflow-x:auto;border-collapse:collapse;margin:10px 0;max-width:100%}
.tbl th,.tbl td{border:1px solid var(--surface);padding:6px 10px;text-align:left;vertical-align:top}
.tbl th{background:var(--surface)}
.note{background:var(--surface);border-left:4px solid var(--accent);border-radius:8px;padding:10px 12px;margin:10px 0}
.note.ok{border-left-color:var(--ok)}.note.warn{border-left-color:var(--warn)}.note.danger{border-left-color:var(--danger)}
.bars{margin:10px 0}
.bar{display:grid;grid-template-columns:minmax(80px,30%) 1fr;gap:8px;align-items:center;margin:4px 0}
.bar i{display:block;height:14px;border-radius:4px;background:var(--accent);width:var(--v,0%)}
.bar.ok i{background:var(--ok)}.bar.warn i{background:var(--warn)}.bar.danger i{background:var(--danger)}
.flow{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:10px 0;padding:0;list-style:none}
.flow li{background:var(--surface);border-radius:8px;padding:6px 10px}
.flow li+li::before{content:"→";margin-right:6px;color:var(--muted)}
"""


class ErrorDeUso(Exception):
    pass


class ArchivoRoto(Exception):
    pass


class Argumentos(argparse.ArgumentParser):
    def error(self, message):
        raise ErrorDeUso(message)


def slug(tema):
    plano = unicodedata.normalize("NFKD", tema).encode("ascii", "ignore").decode("ascii").lower()
    return re.sub(r"[^a-z0-9]+", "-", plano).strip("-")


def leer_css(ruta):
    with open(ruta, encoding="utf-8") as f:
        # Un "</style" dentro del CSS cerraría su bloque y lo que sigue sería HTML: se corta con un escape de CSS.
        return re.sub(r"</(style)", r"<\\/\1", f.read(), flags=re.I)


def temas(repo):
    lista = [("barrilete", leer_css(TEMA_BARRILETE))]
    propio = os.path.join(repo, ".barrilete", "bitacora.css")
    if os.path.isfile(propio):
        lista.append(("project", leer_css(propio)))
    return lista


def idioma(repo):
    try:
        with open(os.path.join(repo, ".agent-kit.json"), encoding="utf-8") as f:
            valor = json.load(f).get("language")
    except (OSError, ValueError, AttributeError):
        valor = None
    return valor if valor in TEXTOS else "en"


def pagina_vacia(repo):
    lang = idioma(repo)
    tx = TEXTOS[lang]
    estilos = "".join(f'<style id="theme-{nombre}">\n{css}\n</style>\n' for nombre, css in temas(repo))
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
<header>
<h1>{html.escape(tx["title"])}</h1>
<p class="sub">{tx["sub"]}</p>
</header>
<nav aria-label="{html.escape(tx["contents"])}">
<h2>{html.escape(tx["contents"])}</h2>
<ol>
{MARCA_NAV}
</ol>
</nav>
<main>
{MARCA_MAIN}
</main>
</body>
</html>
"""


def secciones(texto):
    """Las secciones de la página, en orden: [(slug, tema)]."""
    return [(s, html.unescape(t)) for s, t in SECCION.findall(texto)]


def marca_fin(s):
    return f"<!-- bitacora:end {s} -->"


def validar(texto):
    for marca in (MARCA_NAV, MARCA_MAIN):
        if texto.count(marca) != 1:
            raise ArchivoRoto(f"no encuentro una sola vez el marcador {marca}")
    for s, _ in secciones(texto):
        if texto.count(marca_fin(s)) != 1:
            raise ArchivoRoto(f"la sección {s} no tiene una sola vez su marcador de fin")


def parecidas(objetivo, lista):
    return [(s, t) for s, t in lista if s != objetivo and (
        f"-{objetivo}-" in f"-{s}-" or f"-{s}-" in f"-{objetivo}-"
        or difflib.SequenceMatcher(None, objetivo, s).ratio() >= PARECIDO)]


class Balance(HTMLParser):
    """Cuenta las etiquetas abiertas y cerradas: una entrada que deja algo abierto se comería la página que sigue."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.pila, self.mal = [], None

    def handle_starttag(self, tag, attrs):
        if tag not in VACIAS:
            self.pila.append(tag)

    def handle_startendtag(self, tag, attrs):
        pass

    def handle_endtag(self, tag):
        if tag in VACIAS:
            return
        if not self.pila or self.pila[-1] != tag:
            self.mal = self.mal or f"</{tag}> no cierra lo último que se abrió"
        else:
            self.pila.pop()


def leer_entrada(ruta):
    try:
        with open(ruta, encoding="utf-8") as f:
            texto = f.read()
    except (OSError, UnicodeDecodeError) as err:
        raise ErrorDeUso(f"--entry: no puedo leer {ruta} ({err.__class__.__name__})")
    texto = texto.strip("\n")
    if not texto.strip():
        raise ErrorDeUso("--entry: la entrada está vacía")
    m = PROHIBIDO.search(texto)
    if m:
        raise ErrorDeUso(f"--entry: la entrada no puede traer {m.group(0).strip()!r} (ni scripts, estilos, manejadores "
                         "on…=, javascript:, comentarios ni etiquetas de la estructura de la página)")
    b = Balance()
    b.feed(texto)
    b.close()
    if b.mal or b.pila:
        raise ErrorDeUso(f"--entry: el HTML no está balanceado ({b.mal or 'queda abierto <' + b.pila[-1] + '>'})")
    return texto


def insertar(texto, marca, bloque):
    """Pone el bloque en las líneas de arriba de la marca: lo que ya estaba no cambia."""
    i = texto.index(marca)
    return texto[:i] + bloque + texto[i:]


def escribir(ruta, texto):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(ruta), prefix=".bitacora-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(texto)
        os.replace(tmp, ruta)
    except BaseException:
        os.unlink(tmp)
        raise


def raiz(directorio):
    r = subprocess.run(["git", "-C", directorio, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if r.returncode != 0:
        raise ErrorDeUso(f"{directorio} no es un repo de git")
    top = r.stdout.strip()
    # git resuelve los enlaces (/var → /private/var en macOS): se sube desde la ruta tal como vino hasta la raíz.
    camino = os.path.abspath(directorio)
    while not os.path.samefile(camino, top):
        arriba = os.path.dirname(camino)
        if arriba == camino:
            return top
        camino = arriba
    return camino


def leer_pagina(ruta):
    if not os.path.exists(ruta):
        return None
    with open(ruta, encoding="utf-8", newline="") as f:
        texto = f.read()
    validar(texto)
    return texto


def imprimir_parecidas(lista):
    for s, t in lista:
        print(f"similar {s}\t{t}")


def cmd_find(repo, a):
    s = slug(a.topic)
    if not s:
        raise ErrorDeUso("--topic: el tema necesita al menos una letra o un número")
    texto = leer_pagina(os.path.join(repo, RUTA))
    lista = secciones(texto) if texto else []
    if s in dict(lista):
        print(f"exact {s}")
        return 0
    cerca = parecidas(s, lista)
    if cerca:
        imprimir_parecidas(cerca)
        return 3
    print(f"none {s}")
    return 0


def cmd_add(repo, a):
    s = slug(a.topic)
    if not s:
        raise ErrorDeUso("--topic: el tema necesita al menos una letra o un número")
    entrada = leer_entrada(a.entry)
    ruta = os.path.join(repo, RUTA)
    texto = leer_pagina(ruta)
    if texto is None:
        texto = pagina_vacia(repo)
    lista = dict(secciones(texto))
    if a.into:
        if a.into not in lista:
            raise ErrorDeUso(f"--into: no hay una sección {a.into}")
        destino, nueva = a.into, False
    elif s in lista:
        if a.new:
            raise ErrorDeUso(f"--new: ya hay una sección {s}; sin --new la entrada se suma a esa")
        destino, nueva = s, False
    else:
        cerca = parecidas(s, list(lista.items()))
        if cerca and not a.new:
            imprimir_parecidas(cerca)
            print("bitacora_add.py: hay secciones con un nombre parecido; repetí con --into <slug> o --new",
                  file=sys.stderr)
            return 3
        destino, nueva = s, True
    if nueva:
        tema = html.escape(a.topic.strip())
        texto = insertar(texto, MARCA_NAV, f'<li><a href="#{destino}">{tema}</a></li>\n')
        texto = insertar(texto, MARCA_MAIN, f'<section id="{destino}" data-topic="{tema}">\n'
                                            f'<h2><a href="#{destino}">{tema}</a></h2>\n'
                                            f'{marca_fin(destino)}\n</section>\n')
    hoy = (a.date or datetime.date.today()).isoformat()
    texto = insertar(texto, marca_fin(destino), f'<article class="entrada">\n'
                                                f'<p class="fecha"><time datetime="{hoy}">{hoy}</time></p>\n'
                                                f'{entrada}\n</article>\n')
    escribir(ruta, texto)
    print(f"ok: {'new' if nueva else 'append'} {destino} {ruta}")
    return 0


def fecha(valor):
    try:
        return datetime.date.fromisoformat(valor)
    except ValueError:
        raise argparse.ArgumentTypeError("tiene que ser AAAA-MM-DD")


def main(argv):
    p = Argumentos(prog="bitacora_add.py", description=__doc__.split("\n")[0])
    p.add_argument("-C", dest="repo", default=".")
    sub = p.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("find")
    f.add_argument("--topic", required=True)
    ad = sub.add_parser("add")
    ad.add_argument("--topic", required=True)
    ad.add_argument("--entry", required=True)
    ad.add_argument("--date", type=fecha, help="fecha de la entrada (AAAA-MM-DD); por defecto, hoy")
    excl = ad.add_mutually_exclusive_group()
    excl.add_argument("--new", action="store_true", help="crea una sección aunque haya una parecida")
    excl.add_argument("--into", help="suma la entrada a esta sección (su slug)")
    for sp in (f, ad):
        sp.error = p.error
    a = p.parse_args(argv)
    repo = raiz(a.repo)
    return cmd_find(repo, a) if a.cmd == "find" else cmd_add(repo, a)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except ErrorDeUso as err:
        print(f"bitacora_add.py: {err}", file=sys.stderr)
        sys.exit(64)
    except ArchivoRoto as err:
        print(f"bitacora_add.py: {RUTA} no se toca: {err}. Arreglalo a mano o restauralo con git.", file=sys.stderr)
        sys.exit(65)
    except (OSError, UnicodeDecodeError) as err:
        print(f"bitacora_add.py: {err}", file=sys.stderr)
        sys.exit(1)
