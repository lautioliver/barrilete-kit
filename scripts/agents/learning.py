#!/usr/bin/env python3
"""Learning events of the project (ADR-007): the v1 event, its validator and the store that keeps it.

The event (ADR-007 D3, documented in docs/agents/learning-event.md) is one JSON line with only the fields of the table in
CAMPOS: no free text, nothing that is not in the table. `v`, `ts`, `project`, `kind`, `model` and `harness` are required;
an emitter that cannot know the model or the harness writes `unknown`, it never guesses. The model and the provider come
from BK_MODEL and BK_PROVIDER or, without them, from BARRILETE_MODEL and BARRILETE_PROVIDER (what `bk` exports); the harness,
from BK_HARNESS or, if it is unset or empty, `claude-code` with CLAUDECODE=1.

Where it goes (D2) is said by .barrilete/learning.json of the main checkout (also from a worktree), {"store": "local"} or
{"store": "branch"}; without the file, local:
  local   .barrilete/learning/events.jsonl of the main checkout (also from a worktree); the folder ignores itself.
  branch  the data branch agents/learning: each write is one plumbing commit on the local branch, without touching the
          working branch, the index or the tree. `push` uploads it (joining the lines if the remote moved); emit never goes
          to the network.

rules_ref (D6): "<12 of the rules.lock SHA>.<12 of the sha256 of the generated sections the role reads>" (the rules block of
AGENTS.md and the one of .claude/agents/<role>.md). It only goes in the events of a `bk` agent (BK_TASK_DIR), and
never without rules.lock.

Usage:
  learning.py validate <events.jsonl>    # exits with 3 and says the line of each broken event; v0 lines of #323 are legacy
  learning.py emit <kind> [field=value…] # adds model, harness, provider, project and the task's fields; 3 if invalid,
                                         # 64 with a field that is not the event's own: only ts, pr,
                                         # area, role, class, rule_id, outcome, evidence_ref (role/pr not in a bk task)
  learning.py push                       # store branch: uploads agents/learning to origin
  learning.py rules-ref [role]           # prints the rules_ref of that role (1 without rules.lock)
Exit status: 0 ok; 1 nothing to print (rules-ref without lock) or a git failure in push; 3 an invalid event or
learning.json; 64 invalid usage.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time

RAMA = "agents/learning"
REF = "refs/heads/" + RAMA
REMOTO = "origin"
ARCHIVO = "events.jsonl"
BEGIN, END = "<!-- rules:begin", "<!-- rules:end -->"

SLUG = r"[a-z0-9]+(?:-[a-z0-9]+)*"
TOKEN = r"[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,99}"   # a model id (claude-sonnet-5-5, gpt-5.1, openai/gpt-4o): no spaces
TERMINALES = ("completed", "failed", "incomplete", "cancelled")   # ADR-005 D3
OUTCOMES = {"check_run": ("pass", "fail", "skipped"), "task_end": TERMINALES, "deviation": (), "finding": ()}


def _entero(x):
    return isinstance(x, int) and not isinstance(x, bool)


def _patron(regex):
    r = re.compile(regex)
    return lambda x: isinstance(x, str) and r.fullmatch(x) is not None


# evidence_ref: `push` publishes the store, and that is where a webhook or a token travels. So a URL is valid only if it is
# one of these, and anything else (another host, http, a port, user, query, `%`, `=`) is not. Each piece is a fixed class with
# no nested quantifier, so a hostile input is rejected in linear time.
_OWNER = r"[A-Za-z0-9][A-Za-z0-9-]{0,38}"
_REPO = r"(?!\.+/)[A-Za-z0-9._-]{1,100}"
_SHA = r"[0-9a-f]{7,40}"
_SEG = r"(?!\.{1,2}(?:/|$))[A-Za-z0-9._~-]{1,100}"   # the class of a local path, without `/`, `.` or `..`
_URL_GITHUB = re.compile(
    rf"https://github\.com/{_OWNER}/{_REPO}/(?:"
    rf"(?:pull|issues)/[0-9]{{1,10}}(?:#(?:issuecomment-|discussion_r)[0-9]{{1,20}})?"
    rf"|blob/{_SHA}/(?=[^#]{{1,300}}(?:#|\Z)){_SEG}(?:/{_SEG})*(?:#L[0-9]{{1,7}}(?:-L[0-9]{{1,7}})?)?"
    rf"|commit/{_SHA})")
_RUTA_LOCAL = re.compile(r"[A-Za-z0-9._~/-]{1,300}")


def evidencia(x):
    """Whether a value is a valid evidence_ref: a local path or a URL of the list of ADR-007 D3."""
    if "://" in x:
        return _URL_GITHUB.fullmatch(x) is not None
    return _RUTA_LOCAL.fullmatch(x) is not None


# The table of ADR-007 D3. Each value is checked against its form: a field of the table with free text inside is rejected.
CAMPOS = {
    "v": lambda x: _entero(x) and x == 1,
    "ts": _patron(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z"),
    "project": _patron(r"[A-Za-z0-9._-]{1,100}"),
    "task_id": _patron(SLUG),
    "pr": lambda x: _entero(x) and x > 0,
    "provider": _patron(SLUG),
    "model": _patron(TOKEN),
    "harness": _patron(SLUG),
    "area": _patron(SLUG),
    "role": _patron(SLUG),
    "kind": lambda x: isinstance(x, str) and x in OUTCOMES,
    "class": _patron(SLUG),
    "rule_id": _patron(SLUG),
    "outcome": _patron(SLUG),   # which values depends on kind: see problemas()
    # A local path, or one of the GitHub URLs of the list in ADR-007 D3 (amended in #348): see evidencia().
    "evidence_ref": lambda x: isinstance(x, str) and evidencia(x),
    "rules_ref": _patron(r"[0-9a-f]{12}\.[0-9a-f]{12}"),
}
OBLIGATORIOS = ("v", "ts", "project", "kind", "model", "harness")
# What `emit field=value` can set: the event's own fields. The rest says who emits it (contexto()) and is never set by hand.
PROPIOS = ("ts", "pr", "area", "role", "class", "rule_id", "outcome", "evidence_ref")


class LearningError(Exception):
    """An event or a store that cannot be written. The message never carries the event's values."""


