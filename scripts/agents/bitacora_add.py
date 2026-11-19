#!/usr/bin/env python3
"""Suma entradas a la bitácora del proyecto, partida por mes (#343, #365).

docs/bitacora.html es la portada: el índice de meses y una sección por tema, con un enlace a cada mes donde el tema
tiene entradas. Las entradas están en la página de su mes, docs/bitacora/AAAA-MM.html, en la sección de su tema.

Lo usa el skill /bitacora: el chat escribe la entrada (un fragmento HTML) con el contexto de la conversación y este
script la inserta. Solo inserta, nunca reescribe: en la página del mes, una sección nueva va al final de <main>, una
entrada al final de su sección y el link al final del índice; en la portada, un mes va al principio de la lista de
meses y un tema al final. Lo que ya estaba queda byte a byte igual, y las páginas de los meses pasados no se tocan.

Una bitácora de antes de #365 (docs/bitacora.html con las entradas adentro) pasa sin cambios a
docs/bitacora-anterior.html con la primera entrada nueva, y la portada la enlaza. Si falta la portada, se arma de nuevo
con lo que hay en esa página y en las de los meses.

  bitacora_add.py [-C <dir>] find --topic <tema>
      exact <slug>               el tema ya existe, en cualquier mes (sale con 0)
      none <slug>                no hay un tema con ese nombre (sale con 0)
      similar <slug>\\t<tema>     una línea por cada tema con un nombre parecido (sale con 3)
  bitacora_add.py [-C <dir>] add --topic <tema> --entry <fragmento.html> [--new | --into <slug>] [--date AAAA-MM-DD]
      Con un nombre parecido y sin --new ni --into, no escribe y sale con 3 (el skill le pregunta a la persona).
      Imprime "ok: new|append <slug> <página del mes>": append si el tema ya existía, en cualquier mes.
      --date: no puede ser una fecha futura ni de un mes anterior a la última página que existe.

Salidas: 0 bien, 3 hay temas parecidos, 64 error de uso (también una entrada rechazada), 65 una página existe pero no
tiene los marcadores (se editó a mano), o docs/bitacora-anterior.html ya existe y no se puede mover ahí la bitácora de
antes: no se toca nada. Componentes: el skill (.claude/skills/bitacora/SKILL.md); diseño: docs/agents/bitacora.md en el kit.
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
RUTA = os.path.join("docs", "bitacora.html")                # la portada
RUTA_ANTERIOR = os.path.join("docs", "bitacora-anterior.html")   # una bitácora de antes de #365, sin cambios
DIR_MESES = os.path.join("docs", "bitacora")
PAGINA_MES = re.compile(r"^(\d{4}-(?:0[1-9]|1[0-2]))\.html$")
# Los mismos lugares, como los escribe un link: desde la portada y desde la página de un mes.
HREF_ANTERIOR = "bitacora-anterior.html"
HREF_PORTADA = "../bitacora.html"
FUENTES = ("https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:wght@600;800"
           "&family=JetBrains+Mono:wght@400;500;700&display=swap")
PARECIDO = 0.8   # SequenceMatcher.ratio() entre slugs desde el que dos temas se consideran parecidos

TEXTOS = {
    "en": {"title": "Project log", "contents": "Contents", "stamp": "PROJECT LOG",
           "motto": "The agents fly.<br>You hold the line.",
           "sub": "The ideas we think through in the chat, by topic and with drawings: where each one came from, what was "
                  "dropped and what was decided. Each entry is added with <code>/bitacora &lt;topic&gt;</code> and nothing "
                  "above it is rewritten.",
           "since": "started on", "leash": ("talk", "decide", "log"),
           "months": "Months", "cover": "Front page", "earlier": "earlier",
           "footer": "Each section is a topic and each entry was written from a chat with <code>/bitacora</code>. "
                     "Nothing above an entry is rewritten."},
    "es": {"title": "Bitácora del proyecto", "contents": "Índice", "stamp": "BITÁCORA",
           "motto": "Los agentes vuelan.<br>Vos tenés la rienda.",
           "sub": "Las ideas que pensamos en el chat, por tema y con dibujos: de dónde salió cada una, qué se descartó y qué "
                  "se decidió. Cada entrada se suma con <code>/bitacora &lt;tema&gt;</code> y no se reescribe nada de lo "
                  "anterior.",
           "since": "empezada el", "leash": ("charla", "decisión", "bitácora"),
           "months": "Meses", "cover": "Portada", "earlier": "anterior",
           "footer": "Cada sección es un tema y cada entrada se escribió desde un chat con <code>/bitacora</code>. "
                     "Lo que está arriba de una entrada no se reescribe."},
}

MARCA_NAV = "<!-- bitacora:nav -->"
MARCA_MAIN = "<!-- bitacora:main -->"
MARCA_MESES = "<!-- bitacora:months -->"   # solo en la portada: es lo que la distingue de una bitácora de antes
MARCAS_PAGINA = (MARCA_NAV, MARCA_MAIN)
MARCAS_PORTADA = (MARCA_MESES, MARCA_MAIN)
SECCION = re.compile(r'^<section id="([a-z0-9-]+)" data-topic="([^"]*)">\r?$', re.M)
# Ids que ya usa la página: una sección con uno de ellos rompería su link.
RESERVADOS = re.compile(r"^(theme-.*|structure)$")

# Una entrada es una lista permitida de HTML: solo estas etiquetas y, de cada una, solo estos atributos. Se revisa
# después de que HTMLParser decodifica las entidades, así que "jav&#x61;script:" llega como "javascript:".
ETIQUETAS = {"p", "br", "hr", "strong", "b", "em", "i", "u", "s", "small", "mark", "code", "pre", "kbd", "sub", "sup",
             "span", "div", "h3", "h4", "ul", "ol", "li", "dl", "dt", "dd", "blockquote", "a", "abbr", "time",
             "table", "caption", "thead", "tbody", "tfoot", "tr", "th", "td"}
ATRIBUTOS = {"class", "title"}
ATRIBUTOS_DE = {"a": {"href"}, "time": {"datetime"}, "th": {"colspan", "rowspan", "scope"},
                "td": {"colspan", "rowspan"}, "i": {"style"}}
VACIAS = {"br", "hr"}
CLASE = re.compile(r"^[A-Za-z0-9_ -]*$")
ESTILO = re.compile(r"^\s*--v\s*:\s*\d{1,3}(\.\d+)?%\s*;?\s*$")     # solo el ancho de una barra
# Sin esquema (relativo) o uno de estos. //host, \\host y /\host son de otro sitio aunque no tengan esquema.
HREF = re.compile(r"^(https?://|mailto:|#)[^\s]*$|^(?![/\\]{2})[^:\s]*$", re.I)
# Y sobre toda la entrada: comentarios, CDATA e instrucciones de proceso, que podrían esconder marcadores.
PROHIBIDO = re.compile(r"<!--|<!\[CDATA|<\?", re.I)

# La estructura de la página y los componentes de una entrada, con la forma del HTML de estado de barrilete: hero con
# el dron y la rienda, índice fijo, secciones numeradas, bloques con borde de tinta. Solo usan los tokens del contrato.
ESTRUCTURA = """
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--ink);font:400 15px/1.7 var(--font-mono)}
a{color:var(--accent)}
.wrap{max-width:1120px;margin:0 auto;padding:0 16px}
code{font:500 .9em var(--font-mono);background:var(--surface);padding:1px 6px;border-radius:4px}
p{max-width:78ch}
.hero{border-bottom:4px solid var(--ink)}
.hero .wrap{display:grid;grid-template-columns:1fr 300px;gap:48px;align-items:center;padding-top:56px;padding-bottom:48px}
.tags{display:flex;gap:12px;align-items:center;flex-wrap:wrap}
.stamp{font-size:13px;font-weight:500;letter-spacing:.1em;color:#fff;background:#B4122B;border-bottom:3px solid var(--ink);
  padding:4px 12px;border-radius:6px}
