---
skill: implement-issue
issue: 218
pr: 240
area: agents
paths: profiles/small/AGENTS.md, profiles/small/AGENTS.es.md
date: 2026-11-04
skill_sha: 09798fd35d4d278d6c4a88b01cc3b7f4b9f9430c
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** none. Segunda ronda de correcciones sobre un PR existente: sin tests nuevos (`no tests:` del PR sigue valiendo, es texto de docs). No corrí `/code-review` de nuevo: el cambio son dos frases y la review ya había dado 0 hallazgos.
**Decisions not covered:** el skill no dice cómo retomar un PR existente (qué hacer con el cuerpo, con el red block). Edité el cuerpo con `gh pr edit --body-file` conservando el resto. También: `verify.py` tarda ~15 min (i18n 909 s) y supera el timeout de 10 min de Bash; hay que correrlo en background.
**What the review found:** el "en el kit" era falso (el perfil chico instala `docs/decisions/kit/`) y la tabla de contextos nunca está literalmente vacía, empieza con una fila `TODO`. El implementer anterior afirmó en el cuerpo del PR que el perfil no instala `docs/decisions/` sin verificarlo contra `test-init.sh`. Mi primer `sed` falló por error de sintaxis (dos archivos en `sed -n`, y un `sed -i` encadenado con `&&` no llegó a correr); lo detecté porque releí el resultado antes de seguir.
**Proposal:** en implement-issue, antes de afirmar en el PR qué instala un perfil, verificarlo contra `scripts/test-init.sh`; y avisar que `verify.py` excede el timeout de Bash.