def problemas(ev):
    """The problems of an event (empty list if it is valid). They name the field, never its value."""
    if not isinstance(ev, dict):
        return ["it is not a JSON object"]
    p = [f"field {k!r} is not in the event table (ADR-007 D3)" for k in ev if k not in CAMPOS]
    p += [f"missing required field {k!r}" for k in OBLIGATORIOS if k not in ev]
    p += [f"field {k!r} does not have the form of the table" for k in ev if k in CAMPOS and not CAMPOS[k](ev[k])]
    kind = ev.get("kind")
    if isinstance(kind, str) and kind in OUTCOMES:
        validos = OUTCOMES[kind]
        if not validos and "outcome" in ev:
            p.append(f"a {kind} carries no outcome")
        elif validos and ev.get("outcome") not in validos:
            p.append(f"the outcome of a {kind} is one of {', '.join(validos)}")
    return p


# The check_run of verify.py before v1 (#323, schema v0). Stores written then keep those lines: `validate` counts them as
# legacy instead of broken, but only with exactly that shape (no other field, no free text).
V0 = {
    "v": lambda x: _entero(x) and x == 0,
    "ts": CAMPOS["ts"],
    "kind": lambda x: x == "check_run",
    "check": _patron(SLUG),
    "rule_id": _patron(SLUG),
    "outcome": lambda x: x in OUTCOMES["check_run"],
    "branch": _patron(r"(?!.*\.\.)[\w./@+#-]{1,200}"),   # the characters of a branch name (v0 wrote any): letters, ñ too
    "task_id": _patron(SLUG),
    "harness": _patron(SLUG),
}
V0_OBLIGATORIOS = ("v", "ts", "kind", "check", "rule_id", "outcome")