.chip{font-size:12px;font-weight:500;color:var(--bg);background:var(--ink);padding:3px 10px;border-radius:999px}
.hero h1{font:800 clamp(44px,8vw,88px)/.95 var(--font-display);letter-spacing:-.02em;margin:26px 0 14px;overflow-wrap:anywhere}
.lema{font:600 clamp(22px,3vw,32px)/1.2 var(--font-display);margin:0 0 18px}
.lead{color:var(--muted);max-width:58ch;margin:0 0 26px}
.leash{display:flex;align-items:center;gap:12px;font-size:14px}
.knot{width:14px;height:14px;border-radius:50%;background:var(--knot);flex:0 0 14px;
  box-shadow:0 0 0 3px var(--bg),0 0 0 5px var(--ink)}
.rope{flex:1;height:4px;background:var(--danger);border-radius:2px}
.leash .mid{color:var(--muted)}
.prompt{font-size:13px;color:var(--muted);margin-top:22px}
.prompt b{color:var(--accent)}
.art svg{width:100%;height:auto;display:block}
/* El título del índice no se ve (la barra es el índice), pero lo leen los lectores de pantalla. */
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap}
nav.toc{position:sticky;top:0;z-index:5;background:var(--card);border-bottom:2px solid var(--ink)}
nav.toc ol{display:flex;gap:4px;overflow-x:auto;list-style:none;margin:0 auto;max-width:1120px;padding:10px 16px;
  scrollbar-width:none}
nav.toc a{color:var(--ink);text-decoration:none;font-size:13px;padding:4px 10px;border-radius:6px;white-space:nowrap;
  display:block}
