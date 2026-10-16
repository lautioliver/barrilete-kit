---
skill: implement-issue | review-pr | improve-skills | orchestrate
issue: <n> (en review-pr, si el PR no cierra ninguno: "no issue"; en orchestrate, el n° de la épica)
run: <YYYYMMDD-HHMM> (solo orchestrate, si la corrida no es de una épica)
pr: <n o "no PR">
area: <area: del issue, o "none">
paths: <archivos o carpetas principales que tocó, separados por coma>
model: opus | sonnet | haiku (o "unknown")
role: implementer | implementer-light | reviewer | orchestrator | session
---
**Desvíos:** dónde no se siguió la skill y por qué (o "ninguno").
**Decisiones no cubiertas:** qué hubo que decidir que la skill no decía.
**Lo que encontró la revisión:** hallazgos que la implementación no vio — en implement-issue, los de `/code-review` o `/security-review`; en review-pr, los bloqueantes (o "nada").
**Propuesta:** opcional, qué cambiarías.
