"""Task events tests (#248, ADR-005 D1, D4, D5): what the hook writes in the task of a `bk` agent, and what it never does."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(os.path.dirname(AQUI))
SCRIPT = os.path.join(AQUI, "task_events.py")
sys.path.insert(0, AQUI)
import task_events as te  # noqa: E402


def tarea(status="in_progress", seq=1):
    d = tempfile.mkdtemp()
    with open(os.path.join(d, "task.json"), "w") as f:
        json.dump({"id": "1-implementer", "status": status, "seq": seq}, f)
    with open(os.path.join(d, "events.jsonl"), "w") as f:
        f.write(json.dumps({"seq": 1, "type": "task.created"}) + "\n")
    return d


def correr(entrada, d, script=SCRIPT):
    env = {k: v for k, v in os.environ.items() if k != "BK_TASK_DIR"}
    if d:
        env["BK_TASK_DIR"] = d
    return subprocess.run([sys.executable, script], input=json.dumps(entrada), text=True, env=env,
                          capture_output=True, timeout=20)


def leer(d):
    with open(os.path.join(d, "task.json")) as f:
        t = json.load(f)
    with open(os.path.join(d, "events.jsonl")) as f:
        return t, [json.loads(l) for l in f if l.strip()]


def bash(cmd, sha="1a2b3c4", pr=None):
    out = f"[claude/1-x {sha}] feat: algo\n 1 file changed" if sha else ""
    if pr:
        out = f"https://github.com/a/b/pull/{pr}\n"
    return {"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": {"command": cmd},
            "tool_response": {"stdout": out, "stderr": ""}}


class Eventos(unittest.TestCase):
    def test_sin_bk_task_dir_no_escribe_nada(self):
        d = tarea()
        r = correr({"hook_event_name": "Stop"}, None)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(leer(d)[0]["status"], "in_progress")
        self.assertEqual(len(leer(d)[1]), 1)

    def test_session_start(self):
        d = tarea()
        correr({"hook_event_name": "SessionStart"}, d)
        t, ev = leer(d)
        self.assertEqual((t["status"], t["seq"], ev[-1]["type"], ev[-1]["seq"]), ("in_progress", 2, "task.started", 2))

    def test_stop_espera_y_nunca_cierra(self):
        d = tarea()
        for _ in range(3):
            correr({"hook_event_name": "Stop"}, d)
        t, ev = leer(d)
        self.assertEqual(t["status"], "waiting")
        self.assertEqual([e["type"] for e in ev[1:]], ["turn.waiting"] * 3)
        self.assertNotIn(t["status"], te.TERMINAL)

    def test_user_prompt_vuelve_a_trabajar_sin_evento(self):
        d = tarea("waiting")
        correr({"hook_event_name": "UserPromptSubmit", "prompt": "sí, dale"}, d)
        t, ev = leer(d)
        self.assertEqual((t["status"], len(ev)), ("in_progress", 1))

    def test_commit_guarda_solo_el_sha(self):
        d = tarea()
        correr(bash('git commit -m "feat: algo con secretos"'), d)
        ev = leer(d)[1][-1]
        self.assertEqual((ev["type"], ev["sha"]), ("commit", "1a2b3c4"))
        self.assertEqual(sorted(ev), ["seq", "sha", "ts", "type"])   # ni el comando ni la salida (D5)

    def test_pr_abierto(self):
        d = tarea()
        correr(bash("gh pr create --fill", pr=241), d)
        ev = leer(d)[1][-1]
        self.assertEqual((ev["type"], ev["pr"]), ("pr.opened", 241))

    def test_comandos_que_no_cuentan(self):
        d = tarea()
        for cmd in ("ls", "echo git commit", "git status", "git commit --help-me-not"):
            correr(bash(cmd, sha=None), d)
        correr(bash("git commit -m x", sha=None), d)   # un commit que falló: sin "[rama sha]" en la salida
        self.assertEqual(len(leer(d)[1]), 1)

    def test_terminal_y_pendiente_no_se_tocan(self):
        for st in sorted(te.TERMINAL) + ["pending"]:
            d = tarea(st)
            for e in ({"hook_event_name": "SessionStart"}, {"hook_event_name": "Stop"}, bash("git commit -m x")):
                correr(e, d)
            t, ev = leer(d)
            self.assertEqual((t["status"], len(ev)), (st, 1), st)

    def test_sigue_el_seq_de_bk(self):
        d = tarea(seq=7)
        correr({"hook_event_name": "Stop"}, d)
        self.assertEqual(leer(d)[1][-1]["seq"], 8)

    def test_entrada_rota_no_frena_al_agente(self):
        d = tarea()
        r = subprocess.run([sys.executable, SCRIPT], input="{no es json", text=True,
                           env={**os.environ, "BK_TASK_DIR": d}, capture_output=True)
        self.assertEqual((r.returncode, r.stderr), (0, ""))
        r = correr({"hook_event_name": "Stop"}, "/no/existe")
        self.assertEqual(r.returncode, 0)


class Detecta(unittest.TestCase):
    def test_variantes(self):
        for cmd in ("git commit -m x", "cd a && git commit -m x", "git -C repo commit -am x", "/usr/bin/git commit",
                    "make test; git commit -m x", "true || git commit -m x"):
            self.assertTrue(te.runs(cmd, "git", "commit"), cmd)
        for cmd in ("echo git commit", "git log --grep commit", "gitx commit", "grep 'git commit' f"):
            self.assertFalse(te.runs(cmd, "git", "commit"), cmd)
        self.assertTrue(te.runs("gh -R a/b pr create --fill", "gh", "pr", "create"))
        self.assertFalse(te.runs("gh pr view 3", "gh", "pr", "create"))

    def test_lineal_con_un_comando_enorme(self):
        cmd = ("git " + "-x " * 50000 + "a ") * 3 + "; " + "a b " * 100000
        t0 = time.time()
        te.runs(cmd, "git", "commit")
        self.assertLess(time.time() - t0, 2)


class Registro(unittest.TestCase):
    """El comando registrado: sin BK_TASK_DIR, o con un Bash que no es git commit ni gh pr create, no arranca Python."""

    def comandos(self, path):
        with open(os.path.join(RAIZ, path)) as f:
            hooks = json.load(f)["hooks"]
        return {ev: h["command"] for ev, gs in hooks.items() for g in gs for h in g["hooks"]
                if "task_events.py" in h["command"]}

    def test_claude_y_codex_registran_lo_mismo(self):
        c, x = self.comandos(".claude/settings.json"), self.comandos(".codex/hooks.json")
        self.assertEqual(sorted(c), ["PostToolUse", "SessionStart", "Stop", "UserPromptSubmit"])
        self.assertEqual(c, x)

    def test_el_filtro_de_sh(self):
        cmd = self.comandos(".claude/settings.json")["PostToolUse"]
        fake = tempfile.mkdtemp()
        marca = os.path.join(fake, "arranco")
        with open(os.path.join(fake, "python3"), "w") as f:
            f.write(f"#!/bin/sh\ncat >/dev/null; touch {marca}\n")
        os.chmod(os.path.join(fake, "python3"), 0o755)
        env = {**os.environ, "PATH": fake + os.pathsep + os.environ["PATH"], "CLAUDE_PROJECT_DIR": RAIZ}

        def corre(entrada, con_tarea=True):
            e = dict(env, BK_TASK_DIR=tarea()) if con_tarea else {k: v for k, v in env.items() if k != "BK_TASK_DIR"}
            if os.path.exists(marca):
                os.remove(marca)
            r = subprocess.run(["sh", "-c", cmd], input=json.dumps(entrada), text=True, env=e, capture_output=True)
            self.assertEqual(r.returncode, 0)
            return os.path.exists(marca)

        self.assertFalse(corre(bash("ls -la", sha=None)), "un ls no arranca Python")
        self.assertTrue(corre(bash("git commit -m x")), "un git commit sí")
        self.assertTrue(corre(bash("gh pr create --fill", pr=3)), "un gh pr create sí")
        self.assertFalse(corre(bash("git commit -m x"), con_tarea=False), "sin BK_TASK_DIR, nada")


if __name__ == "__main__":
    unittest.main()
