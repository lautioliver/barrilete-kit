#!/usr/bin/env python3
"""Guardrails: Claude Code PreToolUse hook that blocks, before they run, the commands an agent
never runs on its own (AGENTS.md, "Agent autonomy" / "Autonomía del agente" → "Never" / "Nunca"): merging or approving PRs, pushing to a
trunk branch, creating tags or releases, touching branch protection and skipping hooks with --no-verify.

It is registered in .claude/settings.json. It reads the hook JSON from stdin; if it blocks, it exits
with 2 and explains on stderr what to do (Claude Code shows it to the agent). If the person asked for
the step, they run it in the chat with `! <command>`. There is deliberately no variable to disable it:
the agent could set it.

They are guardrails, not a lock: they stop the common mistake (the agent that merges because it is the
next step), not a script that does the same through another path. The lock is branch protection.
"""
import json
import os
import re
import shlex
import subprocess
import sys

TRONCALES = {"main", "master", "develop", "<BASE_BRANCH>"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
GIT_OPC_CON_VALOR = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
CON_NO_VERIFY = {"commit", "push", "merge", "am", "rebase", "cherry-pick", "revert", "pull"}
COMMIT_CON_VALOR = set("mFcCtuS")  # opciones cortas de commit cuyo valor puede ir pegado
TAG_LISTAR = {"-l", "--list", "-v", "--verify", "--contains", "--no-contains", "--points-at", "--merged",
              "--no-merged"}
TAG_CON_VALOR = {"-m", "--message", "-F", "--file", "-u", "--local-user", "--sort", "--format", "--cleanup",
                 "--color", "--column", "--contains", "--no-contains", "--points-at", "--merged", "--no-merged"}
PUSH_CON_VALOR = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
MUTACIONES_GRAPHQL = ("mergePullRequest", "enablePullRequestAutoMerge", "mergeBranch", "createRef", "updateRef",
                      "createRelease", "deleteBranchProtectionRule", "updateBranchProtectionRule")
TRONCAL_RE = "|".join(re.escape(t) for t in sorted(TRONCALES))


def sin_comentarios(texto):
    """Removes comments (# at the start of a word) and empties $'…' strings, outside quotes.

    shlex understands neither: an apostrophe in a comment would look like an unclosed quote."""
    fuera, i, n = [], 0, len(texto)
    while i < n:
        c = texto[i]
        if c == "\\":
            fuera.append(texto[i:i + 2])
            i += 2
        elif texto.startswith("$'", i):
            j = i + 2
            while j < n and texto[j] != "'":
                j += 2 if texto[j] == "\\" else 1
            fuera.append("''")
            i = j + 1
        elif c == "'":
            j = texto.find("'", i + 1)
            j = n if j < 0 else j
            fuera.append(texto[i:j + 1])
            i = j + 1
        elif c == '"':
            j = i + 1
            while j < n and texto[j] != '"':
                j += 2 if texto[j] == "\\" else 1
            fuera.append(texto[i:j + 1])
            i = j + 1
        elif c == "#" and (i == 0 or texto[i - 1] in " \t\n;&|()"):
            j = texto.find("\n", i)
            i = n if j < 0 else j
        else:
            fuera.append(c)
            i += 1
    return "".join(fuera)


def sacar_heredocs(texto):
    """A heredoc body is text, not commands: it is removed before analyzing."""
    fuera, fin = [], None
    for linea in texto.split("\n"):
        if fin is not None:
            if linea.strip() == fin:
                fin = None
            continue
        fuera.append(linea)
        m = re.search(r"(?<![<\w])<<-?(?!<)\s*(['\"]?)([^\s'\"<>;&|()]+)\1", linea)
        if m:
            fin = m.group(2)
    return "\n".join(fuera)


def sustituciones(texto):
    """What runs inside $(…) and `…`, except inside single quotes."""
    dentro, i, simples = [], 0, False
    while i < len(texto):
        c = texto[i]
        if c == "\\" and not simples:
            i += 2
            continue
        if c == "'":
            simples = not simples
        elif not simples and texto.startswith("$(", i):
            nivel, j = 1, i + 2
            while j < len(texto) and nivel:
                nivel += {"(": 1, ")": -1}.get(texto[j], 0)
                j += 1
            dentro.append(texto[i + 2:j - 1])
            i = j
            continue
        elif not simples and c == "`":
            j = texto.find("`", i + 1)
            j = len(texto) if j < 0 else j
            dentro.append(texto[i + 1:j])
            i = j + 1
            continue
        i += 1
    return dentro


def comandos(texto):
    """Splits the text into simple commands (lists of words)."""
    texto = texto.replace("\n", " ; ")
    try:
        lex = shlex.shlex(texto, posix=True, punctuation_chars=";&|()")
        lex.whitespace_split = True
        lex.commenters = ""
        tokens = list(lex)
    except ValueError:
        # Quotes that shlex does not understand: better to split too much than let the command through.
        tokens = re.findall(r"[;&|()]+|[^\s;&|()'\"]+", texto)
    actual = []
    for tok in tokens:
        if set(tok) <= set(";&|()"):
            if actual:
                yield actual
            actual = []
        else:
            actual.append(tok)
    if actual:
        yield actual


def antes_de_dobleguion(args):
    return args[:args.index("--")] if "--" in args else args


def es_no_verify(a):
    return re.match(r"^--no-veri(f|fy)?$", a) is not None


def commit_con_n(a):
    """-n (--no-verify) inside a group of short commit options, like -an."""
    if not re.match(r"^-[a-zA-Z]", a):
        return False
    for c in a[1:]:
        if c == "n":
            return True
        if c in COMMIT_CON_VALOR:
            return False
    return False


class Contexto:
    def __init__(self, rama_actual, es_tag, cwd):
        self.rama_actual, self.es_tag, self.base = rama_actual, es_tag, cwd

    def rama(self, cwd):
        """The branch of cwd; if it does not exist (a cd to a new directory), the one of the starting directory."""
        for d in (cwd, self.base):
            try:
                return self.rama_actual(d)
            except Exception:
                continue
        return None

    def tag(self, nombre, cwd):
        try:
            return self.es_tag(nombre, cwd)
        except Exception:
            return False


def analizar_git(args, cwd, ctx):
    i = 0
    while i < len(args) and args[i].startswith("-"):
        if args[i] in GIT_OPC_CON_VALOR and i + 1 < len(args):
            valor = args[i + 1]
            if args[i] == "-C":
                cwd = os.path.join(cwd or os.getcwd(), valor)
            if args[i] == "-c" and valor.lower().startswith("core.hookspath"):
                return "skipping git hooks (core.hooksPath)"
            i += 2
        else:
            i += 1
    if i >= len(args):
        return None
    sub, resto = args[i], antes_de_dobleguion(args[i + 1:])
    if sub in CON_NO_VERIFY and any(es_no_verify(a) for a in resto):
        return "skipping hooks and checks with --no-verify"
    if sub == "commit" and any(commit_con_n(a) for a in resto):
        return "skipping hooks and checks with --no-verify (-n)"
    if sub == "tag":
        return analizar_tag(resto)
    if sub == "push":
        return analizar_push(resto, cwd, ctx)
    return None


def analizar_tag(args):
    if any(a.split("=")[0] in TAG_LISTAR or re.match(r"^-n\d*$", a) for a in args):
        return None
    if "-d" in args or "--delete" in args:
        return "deleting tags"
    posicionales, i = [], 0
    while i < len(args):
        if args[i] in TAG_CON_VALOR:
            i += 2
            continue
        if not args[i].startswith("-"):
            posicionales.append(args[i])
        i += 1
    return "creating tags" if posicionales else None


def analizar_push(args, cwd, ctx):
    opciones, posicionales, i = set(), [], 0
    while i < len(args):
        a = args[i]
        if a in PUSH_CON_VALOR:
            opciones.add(a)
            i += 2
            continue
        if a.startswith("-"):
            opciones.add(a.split("=")[0])
        else:
            posicionales.append(a)
        i += 1
    for o, que in (("--all", "pushing all branches"), ("--mirror", "pushing all branches"),
                   ("--tags", "pushing tags"), ("--follow-tags", "pushing tags")):
        if o in opciones:
            return que
    borrar = bool(opciones & {"--delete", "-d"})
    # With --repo the remote is not among the positionals: all of them are refspecs.
    refspecs = (posicionales if "--repo" in opciones else posicionales[1:]) or ["HEAD"]
    if "tag" in refspecs:
        return "pushing tags"
    for r in refspecs:
        r = r.lstrip("+")
        origen, destino = r.split(":", 1) if ":" in r else (r, r)
        if "$" in destino or destino in ("HEAD", "@"):
            # If it cannot be resolved, the current branch is assumed (the most common: git push origin HEAD).
            destino = ctx.rama(cwd) or ""
        if destino.startswith("refs/tags/") or (not borrar and origen and ctx.tag(origen, cwd)):
            return "pushing tags"
        destino = destino.removeprefix("refs/heads/")
        if destino in TRONCALES:
            return f"deleting the trunk branch {destino}" if borrar else f"pushing to the trunk branch {destino}"
    return None


def metodo_api(args):
    for i, a in enumerate(args):
        if a in ("-X", "--method") and i + 1 < len(args):
            return args[i + 1].upper()
        if a.startswith("--method="):
            return a.split("=", 1)[1].upper()
        if re.match(r"^-X[A-Za-z]+$", a):
            return a[2:].upper()
    if any(re.match(r"^-[fF]", a) or a.startswith(("--field", "--raw-field", "--input")) for a in args):
        return "POST"
    return "GET"


def analizar_gh(args):
    palabras, i = [], 0
    while i < len(args):
        if args[i] in ("-R", "--repo"):
            i += 2
            continue
        if not args[i].startswith("-"):
            palabras.append(args[i])
        i += 1
    if palabras[:2] == ["pr", "merge"]:
        return "merging a PR"
    if palabras[:2] == ["pr", "review"] and any(a in ("--approve", "-a") for a in args):
        return "approving a PR"
    if palabras[:1] == ["release"] and palabras[1:2] and palabras[1] in ("create", "delete", "edit", "upload"):
        return "creating, editing or deleting releases"
    if palabras[:1] == ["api"]:
        texto = " ".join(args)
        if any(m in texto for m in MUTACIONES_GRAPHQL):
            return "merging or touching branches, tags or releases through GraphQL"
        if metodo_api(args) == "GET":
            return None
        if re.search(r"pulls/[^/\s]+/merge\b", texto) or re.search(r"/merges\b", texto):
            return "merging through the API"
        if re.search(r"/releases\b", texto):
            return "creating, editing or deleting releases"
        if re.search(r"/git/refs\b", texto) and (
                "refs/tags/" in texto or re.search(rf"refs/heads/({TRONCAL_RE})(\s|$)", texto)):
            return "creating tags or moving a trunk branch through the API"
        if re.search(r"/protection\b|/rulesets\b", texto):
            return "changing branch protection"
    return None


def analizar(texto, cwd, ctx):
    for sub in sustituciones(texto):
        m = analizar(sub, cwd, ctx)
        if m:
            return m
    for palabras in comandos(texto):
        if palabras[0] == "cd" and len(palabras) > 1:
            destino = os.path.expanduser(os.path.expandvars(palabras[1]))
            if "$" not in destino:
                cwd = os.path.join(cwd or os.getcwd(), destino)
            continue
        # Any git or gh in the command, even after env, timeout, sudo, xargs…
        for i, p in enumerate(palabras):
            nombre, resto, m = p.rsplit("/", 1)[-1], palabras[i + 1:], None
            if nombre == "git":
                m = analizar_git(resto, cwd, ctx)
            elif nombre == "gh":
                m = analizar_gh(resto)
            elif nombre in SHELLS:
                j = next((k for k, a in enumerate(resto) if re.match(r"^-[a-zA-Z]*c[a-zA-Z]*$", a)), None)
                if j is not None and j + 1 < len(resto):
                    m = analizar(preparar(resto[j + 1]), cwd, ctx)
            elif nombre == "eval":
                m = analizar(preparar(" ".join(resto)), cwd, ctx)
            if m:
                return m
    return None


def preparar(texto):
    texto = re.sub(r"\\\n", "", texto or "")  # line continuations
    return sin_comentarios(sacar_heredocs(texto))


def motivo(comando, rama_actual=None, cwd=None, es_tag=None):
    """Why the command must be blocked, or None if it can run."""
    ctx = Contexto(rama_actual or rama_de, es_tag or tag_existe, cwd)
    return analizar(preparar(comando), cwd, ctx)


def rama_de(cwd):
    r = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd or None, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def tag_existe(nombre, cwd):
    r = subprocess.run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{nombre}"], cwd=cwd or None,
                       capture_output=True, text=True)
    return r.returncode == 0