nav.toc a:hover,nav.toc a:focus-visible{background:#B4122B;color:#fff}
main{padding-bottom:16px}
main>section{padding:64px 0 8px}
.sec-head{display:flex;align-items:baseline;gap:14px;margin-bottom:22px}
.sec-head .num{font:700 14px var(--font-mono);color:var(--accent);white-space:nowrap}
.sec-head h2{font:800 clamp(30px,4vw,42px)/1.05 var(--font-display);letter-spacing:-.015em;margin:0}
.sec-head h2 a{color:inherit;text-decoration:none}
h3{font:800 22px/1.2 var(--font-display);margin:28px 0 12px}
h4{font:800 17px/1.2 var(--font-display);margin:18px 0 8px}
.entrada{position:relative;margin:0 0 0 8px;padding:0 0 26px 34px;overflow-wrap:anywhere}
.entrada::before{content:"";position:absolute;left:9px;top:8px;bottom:0;width:4px;background:var(--danger);border-radius:2px}
.entrada:last-of-type::before{bottom:auto;height:16px}
.entrada::after{content:"";position:absolute;left:2px;top:6px;width:16px;height:16px;border-radius:50%;background:var(--knot);
  box-shadow:0 0 0 3px var(--bg),0 0 0 5px var(--ink)}
.entrada>p{margin:0 0 12px}
.fecha{font:800 22px/1.1 var(--font-display);margin:0 0 10px!important}
.fecha time{color:var(--ink)}
.ok{color:var(--ok)}.warn{color:var(--warn)}.danger{color:var(--danger)}
.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:14px;margin:20px 0}
.kpi,.kpi.ok,.kpi.warn,.kpi.danger{background:var(--card);border:2px solid var(--ink);border-bottom-width:5px;border-radius:14px;
  padding:14px 16px;font-size:13px;color:var(--muted)}
.kpi b{display:block;font:800 40px/1 var(--font-display);margin-bottom:6px;color:var(--ink)}
.kpi.ok b{color:var(--ok)}.kpi.warn b{color:var(--warn)}.kpi.danger b{color:var(--danger)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:16px;margin:18px 0}
.card,.card.ok,.card.warn,.card.danger{background:var(--card);border:2px solid var(--ink);border-bottom-width:5px;
  border-radius:14px;padding:18px 20px;color:var(--ink)}
.card.warn{background:color-mix(in srgb,var(--knot) 16%,var(--card))}
.card.danger{border-color:var(--danger)}
.card h3,.card h4{font:800 19px/1.2 var(--font-display);margin:0 0 8px}
.card.ok h3,.card.ok h4{color:var(--ok)}.card.danger h3,.card.danger h4{color:var(--danger)}
.card p,.card ul{margin:0}.card ul{padding-left:18px}
.tbl{width:100%;margin:16px 0;border:2px solid var(--ink);border-bottom-width:5px;
  border-radius:14px;background:var(--card);border-collapse:separate;border-spacing:0;font-size:14px}
.tbl th,.tbl td{text-align:left;padding:10px 14px;border-bottom:1px solid var(--surface);vertical-align:top}
.tbl th{background:var(--surface);color:var(--ink);border-bottom:2px solid var(--ink);font-weight:500;font-size:12px;letter-spacing:.06em;text-transform:uppercase}
/* El encabezado es claro: sus esquinas se redondean para no salirse del borde de la tabla. */
.tbl tr:first-child th:first-child{border-top-left-radius:12px}.tbl tr:first-child th:last-child{border-top-right-radius:12px}
.tbl tr:last-child td{border-bottom:0}
.tbl td:first-child{font-weight:700}
.note,.note.ok,.note.warn,.note.danger{border:2px solid var(--ink);border-left:10px solid var(--knot);border-radius:12px;
  background:var(--card);padding:14px 18px;margin:18px 0;color:var(--ink)}
.note.ok{border-left-color:var(--ok)}.note.danger{border-left-color:var(--danger)}
.note p{margin:0}
.note b:first-child,.note strong:first-child{font-family:var(--font-display);font-weight:800;font-size:17px}
.bars{display:grid;gap:10px;margin:16px 0}
.bar,.bar.ok,.bar.warn,.bar.danger{display:grid;grid-template-columns:220px 1fr;gap:12px;align-items:center;font-size:14px;
  color:var(--ink)}
.bar i{display:block;height:22px;border:2px solid var(--ink);border-radius:6px;--c:var(--ink);
  background:linear-gradient(to right,var(--c) var(--v,0%),var(--surface) var(--v,0%))}
.bar.ok i{--c:var(--ok)}.bar.warn i{--c:var(--knot)}.bar.danger i{--c:var(--danger)}
.flow{counter-reset:paso;display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin:16px 0;padding:0;list-style:none}
.flow li{counter-increment:paso;display:flex;align-items:center;gap:8px;background:var(--card);border:2px solid var(--ink);
  border-radius:10px;padding:4px 12px 4px 4px;font-size:14px}
.flow li::before{content:counter(paso);width:26px;height:26px;border-radius:7px;background:var(--ink);color:var(--bg);
  font-weight:700;font-size:12px;display:grid;place-items:center}
