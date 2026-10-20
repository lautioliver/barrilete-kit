#!/usr/bin/env python3
"""Flow line: which step of the flow the current branch is in, in one line for any terminal.

    plan ● ─ ▸implement ─ review ─ ● merge   #176 · no PR yet

The two ● are the knots that stay in human hands (approving the plan and merging). The step comes from
what already exists, nothing is written by hand:
  - a branch `<type>/<n>-…` (also `claude/<n>-…`) and no open PR → implement
  - an open PR for the branch → review; approved → merge (waiting for your merge)
  - the PR merged → retro
  - the issue with `status:blocked` → blocked, whatever the step
On a trunk branch or one without an issue number it shows the flow with no step marked. `/plan-feature`
leaves no trace in git, so the plan knot is never the current step.

It does not depend on the agent: the harness or the ADE only has to show a line of text.
  flow.py                      one line with ANSI colors (a script, `watch`, any terminal)
  flow.py --statusline         Claude Code status line (reads its JSON from stdin)
  flow.py --format zsh|bash    for the shell prompt (escapes the colors so the cursor does not drift)
  flow.py --format tmux        for tmux's status-right
  flow.py --format json        for an ADE or an extension that draws it its own way
  flow.py --watch [seconds]    redraws the line in a pane (default 5 s)
  flow.py --busy on|off        Claude Code hooks (UserPromptSubmit / Stop): while the agent works, the status
                               line (with refreshInterval) shows a spinner and the elapsed time
NO_COLOR=1 or --format plain turns the colors off.

What it asks GitHub (`gh`) is cached per branch in the git dir: after 30 s the line still shows what it
had and a process in the background refreshes it, so the prompt does not wait for the network. Only the
first prompt on a branch it has never seen waits for `gh` (up to 4 s without network). A call that fails
keeps what the cache had for that field; without `gh` or without network it falls back to what git knows.

With `.github/brand/` (the template repo) the line starts with Barrilete's face for the step, the states
of `.github/brand/states/`: (● ●) working, (• • •) planning, (✕ ✕) blocked and (^ ^) PR ready; `--watch`
draws it big. `init-template.sh` deletes that folder, so a project shows the line without it.
  flow.py --face working|planning|blocked|ready   prints the big face (the init uses it to say goodbye)
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

CACHE_TTL = 30
CACHE_NOMBRE = "agent-kit-flow.json"
CACHE_RAMAS = 20  # branches kept in the cache; the oldest one goes first
RAMA_RE = re.compile(r"^[a-z]+/(\d+)-")
PASOS = ["plan", "implement", "review", "merge"]
NUDOS = {"plan", "merge"}
TEXTO = {"plan": "plan ●", "merge": "● merge"}
DETALLE = {
    "implement": "no PR yet",
    "draft": "PR #{pr} draft",
    "closed": "PR #{pr} closed, no merge",
    "offline": "no data from GitHub",
    "review": "PR #{pr} in review",
    "merge": "PR #{pr} waiting for your merge",
    "retro": "PR #{pr} merged · retro",
    "blocked": "blocked",
}

# Shades of the brand palette that read on a dark and on a light terminal (contrast ≥ 3:1 on both):
# the brand's amber and blue do not read on white, nor its grey on black.
AMBAR, ROJO, AZUL, GRIS = "#C98500", "#E0525E", "#5B7FFF", "#7A8290"
FORMATOS = ("ansi", "plain", "zsh", "bash", "tmux", "json")

# Barrilete's faces (.github/brand/states/): eyes and mouth color of each state. The small one goes in the
# line; the big one, in --watch and at the end of the init.
CARAS = {
    "working": ("  ●   ●  ", AZUL, ROJO),
    "planning": ("  • • •  ", AZUL, ROJO),
    "blocked": ("  ✕   ✕  ", ROJO, ROJO),
    "ready": ("  ^   ^  ", AZUL, AMBAR),
}
# While the agent works (hooks --busy on/off, docs/guides/flow-line.md): a spinner, the time and eyes that move.
OCUPADO_DIR = os.path.join(tempfile.gettempdir(), "agent-kit-flow")
OCUPADO_MAX = 6 * 3600  # a mark older than this is a turn whose Stop never came (a killed session)
GIRO = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
MIRADA = {"working": ["● ●", "●● ", "● ●", " ●●"], "planning": ["• · ·", "· • ·", "· · •", "· • ·"]}
CARA_DEL_PASO = {None: "planning", "implement": "working", "review": "working", "merge": "ready",
                 "retro": "working", "blocked": "blocked"}


def literal(texto, formato):
    """Escapes what tmux (#) and zsh (%) would read as their own codes: `#176` is text, not a format."""
    return {"tmux": texto.replace("#", "##"), "zsh": texto.replace("%", "%%")}.get(formato, texto)


def pintar(texto, hexa, formato, negrita=False):
    texto = literal(texto, formato)
    if formato == "plain":
        return texto
    if formato == "tmux":
        return f"#[fg={hexa}{',bold' if negrita else ''}]{texto}#[default]"
    r, g, b = (int(hexa[i:i + 2], 16) for i in (1, 3, 5))
    abre, cierra = f"\033[{'1;' if negrita else ''}38;2;{r};{g};{b}m", "\033[0m"
    if formato == "zsh":
        abre, cierra = f"%{{{abre}%}}", f"%{{{cierra}%}}"
    elif formato == "bash":
        abre, cierra = f"\001{abre}\002", f"\001{cierra}\002"
    return abre + texto + cierra


def cara_chica(cara, formato, cuadro=None):
    """`cuadro` (a number that grows each second) moves the eyes while the agent works."""
    ojos, color_ojos, boca = CARAS[cara]
    ojos = " ".join(ojos.split())
    if cuadro is not None and cara in MIRADA:
        ojos = MIRADA[cara][cuadro % len(MIRADA[cara])]
    color = AMBAR if boca == AMBAR else GRIS  # PR ready: the face lights up in amber, like its mouth
    return pintar("(", color, formato) + pintar(ojos, color_ojos, formato) + pintar(")", color, formato)


def ruta_ocupado(sesion):
    return os.path.join(OCUPADO_DIR, re.sub(r"[^\w-]", "_", sesion))


def marcar_ocupado(sesion, prender):
    """Hook side: UserPromptSubmit turns the mark on (with the time it started), Stop turns it off."""
    if not sesion:
        return
    try:
        if prender:
            os.makedirs(OCUPADO_DIR, exist_ok=True)
            guardar(ruta_ocupado(sesion), time.time())
        else:
            os.remove(ruta_ocupado(sesion))
    except OSError:
        pass


def ocupado_desde(sesion):
    """When the current turn started, or None if the agent is not working."""
    desde = leer(ruta_ocupado(sesion)) if sesion else None
    if not isinstance(desde, (int, float)) or time.time() - desde > OCUPADO_MAX:
        return None
    return desde


def duracion(segundos):
    s = int(segundos)
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m {s % 60:02d}s"
    return f"{s // 3600}h {s % 3600 // 60:02d}m"


def cara_grande(cara, formato):
    """Six lines: propellers, body, visor with the eyes, and the mouth below."""
    ojos, color_ojos, boca = CARAS[cara]
    g = lambda t: pintar(t, GRIS, formato)  # noqa: E731
    return [
        g("━━━┳━━     ━━┳━━━"),
        g(" ╭─┸─────────┸─╮"),
        g(" │ ┌─────────┐ │"),
        g(" │ │") + pintar(ojos, color_ojos, formato, negrita=True) + g("│ │"),
        g(" │ └─────────┘ │"),
        g(" ╰─────") + pintar("▆▆▆", boca, formato) + g("─────╯"),
    ]


def correr(args, cwd, timeout=4):
    try:
        r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def gh(args, cwd, timeout=4):
    """(answered, stdout, stderr): answered is False if gh did not run or did not finish (no gh, timeout)."""
    try:
        r = subprocess.run(["gh", *args], cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return False, "", ""
    return r.returncode == 0, r.stdout.strip(), r.stderr


def consultar_github(cwd, rama, issue, previo=None):
    """PR of the branch and labels of the issue. A call that fails keeps the field `previo` had: a timeout of
    `gh pr view` is not "no PR", and one of `gh issue view` does not hide a status:blocked."""
    previo = previo or {}
    with ThreadPoolExecutor(2) as ex:  # in parallel: the first time on a branch the prompt waits for gh
        pr = ex.submit(gh, ["pr", "view", rama, "--json", "number,state,isDraft,reviewDecision,latestReviews"], cwd)
        labels = ex.submit(gh, ["issue", "view", issue, "--json", "labels", "--jq", "[.labels[].name]"], cwd)
        (pr_ok, pr_out, pr_err), (labels_ok, labels_out, _) = pr.result(), labels.result()
    sin_pr = not pr_ok and "no pull requests found" in pr_err  # gh's answer when the branch has no PR
    return {
        "t": time.time(),
        "ok": pr_ok or sin_pr or labels_ok or bool(previo.get("ok")),
        "pr": json.loads(pr_out) if pr_ok else None if sin_pr else previo.get("pr"),
        "labels": json.loads(labels_out) if labels_ok else previo.get("labels", []),
    }


def guardar(ruta, datos):
    try:
        tmp = f"{ruta}.{os.getpid()}"
        with open(tmp, "w") as f:
            json.dump(datos, f)
        os.replace(tmp, ruta)  # atomic: a prompt never reads a half-written file
    except OSError:
        pass


def leer(ruta):
    try:
        with open(ruta) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def aprobado(pr):
    """Approved: by the required review or, if the repo requires none, by an approval and no change requests."""
    if pr.get("reviewDecision"):
        return pr["reviewDecision"] == "APPROVED"
    estados = {r.get("state") for r in pr.get("latestReviews") or []}
    return "APPROVED" in estados and "CHANGES_REQUESTED" not in estados


def guardar_rama(ruta, rama, datos, si_sigue=None):
    """Writes the branch's data in the cache, re-read just before so another branch's write is not lost.
    With `si_sigue`, only if the branch's entry still has that time (a refresh that landed meanwhile wins)."""
    ramas = leer(ruta).get("ramas", {})
    if si_sigue is not None and ramas.get(rama, {}).get("t") != si_sigue:
        return
    ramas[rama] = datos
    viejas = sorted(ramas, key=lambda r: ramas[r].get("t", 0))[:-CACHE_RAMAS]
    guardar(ruta, {"ramas": {r: d for r, d in ramas.items() if r not in viejas}})


def datos_github(cwd, ruta, rama, issue):
    """Cached data; stale → shown anyway and refreshed in the background; missing → asked now."""
    cache = leer(ruta).get("ramas", {}).get(rama)
    if cache:
        if time.time() - cache.get("t", 0) >= CACHE_TTL:
            visto = cache["t"]
            cache = dict(cache, t=time.time())  # so another prompt does not start another query while this one runs
            guardar_rama(ruta, rama, cache, si_sigue=visto)
            try:
                subprocess.Popen([sys.executable, os.path.abspath(__file__), "--refresh", ruta, rama, issue],
                                 cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
            except OSError:
                pass
        return cache
    datos = consultar_github(cwd, rama, issue)
    guardar_rama(ruta, rama, datos)
    return datos


def paso_actual(datos):
    if "status:blocked" in datos["labels"]:
        return "blocked"
    pr = datos["pr"]
    if not pr or pr["state"] == "CLOSED" or pr.get("isDraft"):  # closed without merge or draft: still working
        return "implement"
    if pr["state"] == "MERGED":
        return "retro"
    return "merge" if aprobado(pr) else "review"


def dibujar(paso, formato):
    partes = []
    for p in PASOS:
        texto = TEXTO.get(p, p)
        if p == paso:
            partes.append(pintar("▸" + texto, AMBAR if p in NUDOS else AZUL, formato, negrita=True))
        else:
            partes.append(pintar(texto, AMBAR if p in NUDOS else GRIS, formato))
    return pintar(" ─ ", GRIS, formato).join(partes)


def estado(cwd):
    """What the line shows, without format: None outside a git repo."""
    raiz = correr(["git", "rev-parse", "--show-toplevel"], cwd)
    if not raiz:
        return None
    rama = correr(["git", "branch", "--show-current"], cwd) or ""
    e = {"brand": os.path.isdir(os.path.join(raiz, ".github", "brand")), "branch": rama or None,
         "issue": None, "pr": None, "step": None, "note": None, "face": CARA_DEL_PASO[None], "steps": PASOS}
    m = RAMA_RE.match(rama)
    if not m:
        return e
    git_dir = correr(["git", "rev-parse", "--absolute-git-dir"], cwd) or os.path.join(raiz, ".git")
    datos = datos_github(cwd, os.path.join(git_dir, CACHE_NOMBRE), rama, m.group(1))
    pr, paso = datos["pr"] or {}, paso_actual(datos)
    nota = None
    if paso == "implement":
        nota = ("offline" if not datos.get("ok", True) else "draft" if pr.get("isDraft")
                else "closed" if pr.get("state") == "CLOSED" else None)
    e.update(issue=int(m.group(1)), pr=pr.get("number"), step=paso, note=nota, face=CARA_DEL_PASO[paso])
    return e


def linea(e, formato):
    desde = e.get("busy_since")
    ahora = time.time()
    marca = cara_chica(e["face"], formato, int(ahora) if desde else None) + " " if e["brand"] else ""
    trabajando = ""
    if desde:
        trabajando = "   " + pintar(f"{GIRO[int(ahora) % len(GIRO)]} working {duracion(ahora - desde)}", AZUL, formato)
    return linea_base(e, formato, marca) + trabajando


def linea_base(e, formato, marca):
    if not e["issue"]:
        return f"{marca}{dibujar(None, formato)}   {pintar(e['branch'] or 'detached', GRIS, formato)}"
    paso = e["step"]
    if paso == "blocked":
        flujo = pintar("✖ blocked", ROJO, formato, negrita=True) + "  " + dibujar(None, formato)
    else:
        flujo = dibujar(paso, formato)
    detalle = literal(DETALLE[e.get("note") or paso].format(pr=e["pr"]), formato)
    return f"{marca}{flujo}   {pintar('#' + str(e['issue']), AZUL, formato)} · {detalle}"


def vista_grande(e, formato):
    """--watch with the brand: the big face, what it means beside it, and the line below."""
    cara = cara_grande(e["face"], formato)
    nombre = {"working": "working", "planning": "planning", "blocked": "blocked", "ready": "PR ready"}[e["face"]]
    cara[3] += "   " + pintar(nombre, ROJO if e["face"] == "blocked" else AMBAR if e["face"] == "ready" else AZUL,
                              formato, negrita=True)
    cara[4] += "   " + pintar(e["branch"] or "detached", GRIS, formato)
    return "\n".join(cara + ["", linea(dict(e, brand=False), formato)])


def salida(cwd, formato, grande=False, sesion=None):
    e = estado(cwd)
    if e is None:
        return "" if formato != "json" else "null"
    e["busy_since"] = ocupado_desde(sesion)
    if formato == "json":
        return json.dumps(dict(e, text=linea(e, "plain")), ensure_ascii=False)
    if grande and e["brand"]:
        return vista_grande(e, formato)
    return linea(e, formato)


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    if argv[:1] == ["--refresh"]:  # background process started by datos_github
        ruta, rama, issue = argv[1:4]
        previo = leer(ruta).get("ramas", {}).get(rama)  # what a failed call keeps: no false "no PR yet"
        guardar_rama(ruta, rama, consultar_github(os.getcwd(), rama, issue, previo))
        return 0
    p = argparse.ArgumentParser(description="Shows which step of the flow the current branch is in.")
    p.add_argument("--format", choices=FORMATOS, default=None)
    p.add_argument("--statusline", action="store_true", help="Claude Code: reads the status line JSON from stdin")
    p.add_argument("--watch", nargs="?", type=float, const=5.0, metavar="SECONDS")
    p.add_argument("--dir", default=None, help="directory of the repo (default: the current one)")
    p.add_argument("--face", choices=sorted(CARAS), help="prints Barrilete's big face for that state and exits")
    p.add_argument("--busy", choices=("on", "off"), help="hook: marks that the agent started or stopped working "
                   "(reads the hook JSON from stdin; prints nothing)")
    a = p.parse_args(argv)
    formato = a.format or ("plain" if os.environ.get("NO_COLOR") else "ansi")
    if a.face:
        print("\n".join(cara_grande(a.face, "plain" if formato == "json" else formato)))
        return 0
    cwd = a.dir or os.getcwd()
    entrada = {}
    if a.statusline or a.busy:
        try:
            entrada = json.load(sys.stdin)
        except ValueError:
            pass
        if not isinstance(entrada, dict):
            entrada = {}
        cwd = (entrada.get("workspace") or {}).get("current_dir") or entrada.get("cwd") or cwd
    if a.busy:
        marcar_ocupado(entrada.get("session_id"), a.busy == "on")
        return 0
    if a.watch is None:
        print(salida(cwd, formato, sesion=entrada.get("session_id")))
        return 0
    try:
        while True:
            sys.stdout.write("\033[H\033[2J" + salida(cwd, formato, grande=True) + "\n")
            sys.stdout.flush()
            time.sleep(max(a.watch, 1))
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