def es_v0(ev):
    """Whether it is a legacy v0 check_run line of #323."""
    return (isinstance(ev, dict) and all(k in V0 and V0[k](x) for k, x in ev.items())
            and all(k in ev for k in V0_OBLIGATORIOS))


def validar_archivo(ruta):
    """(number of valid events, ["line n: problem", …], number of legacy v0 lines)."""
    ok, errores, heredadas = 0, [], 0
    with open(ruta, encoding="utf-8") as fh:
        for n, linea in enumerate(fh, 1):
            if not linea.strip():
                continue
            try:
                ev = json.loads(linea)
            except ValueError:
                errores.append(f"line {n}: it is not JSON")
                continue
            if es_v0(ev):
                heredadas += 1
                continue
            pr = problemas(ev)
            errores += [f"line {n}: {x}" for x in pr]
            ok += not pr
    return ok, errores, heredadas


# --- git ---

def _git(*args, cwd=None, entrada=None, env=None):
    return subprocess.run(["git", *args], cwd=cwd, input=entrada, capture_output=True, text=True, env=env)


def _salida(*args, cwd=None, entrada=None, env=None):
    r = _git(*args, cwd=cwd, entrada=entrada, env=env)
    if r.returncode != 0:
        raise LearningError(f"git {args[0]} failed: {r.stderr.strip().splitlines()[-1:] or ['?']}")
    return r.stdout.strip()


def raiz(cwd=None):
    """The toplevel of the checkout where it runs (a worktree, if it is one)."""
    r = _git("rev-parse", "--show-toplevel", cwd=cwd)
    if r.returncode != 0 or not r.stdout.strip():
        raise LearningError("not inside a git repository")
    return r.stdout.strip()


def raiz_principal(cwd=None):
    """The main checkout: from a worktree the events go there, because the worktree is deleted when the agent finishes."""
    r = _git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=cwd)
    comun = r.stdout.strip()
    if r.returncode == 0 and os.path.basename(comun) == ".git":
        return os.path.dirname(comun)
    return raiz(cwd)


