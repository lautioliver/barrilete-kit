#!/usr/bin/env python3
"""Creates a work plan on GitHub: epic, sub-issues and blocks between them.

Usage:
  planner.py plan.json --draft      # validates and shows the plan; creates nothing
  planner.py plan.json              # creates everything (after confirming the draft)
  planner.py plan.json --repo owner/repo

plan.json format:
{
  "epic": {"title": "...", "body": "...", "labels": ["type:feature", "area:api"]},
  "issues": [
    {"key": "schema", "title": "...", "body": "...", "labels": ["type:task"]},
    {"key": "migration", "title": "...", "body": "...", "labels": ["type:task"],
     "blocked_by": ["schema", 25], "reason": "needs the new table"}
  ]
}
- "epic" is optional. If present, each issue becomes a sub-issue of the epic.
- "blocked_by" accepts keys of the same plan or numbers of issues that already exist.
- "assignee" (optional) sets the owner; if missing, it is picked from the team (.github/team.json):
  by area and load, also spreading across the issues of the same plan.
"""
import json
import os
import subprocess
import sys
import tempfile


def gh(*args, entrada=None):
    r = subprocess.run(["gh", *args], capture_output=True, text=True, input=entrada)
    if r.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args[:3])}…: {r.stderr.strip()}")
    return r.stdout.strip()


def gh_json(*args):
    return json.loads(gh(*args) or "null")


def labels_validos():
    """Reads the names from .github/labels.yml (if it exists) without depending on PyYAML."""
    raiz = gh_raiz()
    ruta = os.path.join(raiz, ".github", "labels.yml")
    if not os.path.exists(ruta):
        return None
    nombres = set()
    with open(ruta) as f:
        for linea in f:
            linea = linea.strip()
            if linea.startswith("- name:"):
                nombres.add(linea.split(":", 1)[1].strip().strip('"').strip("'"))
    return nombres


def gh_raiz():
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return r.stdout.strip() or "."


def responsables(plan, orden):
    """Owner of the epic and of each issue: the one in the plan, or the one the team picks.

    The load is added as it is assigned, so a large plan does not fall entirely on one person.
    """
    raiz = gh_raiz()
    sys.path.insert(0, os.path.join(raiz, "scripts", "agents"))
    try:
        import team as equipo
    except ImportError:
        return {}
    integrantes = equipo.leer().get("members", [])
    activos = [i["login"] for i in integrantes if i.get("active", True)]
    carga = equipo.carga_actual(activos) if activos else {}
    asignados = {}
    todos = ([("epic", plan["epic"])] if plan.get("epic") else []) + [(i["key"], i) for i in orden]
    for clave, item in todos:
        login = item.get("assignee") or equipo.elegir(integrantes, item.get("labels", []), carga)
        if login:
            asignados[clave] = login.lstrip("@")
            carga[asignados[clave]] = carga.get(asignados[clave], 0) + 1
    return asignados


def orden_topologico(issues):
    """Sorts so that each issue comes after its blockers. Fails if there is a cycle."""
    claves = {i["key"] for i in issues}
    pendientes = {i["key"]: {b for b in i.get("blocked_by", []) if b in claves} for i in issues}
    orden = []
    while pendientes:
        listos = sorted(c for c, deps in pendientes.items() if not deps)
        if not listos:
            ciclo = ", ".join(sorted(pendientes))
            raise ValueError(f"there is a block cycle among: {ciclo}")
        for c in listos:
            orden.append(c)
            del pendientes[c]
        for deps in pendientes.values():
            deps.difference_update(listos)
    por_clave = {i["key"]: i for i in issues}
    return [por_clave[c] for c in orden]


def validar(plan, obtener_repo):
    errores, avisos = [], []
    issues = plan.get("issues", [])
    if not issues:
        errores.append("the plan has no issues")
    claves = [i.get("key") for i in issues]
    if any(not c for c in claves):
        errores.append("all issues need a key")
    duplicadas = {c for c in claves if claves.count(c) > 1}
    if duplicadas:
        errores.append(f"repeated keys: {', '.join(sorted(duplicadas))}")

    validos = labels_validos()
    externos = {}
    todos = ([plan["epic"]] if plan.get("epic") else []) + issues
    for i in todos:
        nombre = i.get("key", "epic")
        if not i.get("title"):
            errores.append(f"{nombre}: the title is missing")
        tipos = [l for l in i.get("labels", []) if l.startswith("type:")]
        if len(tipos) != 1:
            errores.append(f"{nombre}: must have exactly one type: label (has {len(tipos)})")
        if validos is not None:
            for l in i.get("labels", []):
                if l not in validos:
                    errores.append(f"{nombre}: the label {l} is not in .github/labels.yml")
        for b in i.get("blocked_by", []):
            if isinstance(b, int):
                if b not in externos:
                    try:
                        externos[b] = gh_json("api", f"repos/{obtener_repo()}/issues/{b}")
                    except RuntimeError:
                        errores.append(f"{nombre}: issue #{b} does not exist")
                        continue
                if externos[b]["state"] != "open":
                    avisos.append(f"{nombre}: #{b} is already closed, that block is not created")
            elif b not in claves:
                errores.append(f"{nombre}: blocked by '{b}', which is not a key of the plan")

    orden = []
    # The cycle is searched for even if there are other errors, to show them all at once.
    if issues and all(claves) and not duplicadas:
        try:
            orden = orden_topologico(issues)
        except ValueError as e:
            errores.append(str(e))
    return orden, externos, errores, avisos


