"""Flow line tests (flow.py): the step comes from the branch, the PR and the labels of the issue."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow  # noqa: E402

FLOW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "flow.py")

# Fake gh: answers what FAKE_PR and FAKE_LABELS say. Without FAKE_PR the branch has no PR (gh's own message);
# without FAKE_LABELS, or with FAKE_OFFLINE (both calls) or FAKE_PR_FAILS (the PR one), it fails like gh without network.
GH_FALSO = """#!/bin/sh
[ -n "$FAKE_OFFLINE" ] && { echo "error connecting to api.github.com" >&2; exit 1; }
case "$1" in
  pr) [ -n "$FAKE_PR_FAILS" ] && { echo "error connecting to api.github.com" >&2; exit 1; }
      [ -n "$FAKE_PR" ] && printf '%s\\n' "$FAKE_PR" && exit 0
      echo 'no pull requests found for branch "x"' >&2; exit 1;;
  issue) [ -n "$FAKE_LABELS" ] && printf '%s\\n' "$FAKE_LABELS" && exit 0; echo "error connecting" >&2; exit 1;;
esac
exit 1
"""


def datos(pr=None, labels=()):
    return {"pr": pr, "labels": list(labels)}


def pr_abierto(**campos):
    return dict({"number": 1, "state": "OPEN", "isDraft": False, "reviewDecision": "", "latestReviews": []}, **campos)


class Paso(unittest.TestCase):
    def test_sin_pr_es_implement(self):
        self.assertEqual(flow.paso_actual(datos()), "implement")

    def test_pr_abierto_es_review(self):
        self.assertEqual(flow.paso_actual(datos(pr_abierto())), "review")

    def test_pr_en_draft_sigue_en_implement(self):
        self.assertEqual(flow.paso_actual(datos(pr_abierto(isDraft=True))), "implement")

    def test_pr_aprobado_espera_el_merge(self):
        self.assertEqual(flow.paso_actual(datos(pr_abierto(reviewDecision="APPROVED"))), "merge")

    def test_review_obligatoria_con_cambios_pedidos_sigue_en_review(self):
        pr = pr_abierto(reviewDecision="CHANGES_REQUESTED", latestReviews=[{"state": "APPROVED"}])
        self.assertEqual(flow.paso_actual(datos(pr)), "review")

    def test_sin_review_obligatoria_una_aprobacion_alcanza(self):
        pr = pr_abierto(reviewDecision=None, latestReviews=[{"state": "COMMENTED"}, {"state": "APPROVED"}])
        self.assertEqual(flow.paso_actual(datos(pr)), "merge")

    def test_sin_review_obligatoria_un_cambio_pedido_frena(self):
        pr = pr_abierto(reviewDecision=None, latestReviews=[{"state": "APPROVED"}, {"state": "CHANGES_REQUESTED"}])
        self.assertEqual(flow.paso_actual(datos(pr)), "review")

    def test_pr_mergeado_es_retro(self):
        self.assertEqual(flow.paso_actual(datos({"number": 1, "state": "MERGED"})), "retro")

    def test_pr_cerrado_sin_merge_vuelve_a_implement(self):
        self.assertEqual(flow.paso_actual(datos({"number": 1, "state": "CLOSED"})), "implement")

    def test_blocked_gana_a_cualquier_paso(self):
        pr = pr_abierto(reviewDecision="APPROVED")
        self.assertEqual(flow.paso_actual(datos(pr, ["status:blocked"])), "blocked")


class Rama(unittest.TestCase):
    def test_ramas_con_issue(self):
        for rama in ("claude/176-pulir", "feat/12-pagos", "fix/3-qr"):
            self.assertTrue(flow.RAMA_RE.match(rama), rama)

    def test_ramas_sin_issue(self):
        for rama in ("main", "develop", "agents/retros", "lautioliver/discus", "feat/sin-numero", "release/1.2.0"):
            self.assertFalse(flow.RAMA_RE.match(rama), rama)


class Formatos(unittest.TestCase):
    e = {"brand": False, "branch": "claude/7-x", "issue": 7, "pr": 9, "step": "review", "note": None,
         "face": "working", "steps": flow.PASOS}

    def test_plain_marca_el_paso(self):
        self.assertEqual(flow.linea(self.e, "plain"),
                         "plan ● ─ implement ─ ▸review ─ ● merge   #7 · PR #9 in review")

    def test_la_marca_suma_la_carita_del_estado(self):
        for cara, chica in (("working", "(● ●)"), ("planning", "(• • •)"), ("blocked", "(✕ ✕)"), ("ready", "(^ ^)")):
            self.assertTrue(flow.linea(dict(self.e, brand=True, face=cara), "plain").startswith(chica + " plan ●"), cara)

    def test_cada_paso_tiene_su_carita(self):
        self.assertEqual([flow.CARA_DEL_PASO[p] for p in (None, "implement", "review", "merge", "retro", "blocked")],
                         ["planning", "working", "working", "ready", "working", "blocked"])

    def test_la_carita_grande_es_pareja(self):
        for cara in flow.CARAS:
            filas = flow.cara_grande(cara, "plain")
            self.assertEqual(len(filas), 6)
            self.assertEqual({len(f) for f in filas[1:]}, {16}, cara)  # the body, aligned under the propellers

    def test_watch_con_marca_dibuja_la_carita_grande(self):
        e = dict(self.e, brand=True, face="ready", step="merge")
        filas = flow.vista_grande(e, "plain").split("\n")
        self.assertIn("^   ^", filas[3])
        self.assertTrue(filas[3].endswith("PR ready"))
        self.assertTrue(filas[4].endswith("claude/7-x"))
        self.assertEqual(filas[-1], "plan ● ─ implement ─ review ─ ▸● merge   #7 · PR #9 waiting for your merge")

    def test_blocked_no_marca_ningun_paso(self):
        l = flow.linea(dict(self.e, step="blocked"), "plain")
        self.assertTrue(l.startswith("✖ blocked  plan ●"), l)
        self.assertNotIn("▸", l)

    def test_las_notas_aclaran_el_implement(self):
        for nota, texto in (("draft", "PR #9 draft"), ("closed", "PR #9 closed, no merge"),
                            ("offline", "no data from GitHub")):
            self.assertTrue(flow.linea(dict(self.e, step="implement", note=nota), "plain").endswith(texto), nota)

    def test_tmux_escapa_los_numeral(self):
        l = flow.linea(self.e, "tmux")
        self.assertIn("##7", l)
        self.assertIn("PR ##9", l)
        self.assertNotIn("\033", l)

    def test_zsh_envuelve_los_colores(self):
        l = flow.linea(self.e, "zsh")
        self.assertEqual(l.count("\033"), l.count("%{\033"))

    def test_bash_envuelve_los_colores(self):
        l = flow.linea(self.e, "bash")
        self.assertEqual(l.count("\033"), l.count("\001\033"))
        self.assertEqual(l.count("\001"), l.count("\002"))


class Trabajando(unittest.TestCase):
    """While the agent works (hooks --busy on/off): spinner, time and eyes that move."""

    e = {"brand": True, "branch": "claude/7-x", "issue": 7, "pr": 9, "step": "review", "note": None,
         "face": "working", "steps": flow.PASOS}

    def test_los_ojos_se_mueven_cuadro_a_cuadro(self):
        caras = [flow.cara_chica("working", "plain", c) for c in range(4)]
        self.assertEqual(caras, ["(● ●)", "(●● )", "(● ●)", "( ●●)"])
        self.assertEqual(flow.cara_chica("blocked", "plain", 1), "(✕ ✕)")  # blocked does not look around

    def test_trabajando_suma_spinner_y_tiempo(self):
        l = flow.linea(dict(self.e, busy_since=time.time() - 75), "plain")
        self.assertRegex(l, r"PR #9 in review   [⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] working 1m 1[56]s$")

    def test_sin_trabajar_no_hay_spinner(self):
        self.assertNotIn("working", flow.linea(dict(self.e, busy_since=None), "plain"))

    def test_duracion(self):
        self.assertEqual([flow.duracion(s) for s in (0, 59, 61, 3600 + 120)], ["0s", "59s", "1m 01s", "1h 02m"])


class DeVerdad(unittest.TestCase):
    """flow.py run as a process, in a real repo and with a fake gh on the PATH."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.tmp.name, "repo")
        binario = os.path.join(self.tmp.name, "bin")
        os.makedirs(binario)
        with open(os.path.join(binario, "gh"), "w") as f:
            f.write(GH_FALSO)
        os.chmod(os.path.join(binario, "gh"), 0o755)
        self.env = dict(os.environ, PATH=binario + os.pathsep + os.environ["PATH"], GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_CONFIG_NOSYSTEM="1", FAKE_LABELS="[]")
        for v in ("FAKE_PR", "FAKE_OFFLINE", "FAKE_PR_FAILS", "NO_COLOR"):
            self.env.pop(v, None)
        self.git("init", "-q", "-b", "main", self.repo, cwd=self.tmp.name)
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "base")

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args, cwd=None):
        subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.env, check=True, capture_output=True)

    def flow(self, *args, entrada=None, directorio=None, cwd=None):
        r = subprocess.run([sys.executable, FLOW, "--dir", directorio or self.repo, *args], env=self.env, cwd=cwd,
                           input=entrada, capture_output=True, text=True, timeout=20)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.rstrip("\n")

    def cache(self):
        return os.path.join(self.repo, ".git", flow.CACHE_NOMBRE)

    def leer_cache(self):
        with open(self.cache()) as f:
            return json.load(f)["ramas"]

    def vencer_cache(self):
        ramas = self.leer_cache()
        for d in ramas.values():
            d["t"] -= flow.CACHE_TTL + 1
        with open(self.cache(), "w") as f:
            json.dump({"ramas": ramas}, f)

    def refrescar(self, rama, issue):
        """The background refresh, run in the foreground so the test does not poll."""
        subprocess.run([sys.executable, FLOW, "--refresh", self.cache(), rama, issue], cwd=self.repo, env=self.env,
                       check=True)

    def esperar(self, texto, **kw):
        """The background process writes the new cache: polls until the line shows it."""
        for _ in range(50):
            l = self.flow("--format", "plain", **kw)
            if texto in l:
                return l
            time.sleep(0.1)
        return l

    def test_troncal_sin_paso(self):
        self.assertEqual(self.flow("--format", "plain"), "plan ● ─ implement ─ review ─ ● merge   main")

    def test_rama_con_pr_en_review(self):
        self.git("checkout", "-q", "-b", "claude/42-algo")
        self.env["FAKE_PR"] = json.dumps(pr_abierto(number=50))
        self.assertEqual(self.flow("--format", "plain"),
                         "plan ● ─ implement ─ ▸review ─ ● merge   #42 · PR #50 in review")

    def test_statusline_lee_el_directorio_del_json(self):
        otro = os.path.join(self.tmp.name, "otro")
        self.git("clone", "-q", self.repo, otro, cwd=self.tmp.name)
        self.git("checkout", "-q", "-b", "feat/8-x", cwd=otro)
        entrada = json.dumps({"workspace": {"current_dir": otro}})
        self.assertIn("#8 · no PR yet", self.flow("--statusline", "--format", "plain", entrada=entrada))

    def test_json(self):
        self.git("checkout", "-q", "-b", "fix/3-qr")
        self.env["FAKE_LABELS"] = '["status:blocked"]'
        e = json.loads(self.flow("--format", "json"))
        self.assertEqual((e["issue"], e["step"], e["pr"], e["note"]), (3, "blocked", None, None))
        self.assertTrue(e["text"].startswith("✖ blocked"))

    def test_face_imprime_la_carita_sin_repo(self):
        r = subprocess.run([sys.executable, FLOW, "--face", "blocked", "--format", "plain"], capture_output=True,
                           text=True, cwd=self.tmp.name)
        self.assertEqual(r.stdout.splitlines()[3], " │ │  ✕   ✕  │ │")

    def test_en_la_plantilla_aparece_la_carita(self):
        os.makedirs(os.path.join(self.repo, ".github", "brand"))
        self.git("checkout", "-q", "-b", "claude/42-algo")
        self.assertTrue(self.flow("--format", "plain").startswith("(● ●) plan ●"))

    def test_los_hooks_busy_prenden_y_apagan_la_animacion(self):
        self.env["TMPDIR"] = self.tmp.name  # the marks go to the system temp dir: here, the test's
        self.git("checkout", "-q", "-b", "claude/42-algo")
        hook = json.dumps({"session_id": "s/1", "cwd": self.repo})
        estado = json.dumps({"session_id": "s/1", "workspace": {"current_dir": self.repo}})
        self.assertEqual(self.flow("--busy", "on", entrada=hook), "")  # a hook prints nothing
        self.assertRegex(self.flow("--statusline", "--format", "plain", entrada=estado), r"working \d+s$")
        otra = json.dumps({"session_id": "s2", "workspace": {"current_dir": self.repo}})
        self.assertNotIn("working", self.flow("--statusline", "--format", "plain", entrada=otra))  # per session
        self.flow("--busy", "off", entrada=hook)
        self.assertNotIn("working", self.flow("--statusline", "--format", "plain", entrada=estado))

    def test_una_marca_vieja_no_cuenta(self):
        self.env["TMPDIR"] = self.tmp.name
        marcas = os.path.join(self.tmp.name, os.path.basename(flow.OCUPADO_DIR))
        os.makedirs(marcas)
        with open(os.path.join(marcas, "s1"), "w") as f:
            json.dump(time.time() - flow.OCUPADO_MAX - 1, f)  # a turn whose Stop never came
        estado = json.dumps({"session_id": "s1", "workspace": {"current_dir": self.repo}})
        self.assertNotIn("working", self.flow("--statusline", "--format", "plain", entrada=estado))

    def test_fuera_de_un_repo_no_imprime_nada(self):
        r = subprocess.run([sys.executable, FLOW, "--dir", self.tmp.name], env=self.env, capture_output=True,
                           text=True)
        self.assertEqual((r.returncode, r.stdout), (0, "\n"))

    def test_sin_gh_la_primera_vez_no_inventa_que_no_hay_pr(self):
        self.git("checkout", "-q", "-b", "claude/5-x")
        self.env["FAKE_OFFLINE"] = "1"
        self.assertTrue(self.flow("--format", "plain").endswith("#5 · no data from GitHub"))

    def test_cache_vencida_se_muestra_y_se_refresca_de_fondo(self):
        self.git("checkout", "-q", "-b", "claude/5-x")
        self.flow("--format", "plain")  # fills the cache: no PR
        self.vencer_cache()
        self.env["FAKE_PR"] = json.dumps(pr_abierto(number=6, reviewDecision="APPROVED"))
        self.assertIn("no PR yet", self.flow("--format", "plain"))  # does not wait for the network
        self.assertIn("▸● merge   #5 · PR #6 waiting for your merge", self.esperar("waiting for your merge"))

    def test_el_refresco_de_fondo_llega_con_dir_relativo(self):
        self.git("checkout", "-q", "-b", "claude/5-x")
        self.flow("--format", "plain", directorio="repo", cwd=self.tmp.name)
        self.vencer_cache()
        self.env["FAKE_PR"] = json.dumps(pr_abierto(number=6))
        self.flow("--format", "plain", directorio="repo", cwd=self.tmp.name)
        self.assertIn("PR #6 in review", self.esperar("in review", directorio="repo", cwd=self.tmp.name))

    def test_si_solo_falla_el_issue_el_pr_se_refresca_igual(self):
        self.git("checkout", "-q", "-b", "claude/5-x")
        del self.env["FAKE_LABELS"]  # the issue does not answer (another repo, issues turned off)
        self.flow("--format", "plain")
        self.vencer_cache()
        self.env["FAKE_PR"] = json.dumps(pr_abierto(number=6))
        self.flow("--format", "plain")
        self.assertIn("PR #6 in review", self.esperar("in review"))

    def test_sin_red_se_queda_lo_que_habia(self):
        self.git("checkout", "-q", "-b", "claude/5-x")
        self.env["FAKE_PR"] = json.dumps(pr_abierto(number=6))
        self.flow("--format", "plain")
        self.vencer_cache()
        self.env["FAKE_OFFLINE"] = "1"  # gh no longer answers
        self.refrescar("claude/5-x", "5")
        self.assertIn("PR #6 in review", self.flow("--format", "plain"))

    def test_si_solo_falla_el_pr_no_aparece_un_no_pr_yet_falso(self):
        self.git("checkout", "-q", "-b", "claude/5-x")
        self.env["FAKE_PR"] = json.dumps(pr_abierto(number=6))
        self.flow("--format", "plain")
        self.vencer_cache()
        self.env["FAKE_PR_FAILS"] = "1"  # timeout or rate limit on the PR call; the issue answers
        self.refrescar("claude/5-x", "5")
        self.assertIn("PR #6 in review", self.flow("--format", "plain"))

    def test_si_solo_falla_el_issue_no_se_esconde_el_blocked(self):
        self.git("checkout", "-q", "-b", "claude/5-x")
        self.env["FAKE_LABELS"] = '["status:blocked"]'
        self.flow("--format", "plain")
        self.vencer_cache()
        del self.env["FAKE_LABELS"]  # the issue call fails; the PR one answers
        self.env["FAKE_PR"] = json.dumps(pr_abierto(number=6))
        self.refrescar("claude/5-x", "5")
        self.assertTrue(self.flow("--format", "plain").startswith("✖ blocked"))

    def test_volver_a_una_rama_conocida_no_espera_a_gh(self):
        self.git("checkout", "-q", "-b", "claude/5-x")
        self.env["FAKE_PR"] = json.dumps(pr_abierto(number=6))
        self.flow("--format", "plain")
        self.git("checkout", "-q", "-b", "claude/7-y")
        self.flow("--format", "plain")
        self.git("checkout", "-q", "claude/5-x")
        self.env["FAKE_OFFLINE"] = "1"  # if it asked gh again, the line would lose the PR
        self.assertIn("#5 · PR #6 in review", self.flow("--format", "plain"))
        self.assertEqual(sorted(self.leer_cache()), ["claude/5-x", "claude/7-y"])

    def test_una_cache_que_no_es_un_objeto_cuenta_como_vacia(self):
        self.git("checkout", "-q", "-b", "claude/5-x")
        for contenido in ("[1, 2]", '{"ramas": [1]}', '{"ramas": {"claude/5-x": 3}}', "7"):
            with open(self.cache(), "w") as f:
                f.write(contenido)
            self.assertIn("#5", self.flow("--format", "plain"), contenido)

    def test_el_refresco_de_fondo_solo_arranca_si_se_escribio_la_cache(self):
        ruta = self.cache()
        ahora = time.time()
        vieja = {"t": ahora - flow.CACHE_TTL - 1, "ok": True, "pr": None, "labels": []}
        for escribe, lanzado in ((True, 1), (False, 0)):
            flow.guardar(ruta, {"ramas": {"claude/5-x": vieja}})
            with mock.patch.object(flow.subprocess, "Popen") as popen, \
                    mock.patch.object(flow, "guardar_rama", return_value=escribe):
                flow.datos_github(self.repo, ruta, "claude/5-x", "5")
            self.assertEqual(popen.call_count, lanzado, f"guardar_rama devuelve {escribe}")

    def test_las_marcas_van_en_un_directorio_por_usuario(self):
        self.assertTrue(os.path.basename(flow.OCUPADO_DIR).startswith("agent-kit-flow-"))

    def test_la_cache_guarda_hasta_un_maximo_de_ramas(self):
        ruta = self.cache()
        for i in range(flow.CACHE_RAMAS + 3):
            flow.guardar_rama(ruta, f"claude/{i}-x", {"t": i, "ok": True, "pr": None, "labels": []})
        ramas = self.leer_cache()
        self.assertEqual(len(ramas), flow.CACHE_RAMAS)
        self.assertNotIn("claude/0-x", ramas)  # the oldest went first


if __name__ == "__main__":
    unittest.main()