def a_ojo(comando):
    """Last resort if the analysis fails: look for the blocked commands in the raw text."""
    patrones = (r"\bgh\b[^\n;&|]*\bpr\s+merge\b", r"\bgh\b[^\n;&|]*\bpr\s+review\b[^\n;&|]*--approve",
                r"\bgh\s+release\s+(create|delete|edit|upload)\b", r"--no-verify\b", r"\bgit\s+tag\s+\S",
                rf"\bgit\b[^\n;&|]*\bpush\b[^\n;&|]*\b({TRONCAL_RE})\b")
    if any(re.search(p, comando) for p in patrones):
        return "a command I could not analyze that looks like a blocked one"
    return None


def como_texto(valor):
    """A command as text: as is, or joined if it came as a list; None if it is something else."""
    if isinstance(valor, str):
        return valor
    if isinstance(valor, list) and all(isinstance(v, str) for v in valor):
        return " ".join(valor)
    return None


def comando_de(entrada):
    """(command, tool) of the hook, or (None, None) if it is not a shell command.

    Claude Code and Codex: tool_name "Bash" and tool_input.command. Copilot: toolName "bash" and toolArgs
    (object or JSON text). Cursor (beforeShellExecution): command."""
    if not isinstance(entrada, dict):
        return None, None
    if entrada.get("tool_name") == "Bash":
        args = entrada.get("tool_input")
        return como_texto(args.get("command") if isinstance(args, dict) else args), "claude"
    if entrada.get("toolName") == "bash":
        args = entrada.get("toolArgs")
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except ValueError:
                pass  # not JSON: it is the command itself
        return como_texto(args.get("command") if isinstance(args, dict) else args), "copilot"
    if entrada.get("hook_event_name") == "beforeShellExecution":
        return como_texto(entrada.get("command")), "cursor"
    return None, None