def dir_comun(cwd=None):
    return _salida("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=cwd)


def proyecto(cwd=None):
    """The repo name: the one of origin's URL, or else the folder of the main checkout."""
    r = _git("remote", "get-url", REMOTO, cwd=cwd)
    url = r.stdout.strip().rstrip("/") if r.returncode == 0 else ""
    nombre = re.split(r"[/:]", url)[-1] if url else os.path.basename(raiz_principal(cwd))
    nombre = nombre[:-4] if nombre.endswith(".git") else nombre
    # A folder like "mi proyecto" or "año" would make every event invalid: what is outside the table's form becomes "-"
    return re.sub(r"[^A-Za-z0-9._-]+", "-", nombre)[:100] or "unknown"


def store(cwd=None):
    # The main checkout's, where the local store writes: a worktree with an old copy would split the events in two stores
    ruta = os.path.join(raiz_principal(cwd), ".barrilete", "learning.json")
    if not os.path.exists(ruta):
        return "local"
    try:
        with open(ruta, encoding="utf-8") as fh:
            datos = json.load(fh)
    except (OSError, ValueError) as e:
        raise LearningError(f".barrilete/learning.json cannot be read ({e.__class__.__name__})")
    valor = datos.get("store", "local") if isinstance(datos, dict) else None
    if valor not in ("local", "branch"):
        raise LearningError('.barrilete/learning.json: "store" is "local" or "branch"')
    return valor


# --- the context of an event: who emits it, never guessed ---

def tarea():
    """task.json of the `bk` task (BK_TASK_DIR, ADR-005), or {} if there is none or it cannot be read."""
    d = os.environ.get("BK_TASK_DIR")
    if not d:
        return {}
    try:
        with open(os.path.join(d, "task.json"), encoding="utf-8") as fh:
            datos = json.load(fh)
    except (OSError, ValueError):
        return {}
    return datos if isinstance(datos, dict) else {}


def _bloque(ruta):
    try:
        with open(ruta, encoding="utf-8") as fh:
            texto = fh.read()
    except OSError:
        return ""
    i = texto.find(BEGIN)
    j = texto.find(END, i) if i >= 0 else -1
    return texto[i:j + len(END)] if j >= 0 else ""


def rules_ref(rol=None, cwd=None):
    """<12 of the rules.lock SHA>.<12 of the sha256 of the generated sections the role reads>, or None without a lock."""
    base = raiz(cwd)
    try:
        with open(os.path.join(base, ".barrilete", "rules.lock"), encoding="utf-8") as fh:
            lock = fh.read()
    except OSError:
        return None
    m = re.search(r"^sha=([0-9a-f]{12,64})\s*$", lock, re.M)
    if not m:
        return None
    partes = [("AGENTS.md", _bloque(os.path.join(base, "AGENTS.md")))]
    if rol and re.fullmatch(SLUG, rol):
        nombre = f".claude/agents/{rol}.md"
        partes.append((nombre, _bloque(os.path.join(base, nombre))))
    h = hashlib.sha256("".join(f"{n}\0{b}\0" for n, b in partes).encode("utf-8")).hexdigest()
    return f"{m.group(1)[:12]}.{h[:12]}"


def contexto(cwd=None):
    """The fields every event of this process shares: project, model, harness, provider and, inside a `bk` task, the task's."""
    ctx = {"v": 1, "project": proyecto(cwd)}
    model = os.environ.get("BK_MODEL") or os.environ.get("BARRILETE_MODEL", "")   # bk exports BARRILETE_*
    ctx["model"] = model if CAMPOS["model"](model) else "unknown"
    harness = os.environ.get("BK_HARNESS")
    if harness:   # set and not empty: it is the only source, and an invalid one is unknown (not claude-code)
        ctx["harness"] = harness if CAMPOS["harness"](harness) else "unknown"
    else:
        ctx["harness"] = "claude-code" if os.environ.get("CLAUDECODE") == "1" else "unknown"
    provider = os.environ.get("BK_PROVIDER") or os.environ.get("BARRILETE_PROVIDER", "")
    if CAMPOS["provider"](provider):
        ctx["provider"] = provider
    t = tarea()
    for campo, clave in (("task_id", "id"), ("role", "role"), ("pr", "pr")):
        if CAMPOS[campo](t.get(clave)):
            ctx[campo] = t[clave]
    if t:
        ref = rules_ref(ctx.get("role"), cwd)
        if ref:
            ctx["rules_ref"] = ref
    return ctx


def ahora():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


# --- the stores ---

def _escribir_local(lineas, cwd):
    carpeta = os.path.join(raiz_principal(cwd), ".barrilete", "learning")
    try:
        os.makedirs(carpeta, exist_ok=True)
        ignorar = os.path.join(carpeta, ".gitignore")
        if not os.path.exists(ignorar):   # it ignores itself, even if the project's .gitignore lacks the line
            with open(ignorar, "w", encoding="utf-8") as fh:
                fh.write("# Generated by scripts/agents/learning.py: the learning store never goes into the repo.\n*\n")
        with open(os.path.join(carpeta, ARCHIVO), "a", encoding="utf-8") as fh:
            fh.write(lineas)
    except OSError as e:
        raise LearningError(f"could not write in {carpeta}: {e.strerror or e}")


def _env_commit(cwd):
    """The environment for commit-tree: the person's identity if git has one, a fixed one otherwise (a hook has no prompt)."""
    env = dict(os.environ)
    if _git("var", "GIT_COMMITTER_IDENT", cwd=cwd).returncode != 0:
        for k in ("GIT_AUTHOR", "GIT_COMMITTER"):
            env[f"{k}_NAME"], env[f"{k}_EMAIL"] = "barrilete learning", "learning@barrilete.invalid"
    return env


def _contenido(rev, cwd):
    r = _git("cat-file", "-p", f"{rev}:{ARCHIVO}", cwd=cwd)
    return r.stdout if r.returncode == 0 else ""


def _commit(contenido, padres, mensaje, cwd):
    """A commit with the parents' tree (of the first one) and events.jsonl replaced. Never touches the index or the tree."""
    entradas = []
    if padres:
        entradas = [e for e in _salida("ls-tree", "-z", padres[0], cwd=cwd).split("\0")
                    if e and e.split("\t", 1)[-1] != ARCHIVO]
    blob = _salida("hash-object", "-w", "--stdin", cwd=cwd, entrada=contenido)
    entradas.append(f"100644 blob {blob}\t{ARCHIVO}")
    arbol = _salida("mktree", "-z", cwd=cwd, entrada="".join(e + "\0" for e in entradas))
    args = ["commit-tree", "--no-gpg-sign", arbol, "-m", mensaje]
    for p in padres:
        args += ["-p", p]
    return _salida(*args, cwd=cwd, env=_env_commit(cwd))


def _rev(ref, cwd):
    r = _git("rev-parse", "-q", "--verify", f"{ref}^{{commit}}", cwd=cwd)
    return r.stdout.strip() if r.returncode == 0 else None


def _escribir_rama(lineas, cwd, intentos=5):
    """One commit on agents/learning with the new lines. The ref moves only if nobody moved it meanwhile (update-ref with
    the old value); if someone did, it tries again over the new tip."""
    for _ in range(intentos):
        padre = _rev(REF, cwd)
        base = padre or _rev(f"refs/remotes/{REMOTO}/{RAMA}", cwd)   # a fresh clone continues the remote's history
        contenido = _contenido(base, cwd) if base else ""
        if contenido and not contenido.endswith("\n"):
            contenido += "\n"
        nuevo = _commit(contenido + lineas, [base] if base else [], "learning: add events", cwd)
        if _git("update-ref", REF, nuevo, padre or "", cwd=cwd).returncode == 0:
            return
    raise LearningError(f"{RAMA} kept moving while writing")


def escribir(eventos, cwd=None):
    """Validates the events and writes them, all in one write (one line each, one commit with store branch)."""
    for ev in eventos:
        p = problemas(ev)
        if p:
            raise LearningError("invalid event: " + "; ".join(p))
    if not eventos:
        return
    lineas = "".join(json.dumps(ev, ensure_ascii=False, sort_keys=True) + "\n" for ev in eventos)
    if store(cwd) == "branch":
        _escribir_rama(lineas, cwd)
    else:
        _escribir_local(lineas, cwd)


def ajenos(campos, ctx):
    """The given fields that are not the event's own: outside PROPIOS, or already set by the context (role and pr in a `bk`
    task come from task.json, and rules_ref is the one of that role)."""
    return sorted(k for k in campos if k not in PROPIOS or k in ctx)


def evento(kind, campos=None, ctx=None, cwd=None):
    """An event of this kind with the shared context, ts and the given fields, which never overwrite the context."""
    ev = dict(ctx if ctx is not None else contexto(cwd))
    malos = ajenos(campos or {}, ev)
    if malos:
        raise LearningError(f"fields that are not the event's own: {', '.join(malos)}")
    ev.update({"ts": ahora(), "kind": kind})
    ev.update(campos or {})
    return ev


# --- push: the store branch to origin, joining the lines if the remote moved ---

def _lineas(texto):
    return [x for x in texto.splitlines() if x.strip()]


def push(cwd=None):
    if store(cwd) != "branch":
        return "store is local: there is nothing to push"
    for _ in range(5):
        local = _rev(REF, cwd)
        if not local:
            return f"there is no local {RAMA}: nothing to push"
        r = _git("ls-remote", "--exit-code", REMOTO, REF, cwd=cwd)
        if r.returncode not in (0, 2):
            raise LearningError(f"cannot read {REMOTO}: {r.stderr.strip().splitlines()[-1:] or ['?']}")
        remoto = None
        if r.returncode == 0:
            _salida("fetch", "-q", REMOTO, f"+{REF}:refs/remotes/{REMOTO}/{RAMA}", cwd=cwd)
            remoto = _rev(f"refs/remotes/{REMOTO}/{RAMA}", cwd)
        if remoto == local or (remoto and _git("merge-base", "--is-ancestor", local, remoto, cwd=cwd).returncode == 0):
            if remoto != local:
                _git("update-ref", REF, remoto, local, cwd=cwd)
            return f"{RAMA} is up to date with {REMOTO}"
        destino = local
        if remoto and _git("merge-base", "--is-ancestor", remoto, local, cwd=cwd).returncode != 0:
            # Diverged: the remote's lines, then the ones this clone added after the common point (append-only)
            mb = _git("merge-base", local, remoto, cwd=cwd).stdout.strip()
            base = _lineas(_contenido(mb, cwd)) if mb else []
            mias = _lineas(_contenido(local, cwd))
            vistas = set(base)
            nuevas = mias[len(base):] if mias[:len(base)] == base else [x for x in mias if x not in vistas]
            texto = "".join(x + "\n" for x in _lineas(_contenido(remoto, cwd)) + nuevas)
            destino = _commit(texto, [remoto, local], f"learning: join {RAMA}", cwd)
            if _git("update-ref", REF, destino, local, cwd=cwd).returncode != 0:
                continue   # an emit landed meanwhile: start over
        r = _git("push", "-q", REMOTO, f"{destino}:{REF}", cwd=cwd)
        if r.returncode == 0:
            return f"{RAMA} pushed to {REMOTO}"
        if not re.search(r"\[rejected\]|fetch first|non-fast-forward", r.stderr):
            # Not a race (no auth, a protected ref, a hook): retrying does not fix it, git's reason does
            raise LearningError(f"could not push {RAMA}: {r.stderr.strip() or 'git push failed'}")
    raise LearningError(f"could not push {RAMA}: {REMOTO} kept moving")


# --- CLI ---

def _valor(campo, texto):
    return int(texto) if campo == "pr" and re.fullmatch(r"\d{1,9}", texto) else texto


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if argv else 64
    cmd, args = argv[0], argv[1:]
    try:
        if cmd == "validate" and len(args) == 1:
            ok, errores, heredadas = validar_archivo(args[0])
            for e in errores:
                print(e)
            if errores:
                return 3
            print(f"ok: {ok} event(s)" + (f", {heredadas} legacy v0 line(s) (#323)" if heredadas else ""))
            return 0
        if cmd == "emit" and args:
            campos = {}
            for a in args[1:]:
                k, sep, v = a.partition("=")
                if not sep:
                    print(f"learning.py: {a!r} is not field=value", file=sys.stderr)
                    return 64
                campos[k] = _valor(k, v)
            ctx = contexto()
            malos = ajenos(campos, ctx)
            if malos:
                print(f"learning.py: emit does not set {', '.join(malos)}: it sets {', '.join(PROPIOS)}, and inside a bk "
                      "task not role or pr (they come from task.json)", file=sys.stderr)
                return 64
            escribir([evento(args[0], campos, ctx)])
            return 0
        if cmd == "push" and not args:
            store()   # an invalid learning.json is 3, like in emit; only a git failure of the push is 1
            try:
                print(push())
            except LearningError as e:
                print(f"learning.py: {e}", file=sys.stderr)
                return 1
            return 0
        if cmd == "rules-ref" and len(args) <= 1:
            ref = rules_ref(args[0] if args else None)
            if not ref:
                print("learning.py: there is no .barrilete/rules.lock with a sha", file=sys.stderr)
                return 1
            print(ref)
            return 0
    except LearningError as e:
        print(f"learning.py: {e}", file=sys.stderr)
        return 3
    except (OSError, ValueError) as e:   # a file that cannot be read, or is not UTF-8
        print(f"learning.py: {e.__class__.__name__}: {e}", file=sys.stderr)
        return 3
    print(__doc__.strip(), file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