def bloqueantes_abiertos(issue, externos):
    return [b for b in issue.get("blocked_by", [])
            if not isinstance(b, int) or externos[b]["state"] == "open"]


def mostrar_borrador(plan, orden, externos, avisos, asignados):
    def quien(clave):
        return f"  → @{asignados[clave]}" if clave in asignados else "  → unassigned"
    if plan.get("epic"):
        e = plan["epic"]
        print(f"Epic: {e['title']}  [{', '.join(e.get('labels', []))}]{quien('epic')}\n")
    print("Issues, in the order they can be done:\n")
    for n, i in enumerate(orden, 1):
        labels = list(i.get("labels", []))
        bloq = bloqueantes_abiertos(i, externos)
        if bloq and "status:blocked" not in labels:
            labels.append("status:blocked")
        print(f"{n}. [{i['key']}] {i['title']}  [{', '.join(labels)}]{quien(i['key'])}")
        if bloq:
            nombres = [f"#{b}" if isinstance(b, int) else b for b in bloq]
            motivo = f" — {i['reason']}" if i.get("reason") else ""
            print(f"   blocked by: {', '.join(nombres)}{motivo}")
    for a in avisos:
        print(f"\nWarning: {a}")


def crear_issue(repo, titulo, cuerpo, labels, asignado=None):
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
        f.write(cuerpo)
        ruta = f.name
    try:
        args = ["issue", "create", "-R", repo, "--title", titulo, "--body-file", ruta]
        for l in labels:
            args += ["--label", l]
        if asignado:
            args += ["--assignee", asignado]
        url = gh(*args)
    finally:
        os.unlink(ruta)
    numero = int(url.rstrip("/").rsplit("/", 1)[1])
    return numero, url


def firma():
    try:
        return f"\n\n_Opened from the Claude Code chat at the request of @{gh('api', 'user', '-q', '.login')}._"
    except RuntimeError:
        return ""


def crear(plan, orden, externos, repo, asignados):
    creados = {}  # key -> (number, url)
    ids = {}      # number -> internal id
    pie = firma()

    def id_de(numero):
        if numero not in ids:
            ids[numero] = gh_json("api", f"repos/{repo}/issues/{numero}")["id"]
        return ids[numero]

    try:
        epica = None
        if plan.get("epic"):
            e = plan["epic"]
            epica = crear_issue(repo, e["title"], e.get("body", "") + pie, e.get("labels", []),
                                asignados.get("epic"))
            print(f"Epic #{epica[0]}: {epica[1]}")

        for i in orden:
            bloq = bloqueantes_abiertos(i, externos)
            numeros = [b if isinstance(b, int) else creados[b][0] for b in bloq]
            labels = list(i.get("labels", []))
            cuerpo = i.get("body", "")
            if numeros:
                if "status:blocked" not in labels:
                    labels.append("status:blocked")
                motivo = f": {i['reason']}" if i.get("reason") else ""
                cuerpo += f"\n\nBlocked by {', '.join(f'#{n}' for n in numeros)}{motivo}"
            numero, url = crear_issue(repo, i["title"], cuerpo + pie, labels, asignados.get(i["key"]))
            creados[i["key"]] = (numero, url)
            if epica:
                gh("api", f"repos/{repo}/issues/{epica[0]}/sub_issues", "-X", "POST",
                   "-F", f"sub_issue_id={id_de(numero)}")
            for n in numeros:
                gh("api", f"repos/{repo}/issues/{numero}/dependencies/blocked_by", "-X", "POST",
                   "-F", f"issue_id={id_de(n)}")
            extra = f" (blocked by {', '.join(f'#{n}' for n in numeros)})" if numeros else ""
            quien = f" → @{asignados[i['key']]}" if i["key"] in asignados else ""
            print(f"#{numero} {i['title']}{extra}{quien}: {url}")
    except RuntimeError as err:
        print(f"\nError: {err}", file=sys.stderr)
        if creados:
            hechos = ", ".join(f"#{n}" for n, _ in creados.values())
            print(f"These were created before the failure: {hechos}. Review them before retrying.", file=sys.stderr)
        sys.exit(1)


def main():
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        print(__doc__)
        sys.exit(2)
    borrador = "--draft" in args
    try:
        with open(args[0]) as f:
            plan = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"Could not read the plan {args[0]}: {e}", file=sys.stderr)
        sys.exit(1)

    # GitHub is queried only if needed: external issues in blocked_by, or when creating.
    repo_cache = []

    def obtener_repo():
        if not repo_cache:
            try:
                repo_cache.append(args[args.index("--repo") + 1] if "--repo" in args else
                                  gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"))
            except RuntimeError as e:
                print(f"Could not identify the GitHub repo ({e}). Pass --repo owner/repo.", file=sys.stderr)
                sys.exit(1)
        return repo_cache[0]

    orden, externos, errores, avisos = validar(plan, obtener_repo)
    if errores:
        print("The plan is not valid:", file=sys.stderr)
        for e in errores:
            print(f"- {e}", file=sys.stderr)
        sys.exit(1)
    asignados = responsables(plan, orden)
    if borrador:
        mostrar_borrador(plan, orden, externos, avisos, asignados)
    else:
        crear(plan, orden, externos, obtener_repo(), asignados)


if __name__ == "__main__":
    main()
