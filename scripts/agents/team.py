#!/usr/bin/env python3
"""Project team (.github/team.json) and who to assign each issue to.

Usage:
  team.py list
  team.py add <login> [--name "Name"] [--areas area:api,area:docs] [--force]
                                 # adds or edits; validates the user and their access to the repo
  team.py remove <login>
  team.py pause <login>        # stops receiving issues (vacation, other priority)
  team.py activate <login>
  team.py suggest [--labels type:bug,area:api] [--load ana=2,bruno=0]
                                 # prints the login to assign, or nothing if there is no team

Assignment rule (elegir): among the active members, the ones that cover some area: of the
issue; if nobody covers it (or the issue has no area:), all the active ones.
The one with the fewest open assigned issues wins; on a tie, the first in the file.
"""
import json
import os
import subprocess
import sys

RAIZ = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
ARCHIVO = os.path.join(RAIZ, ".github", "team.json")
AYUDA = ("Team members to assign issues to. Only the scripts that create issues read it "
         "(create-issue, planner.py). Edit it with /add-member and /remove-member "
         "(scripts/agents/team.py). areas: area: labels from .github/labels.yml that each one covers.")


def elegir(integrantes, labels, carga):
    activos = [i for i in integrantes if i.get("active", True)]
    if not activos:
        return None
    areas = {l for l in labels if l.startswith("area:")}
    del_area = [i for i in activos if areas & set(i.get("areas", []))]
    candidatos = del_area or activos
    # min() is stable: on a tie the first in the file stays.
    return min(candidatos, key=lambda i: carga.get(i["login"], 0))["login"]


def salir(msg, codigo=1):
    print(f"team.py: {msg}", file=sys.stderr)
    sys.exit(codigo)


def gh(*args):
    return subprocess.run(["gh", *args], capture_output=True, text=True)


def leer():
    if not os.path.exists(ARCHIVO):
        return {"_help": AYUDA, "members": []}
    return json.load(open(ARCHIVO, encoding="utf-8"))


def guardar(datos):
    os.makedirs(os.path.dirname(ARCHIVO), exist_ok=True)
    with open(ARCHIVO, "w", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False, indent=2)
        f.write("\n")


def areas_validas():
    ruta = os.path.join(RAIZ, ".github", "labels.yml")
    if not os.path.exists(ruta):
        return None
    nombres = set()
    for linea in open(ruta, encoding="utf-8"):
        linea = linea.strip()
        if linea.startswith("- name:"):
            nombres.add(linea.split(":", 1)[1].strip().strip('"').strip("'"))
    return {n for n in nombres if n.startswith("area:")}


def opcion(args, nombre):
    if nombre in args:
        i = args.index(nombre)
        if i + 1 >= len(args):
            salir(f"missing value for {nombre}")
        return args[i + 1]
    return None


def carga_actual(logins):
    """Open issues assigned to each one (the load that balances the assignment)."""
    repo = gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").stdout.strip()
    carga = {}
    for login in logins:
        r = gh("issue", "list", "-R", repo, "--state", "open", "--assignee", login,
               "--limit", "500", "--json", "number", "-q", "length")
        carga[login] = int(r.stdout.strip() or 0) if r.returncode == 0 else 0
    return carga


def cmd_listar(datos):
    integrantes = datos["members"]
    if not integrantes:
        print("The team is empty. Add members with /add-member.")
        return
    carga = carga_actual([i["login"] for i in integrantes])
    for i in integrantes:
        estado = "active" if i.get("active", True) else "paused"
        areas = ", ".join(i.get("areas", [])) or "all"
        print(f"- @{i['login']} ({i.get('name') or 'no name'}) · {estado} · areas: {areas} · "
              f"{carga[i['login']]} open issue(s)")


def cmd_agregar(datos, args):
    if not args or args[0].startswith("--"):
        salir("usage: team.py add <login> [--name N] [--areas a,b] [--force]")
    login = args[0].lstrip("@")
    if gh("api", f"users/{login}", "-q", ".login").returncode != 0:
        salir(f"the GitHub user @{login} does not exist.")
    repo = gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").stdout.strip()
    if gh("api", f"repos/{repo}/collaborators/{login}").returncode != 0 and "--force" not in args:
        salir(f"@{login} has no access to {repo}: GitHub does not allow assigning issues to them. "
              "Invite them first (or use --force if the invitation is pending).")
    areas = opcion(args, "--areas")
    lista = [a.strip() for a in areas.split(",") if a.strip()] if areas else None
    if lista is not None:
        validas = areas_validas()
        malas = [a for a in lista if not a.startswith("area:") or (validas is not None and a not in validas)]
        if malas:
            salir(f"areas that are not in .github/labels.yml: {', '.join(malas)}. "
                  f"Valid: {', '.join(sorted(validas or [])) or 'none'}.")
    existente = next((i for i in datos["members"] if i["login"].lower() == login.lower()), None)
    if existente:
        if opcion(args, "--name") is not None:
            existente["name"] = opcion(args, "--name")
        if lista is not None:
            existente["areas"] = lista
        print(f"Updated @{login}.")
    else:
        datos["members"].append({
            "login": login, "name": opcion(args, "--name") or "", "areas": lista or [], "active": True,
        })
        print(f"Added @{login}.")
    guardar(datos)


def buscar(datos, login):
    login = login.lstrip("@").lower()
    i = next((i for i in datos["members"] if i["login"].lower() == login), None)
    if not i:
        salir(f"@{login} is not in the team.")
    return i


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    cmd, resto = args[0], args[1:]
    datos = leer()
    datos.setdefault("_help", AYUDA)
    datos.setdefault("members", [])

    if cmd == "list":
        cmd_listar(datos)
    elif cmd == "add":
        cmd_agregar(datos, resto)
    elif cmd in ("remove", "pause", "activate"):
        if not resto:
            salir(f"usage: team.py {cmd} <login>")
        i = buscar(datos, resto[0])
        if cmd == "remove":
            datos["members"].remove(i)
        else:
            i["active"] = cmd == "activate"
        guardar(datos)
        print({"remove": "Removed", "pause": "Paused", "activate": "Activated"}[cmd] + f" @{i['login']}.")
        if cmd == "remove":
            print("Their open issues are still assigned: reassign them if needed "
                  f"(gh issue list --assignee {i['login']}).")
    elif cmd == "suggest":
        labels = [l for l in (opcion(resto, "--labels") or "").split(",") if l]
        integrantes = datos["members"]
        if opcion(resto, "--load") is not None:
            carga = {k: int(v) for k, v in (p.split("=") for p in opcion(resto, "--load").split(",") if p)}
        else:
            carga = carga_actual([i["login"] for i in integrantes if i.get("active", True)])
        elegido = elegir(integrantes, labels, carga)
        if elegido:
            print(elegido)
    else:
        salir(f"unknown command: {cmd}", 2)


if __name__ == "__main__":
    main()