footer{margin-top:64px;background:#E9ECF1;color:#14161A;border-top:4px solid var(--ink);font-size:13px}
footer .wrap{padding-top:28px;padding-bottom:36px;display:flex;gap:20px;align-items:center}
footer svg{flex:0 0 56px}
footer code{background:transparent;color:inherit;border:1px solid}
/* Diagrama con ramas (#361): una pregunta arriba y sus opciones abajo, unidas por líneas. */
.branch{display:flex;flex-direction:column;align-items:center;margin:22px 0}
.branch .root{position:relative;background:var(--card);border:2px solid var(--ink);border-bottom-width:5px;border-radius:14px;
  padding:10px 18px;font:800 18px/1.25 var(--font-display);text-align:center;max-width:100%}
.branch .root::after{content:"";position:absolute;left:calc(50% - 2px);top:calc(100% + 5px);width:4px;height:27px;background:var(--ink)}
/* Las opciones van en una sola fila: cada una dibuja su tramo de la línea de arriba (la primera y la última, la mitad). */
.branch .opts{display:grid;grid-auto-flow:column;grid-auto-columns:1fr;gap:16px;width:100%;margin-top:42px}
.opt,.opt.ok,.opt.warn,.opt.danger{position:relative;background:var(--card);border:2px solid var(--ink);border-bottom-width:5px;
  border-radius:14px;padding:14px 18px;color:var(--ink)}
.branch .opt::before{content:"";position:absolute;left:calc(50% - 2px);top:-19px;width:4px;height:17px;background:var(--ink)}
.branch .opt::after{content:"";position:absolute;top:-19px;left:-10px;right:-10px;height:4px;background:var(--ink)}
.branch .opt:first-child::after{left:calc(50% - 2px)}.branch .opt:last-child::after{right:calc(50% - 2px)}
.branch .opt:only-child::after{display:none}
.opt.ok{border-color:var(--ok)}.opt.warn{background:color-mix(in srgb,var(--knot) 16%,var(--card))}
.opt.danger{border-style:dashed;color:var(--muted)}
.opt h3,.opt h4{font:800 18px/1.2 var(--font-display);margin:0 0 6px}
.opt.ok h3,.opt.ok h4{color:var(--ok)}.opt.danger h3,.opt.danger h4{color:var(--danger)}
.opt p{margin:0}
/* Mapa de partes (#361): una fila por conexión, «parte → lo que hace → parte». */
.map{list-style:none;padding:0;margin:18px 0;display:grid;gap:12px}
.map li{display:flex;flex-wrap:wrap;align-items:center;gap:10px}
.map .node,.map .node.ok,.map .node.warn,.map .node.danger{background:var(--card);border:2px solid var(--ink);
  border-bottom-width:4px;border-radius:10px;padding:6px 14px;font-weight:700;color:var(--ink)}
.map .node.ok{border-color:var(--ok)}.map .node.warn{background:color-mix(in srgb,var(--knot) 16%,var(--card))}
.map .node.danger{border-color:var(--danger)}
.map .edge{display:flex;align-items:center;gap:8px;color:var(--muted);font-size:13px}
.map .edge::before{content:"";width:24px;height:3px;background:var(--ink);border-radius:2px}
.map .edge::after{content:"→";color:var(--ink);font-weight:700}
/* Portada (#365): cada tema lista los meses donde tiene entradas. */
main.temas>section{padding-top:36px}
.meses{display:flex;flex-wrap:wrap;gap:8px;list-style:none;margin:0;padding:0}
.meses a{display:block;background:var(--card);color:var(--ink);border:2px solid var(--ink);border-bottom-width:4px;
  border-radius:10px;padding:4px 12px;font-weight:700;font-size:14px;text-decoration:none}
.meses a:hover,.meses a:focus-visible{background:#B4122B;color:#fff}
@media (max-width:860px){
  .hero .wrap{grid-template-columns:1fr}
  .art{max-width:220px}
  .bar,.bar.ok,.bar.warn,.bar.danger{grid-template-columns:120px 1fr;font-size:13px}
  .tbl{display:block;overflow-x:auto}
  .branch .root::after,.branch .opt::before,.branch .opt::after{display:none}
  .branch .opts{grid-auto-flow:row;margin-top:16px}
}
"""

# El dron de barrilete atado a su rienda (hero) y su cara (pie). Colores fijos: es la marca, no un token.
DRON = """<svg viewBox="0 0 400 400" role="img" aria-label="barrilete">
<rect width="400" height="400" rx="24" fill="#E9ECF1"/>
<path d="M200 166 Q200 220 150 236 Q100 252 140 300 Q170 336 250 340" stroke="#B4122B" stroke-width="7" fill="none" stroke-linecap="round"/>
<circle cx="150" cy="236" r="11" fill="#FFB020"/><circle cx="140" cy="300" r="11" fill="#FFB020"/>
<rect x="246" y="328" width="72" height="24" rx="12" fill="#14161A"/><rect x="258" y="333" width="48" height="10" rx="4" fill="#B4122B"/><rect x="258" y="341" width="48" height="4" rx="2" fill="#5A6270"/>
<rect x="120" y="52" width="64" height="8" rx="4" fill="#14161A"/><rect x="216" y="52" width="64" height="8" rx="4" fill="#14161A"/>
<rect x="148" y="58" width="6" height="18" rx="3" fill="#14161A"/><rect x="246" y="58" width="6" height="18" rx="3" fill="#14161A"/>
<rect x="140" y="70" width="120" height="98" rx="40" fill="#FFFFFF"/><rect x="158" y="92" width="84" height="46" rx="18" fill="#14161A"/>
<circle cx="186" cy="115" r="7" fill="#8FB0FF"/><circle cx="214" cy="115" r="7" fill="#8FB0FF"/>
<rect x="190" y="160" width="20" height="10" rx="4" fill="#B4122B"/>
</svg>"""
CARA = """<svg viewBox="0 0 160 140" width="56" height="49" aria-hidden="true"><rect x="0" y="12" width="64" height="10" rx="5" fill="#14161A"/><rect x="96" y="12" width="64" height="10" rx="5" fill="#14161A"/><rect x="27" y="18" width="8" height="18" rx="3" fill="#14161A"/><rect x="125" y="18" width="8" height="18" rx="3" fill="#14161A"/><rect x="20" y="30" width="120" height="98" rx="40" fill="#FFFFFF" stroke="#14161A" stroke-width="4"/><rect x="38" y="52" width="84" height="46" rx="18" fill="#14161A"/><circle cx="66" cy="75" r="9" fill="#8FB0FF"/><circle cx="94" cy="75" r="9" fill="#8FB0FF"/><rect x="70" y="120" width="20" height="12" rx="4" fill="#B4122B"/></svg>"""


class ErrorDeUso(Exception):
    pass


class ArchivoRoto(Exception):
    """Una página que existe y no se puede leer como parte de la bitácora: no se escribe nada (sale con 65)."""

    def __init__(self, rel, motivo, salida="Arreglalo a mano o restauralo con git."):
        super().__init__(f"{rel} no se toca: {motivo}. {salida}")


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
    # Un solo diseño para todos los proyectos, el de barrilete y siempre claro (#361): un .barrilete/bitacora.css no entra.
    return [("barrilete", leer_css(TEMA_BARRILETE))]


def idioma(repo):
    try:
        with open(os.path.join(repo, ".agent-kit.json"), encoding="utf-8") as f:
            valor = json.load(f).get("language")
    except (OSError, ValueError, AttributeError):
        valor = None
    return valor if valor in TEXTOS else "en"


def pagina(repo, mes=None, desde=None, anterior=False):
    """Una página sin temas todavía: la de un mes, o la portada si no se pasa el mes. En la portada, desde es la fecha
    de la primera entrada (si se sabe) y anterior dice si hay una bitácora de antes de #365 que enlazar."""
    lang = idioma(repo)
    tx = TEXTOS[lang]
    estilos = "".join(f'<style id="theme-{nombre}">\n{css}\n</style>\n' for nombre, css in temas(repo))
    nombre = html.escape(os.path.basename(os.path.abspath(repo)) or tx["title"])
    titulo = f'{html.escape(tx["title"])} · {nombre}'
    ini, medio, fin = (html.escape(x) for x in tx["leash"])
    if mes:
        titulo, chip, indice, clase = f"{mes} · {titulo}", mes, tx["contents"], "wrap"
        lista = f'<li><a href="{HREF_PORTADA}">← {html.escape(tx["cover"])}</a></li>\n{MARCA_NAV}'
    else:
        chip, indice, clase = (f'{tx["since"]} {desde}' if desde else ""), tx["months"], "wrap temas"
        # El mes más nuevo va primero (se inserta debajo del marcador), y lo de antes de partirla por mes, al final.
        lista = MARCA_MESES + (f'\n<li><a href="{HREF_ANTERIOR}">{html.escape(tx["earlier"])}</a></li>' if anterior else "")
    chip = f'<span class="chip">{chip}</span>' if chip else ""
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{titulo}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="{html.escape(FUENTES)}">
{estilos}<style id="structure">{ESTRUCTURA}</style>
</head>
<body>
<header class="hero">
<div class="wrap">
<div>
<div class="tags"><span class="stamp">{html.escape(tx["stamp"])}</span>{chip}</div>
<h1>{nombre}</h1>
<p class="lema">{tx["motto"]}</p>
<p class="lead">{tx["sub"]}</p>
<div class="leash"><span>{ini}</span><span class="knot"></span><span class="rope"></span><span class="mid">{medio}</span><span class="rope"></span><span class="knot"></span><span>{fin}</span></div>
<div class="prompt"><b>&gt;_</b> /bitacora &lt;{"tema" if lang == "es" else "topic"}&gt;</div>
</div>
<div class="art">{DRON}</div>
</div>
</header>
<nav class="toc" aria-label="{html.escape(indice)}">
<h2 class="sr">{html.escape(indice)}</h2>
<ol>
{lista}
</ol>
</nav>
<main class="{clase}">
{MARCA_MAIN}
</main>
<footer>
<div class="wrap">{CARA}<div>{tx["footer"]}</div></div>
</footer>
</body>
</html>
"""


def secciones(texto):
    """Las secciones de la página, en orden: [(slug, tema)]."""
    return [(s, html.unescape(t)) for s, t in SECCION.findall(texto)]


def marca_fin(s):
    return f"<!-- bitacora:end {s} -->"


def validar(texto, rel, marcas):
    for marca in marcas:
        if texto.count(marca) != 1:
            raise ArchivoRoto(rel, f"no encuentro una sola vez el marcador {marca}")
    for s, _ in secciones(texto):
        if texto.count(marca_fin(s)) != 1:
            raise ArchivoRoto(rel, f"la sección {s} no tiene una sola vez su marcador de fin")


def parecidas(objetivo, lista):
    return [(s, t) for s, t in lista if s != objetivo and (
        f"-{objetivo}-" in f"-{s}-" or f"-{s}-" in f"-{objetivo}-"
        or difflib.SequenceMatcher(None, objetivo, s).ratio() >= PARECIDO)]


class Revisor(HTMLParser):
    """Revisa una entrada contra la lista permitida y que cierre todo lo que abre (si no, se comería la página)."""

    def __init__(self):
        # Sin convertir las entidades en el texto: un "&lt;" es un < escrito bien y tiene que pasar; uno crudo, no.
        # Los valores de los atributos HTMLParser los decodifica igual, y la lista permitida los revisa así.
        super().__init__(convert_charrefs=False)
        self.pila, self.mal = [], None

    def falla(self, motivo):
        self.mal = self.mal or motivo

    def handle_starttag(self, tag, attrs):
        if tag not in ETIQUETAS:
            return self.falla(f"<{tag}> no está entre las etiquetas permitidas")
        for nombre, valor in attrs:
            valor = valor or ""
            if nombre not in ATRIBUTOS | ATRIBUTOS_DE.get(tag, set()):
                self.falla(f"el atributo {nombre} de <{tag}> no está permitido")
            elif nombre == "class" and not CLASE.match(valor):
                self.falla(f"class={valor!r} no es una lista de clases")
            elif nombre == "style" and not ESTILO.match(valor):
                self.falla(f"style={valor!r}: solo se permite el ancho de una barra (--v:70%)")
            elif nombre == "href" and not HREF.match(valor.strip()):
                self.falla(f"href={valor!r}: solo links relativos, #, http(s) o mailto")
        if tag not in VACIAS:
            self.pila.append(tag)

    def handle_startendtag(self, tag, attrs):
        # El navegador ignora la / de <b/> o <a/>: los deja abiertos y se comerían el resto de la página.
        if tag not in VACIAS:
            return self.falla(f"<{tag}/> queda abierto en el navegador; cerralo con </{tag}>")
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        # Un </br> no cierra nada: el navegador lo vuelve un <br>. Cae acá como cualquier cierre que no corresponde.
        if not self.pila or self.pila[-1] != tag:
            self.falla(f"</{tag}> no cierra lo último que se abrió")
        else:
            self.pila.pop()

    def handle_data(self, data):
        if "<" in data:
            self.falla("hay un < suelto o una etiqueta sin cerrar (en el texto, escribí &lt;)")

    def handle_comment(self, data):
        self.falla("los comentarios no están permitidos")

    def handle_decl(self, decl):
        self.falla("las declaraciones no están permitidas")

    def handle_pi(self, data):
        self.falla("las instrucciones de proceso no están permitidas")

    def unknown_decl(self, data):
        self.falla("las declaraciones no están permitidas")


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
        raise ErrorDeUso(f"--entry: la entrada no puede traer {m.group(0).strip()!r} (comentarios, CDATA)")
    rev = Revisor()
    rev.feed(texto)
    # Lo que feed() no pudo procesar es una etiqueta a medias al final ("<b", '<a href="x'). Se mira antes de close():
    # en Python 3.15, close() la entrega como si estuviera completa y rawdata queda vacío (en 3.9 no).
    resto = rev.rawdata
    rev.close()
    if rev.mal or rev.pila or resto:
        motivo = rev.mal or (f"queda abierto <{rev.pila[-1]}>" if rev.pila else "termina en una etiqueta sin cerrar")
        raise ErrorDeUso(f"--entry: {motivo}. Componentes permitidos: .claude/skills/bitacora/SKILL.md")
    return texto


def insertar(texto, marca, bloque, debajo=False):
    """Pone el bloque en las líneas de arriba de la marca (o en las de abajo, con debajo): lo que ya estaba no cambia.
    Usa el fin de línea del archivo."""
    if "\r\n" in texto:
        bloque = bloque.replace("\n", "\r\n")
    i = texto.index(marca)
    if debajo:
        i = texto.find("\n", i) + 1 or len(texto)
    return texto[:i] + bloque + texto[i:]


def escribir(ruta, texto):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    # mkstemp crea con 0600: el archivo conserva su modo, o el que daría el umask si es nuevo.
    try:
        modo = os.stat(ruta).st_mode & 0o777
    except FileNotFoundError:
        umask = os.umask(0)
        os.umask(umask)
        modo = 0o666 & ~umask
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(ruta), prefix=".bitacora-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(texto)
        os.chmod(tmp, modo)
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


def leer(repo, rel):
    try:
        with open(os.path.join(repo, rel), encoding="utf-8", newline="") as f:
            return f.read()
    except FileNotFoundError:
        return None


def ruta_mes(mes):
    return os.path.join(DIR_MESES, f"{mes}.html")


def href_mes(mes):
    return f"bitacora/{mes}.html"


def meses_en_disco(repo):
    """Los meses que ya tienen página, del más viejo al más nuevo."""
    try:
        nombres = os.listdir(os.path.join(repo, DIR_MESES))
    except FileNotFoundError:
        return []
    return sorted(m.group(1) for m in map(PAGINA_MES.match, nombres) if m)


def con_tema(portada, s, tema, num):
    """La portada con un tema más, al final: su sección junta los enlaces a los meses donde tiene entradas."""
    tema = html.escape(tema)
    return insertar(portada, MARCA_MAIN, f'<section id="{s}" data-topic="{tema}">\n'
                                         f'<div class="sec-head"><span class="num">&gt;_ {num:02d}</span>'
                                         f'<h2><a href="#{s}">{tema}</a></h2></div>\n'
                                         f'<ul class="meses">\n{marca_fin(s)}\n</ul>\n</section>\n')


def con_enlace(portada, s, href, texto):
    return insertar(portada, marca_fin(s), f'<li><a href="{href}#{s}">{html.escape(texto)}</a></li>\n')


def con_mes(portada, mes):
    return insertar(portada, MARCA_MESES, f'<li><a href="{href_mes(mes)}">{mes}</a></li>\n', debajo=True)


def leer_bitacora(repo, desde=None):
    """La portada, como texto, y cómo está en el disco: (portada, en_disco, de_antes).

    Si docs/bitacora.html ya es la portada, en_disco es ese mismo texto. Si no, la portada se arma en memoria con lo
    que hay (en_disco es None: add la escribe entera): los temas de la bitácora de antes de #365 y los de las páginas
    de los meses, en ese orden. de_antes dice que la bitácora de antes todavía está en docs/bitacora.html, y add la
    tiene que mover a docs/bitacora-anterior.html antes de escribir la portada."""
    crudo = leer(repo, RUTA)
    # Una portada que perdió el marcador de meses (se editó a mano) no es una bitácora de antes: su aviso nombra ese
    # marcador. Solo la portada escribe <main class="wrap temas">.
    if crudo is not None and (MARCA_MESES in crudo or 'class="wrap temas"' in crudo):
        validar(crudo, RUTA, MARCAS_PORTADA)
        return crudo, crudo, False
    de_antes = crudo is not None
    anterior = crudo if de_antes else leer(repo, RUTA_ANTERIOR)
    if anterior is not None:
        validar(anterior, RUTA if de_antes else RUTA_ANTERIOR, MARCAS_PAGINA)
    meses = meses_en_disco(repo)
    paginas = [(None, anterior)] + [(mes, leer(repo, ruta_mes(mes))) for mes in meses]
    paginas = [(mes, texto) for mes, texto in paginas if texto is not None]
    # La fecha de inicio solo se sabe en una bitácora que nace ahora.
    portada = pagina(repo, desde=None if paginas else desde, anterior=anterior is not None)
    tx = TEXTOS[idioma(repo)]
    vistos = set()
    for mes, texto in paginas:
        if mes:
            validar(texto, ruta_mes(mes), MARCAS_PAGINA)
            portada = con_mes(portada, mes)
        for s, tema in secciones(texto):
            if s not in vistos:
                vistos.add(s)
                portada = con_tema(portada, s, tema, len(vistos))
            portada = con_enlace(portada, s, href_mes(mes) if mes else HREF_ANTERIOR, mes or tx["earlier"])
    return portada, None, de_antes


def imprimir_parecidas(lista):
    for s, t in lista:
        print(f"similar {s}\t{t}")


def slug_de(tema):
    s = slug(tema)
    if not s:
        raise ErrorDeUso("--topic: el tema necesita al menos una letra o un número")
    if RESERVADOS.match(s):
        raise ErrorDeUso(f"--topic: {s} es el id de un bloque de la página; usá otro nombre")
    return s


def cmd_find(repo, a):
    s = slug_de(a.topic)
    lista = secciones(leer_bitacora(repo)[0])
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
    s = slug_de(a.topic)
    entrada = leer_entrada(a.entry)
    hoy = datetime.date.today()
    dia = a.date or hoy
    if dia > hoy:
        # Su página cerraría todos los meses hasta que llegue esa fecha.
        raise ErrorDeUso(f"--date: {dia.isoformat()} es una fecha futura")
    mes = dia.isoformat()[:7]
    portada, en_disco, de_antes = leer_bitacora(repo, dia.isoformat())
    if de_antes and os.path.lexists(os.path.join(repo, RUTA_ANTERIOR)):
        raise ArchivoRoto(RUTA_ANTERIOR, f"ya existe, y {RUTA} es una bitácora de antes de partirla por mes que "
                          "tendría que ir ahí", "Mové o borrá uno de los dos a mano.")
    ultimo = (meses_en_disco(repo) or [mes])[-1]
    if mes < ultimo:
        raise ErrorDeUso(f"{'--date: ' if a.date else ''}la entrada es de {mes} y ya hay una página de {ultimo}: "
                         "las páginas de los meses pasados no se tocan")
    lista = dict(secciones(portada))
    rel = ruta_mes(mes)
    texto = leer(repo, rel)
    if texto is None:
        texto = pagina(repo, mes=mes)
    else:
        validar(texto, rel, MARCAS_PAGINA)
    en_el_mes = secciones(texto)
    if a.into:
        if a.into not in lista:
            raise ErrorDeUso(f"--into: no hay una sección {a.into}")
        destino, nueva = a.into, False
    elif s in lista:
        # Un add --new que se cortó después de escribir la portada dejó el tema ahí, enlazado solo a este mes, y la
        # página del mes sin él: repetirlo igual lo termina.
        enlaces = re.findall(r'href="([^"#]+)#%s"' % re.escape(s), portada)
        reintento = a.new and enlaces == [href_mes(mes)] and s not in dict(en_el_mes)
        if a.new and not reintento:
            raise ErrorDeUso(f"--new: ya hay una sección {s}; sin --new la entrada se suma a esa")
        destino, nueva = s, reintento
    else:
        cerca = parecidas(s, list(lista.items()))
        if cerca and not a.new:
            imprimir_parecidas(cerca)
            print("bitacora_add.py: hay secciones con un nombre parecido; repetí con --into <slug> o --new",
                  file=sys.stderr)
            return 3
        destino, nueva = s, True
    # Un tema que ya existe conserva su nombre en la página de cada mes, aunque ahora se lo haya escrito distinto.
    nombre = lista.get(destino) or a.topic.strip()

    # La portada: lo que le falte de este tema, este mes y el enlace entre los dos. Lo que ya tiene no se repite, así
    # un add que se cortó después de escribirla se puede reintentar.
    if destino not in lista:
        portada = con_tema(portada, destino, nombre, len(lista) + 1)
    if f'href="{href_mes(mes)}"' not in portada:
        portada = con_mes(portada, mes)
    if f'href="{href_mes(mes)}#{destino}"' not in portada:
        portada = con_enlace(portada, destino, href_mes(mes), mes)

    # La página del mes: la sección del tema, si este mes todavía no la tiene, y la entrada al final.
    if destino not in dict(en_el_mes):
        tema = html.escape(nombre)
        num = f"{len(en_el_mes) + 1:02d}"   # el número de la sección, como en el HTML de estado: >_ 01
        texto = insertar(texto, MARCA_NAV, f'<li><a href="#{destino}">{num} {tema}</a></li>\n')
        texto = insertar(texto, MARCA_MAIN, f'<section id="{destino}" data-topic="{tema}">\n'
                                            f'<div class="sec-head"><span class="num">&gt;_ {num}</span>'
                                            f'<h2><a href="#{destino}">{tema}</a></h2></div>\n'
                                            f'{marca_fin(destino)}\n</section>\n')
    texto = insertar(texto, marca_fin(destino), f'<article class="entrada">\n'
                                                f'<p class="fecha"><time datetime="{dia.isoformat()}">{dia.isoformat()}</time></p>\n'
                                                f'{entrada}\n</article>\n')

    # En este orden: si se corta en el medio, lo ya escrito no se pierde y la entrada todavía no está en ningún lado.
    if de_antes:
        os.rename(os.path.join(repo, RUTA), os.path.join(repo, RUTA_ANTERIOR))
    if portada != en_disco:
        escribir(os.path.join(repo, RUTA), portada)
    ruta = os.path.join(repo, rel)
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
        print(f"bitacora_add.py: {err}", file=sys.stderr)
        sys.exit(65)
    except (OSError, UnicodeDecodeError) as err:
        print(f"bitacora_add.py: {err}", file=sys.stderr)
        sys.exit(1)