def main():
    try:
        entrada = json.load(sys.stdin)
    except ValueError:
        return 0  # without valid input there is no command to block
    comando, herramienta = comando_de(entrada)
    if not comando:
        return 0
    try:
        m = motivo(comando, cwd=entrada.get("cwd"))
    except Exception:
        m = a_ojo(comando)
    if not m:
        return 0
    corto = f"Blocked by the template guardrails (scripts/agents/guardrails.py): {m}."
    texto = (f"{corto}\nAGENTS.md ('Agent autonomy' / 'Autonomía del agente'): an agent does not merge, does not approve PRs, does not create tags or releases, "
             f"does not push to trunk branches and does not skip checks. Do not look for another way: if the person asked for it, "
             f"ask them to run it (in Claude Code, in the chat):\n! {comando.strip()}")
    # Each tool reads the reason from a different place: Claude Code and Codex from stderr with exit 2,
    # Copilot from the JSON (exit 2 denies anyway), Cursor from the JSON with exit 0.
    if herramienta == "copilot":
        print(json.dumps({"permissionDecision": "deny", "permissionDecisionReason": texto}, ensure_ascii=False))
    elif herramienta == "cursor":
        print(json.dumps({"permission": "deny", "user_message": corto, "agent_message": texto}, ensure_ascii=False))
        return 0
    print(texto, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
