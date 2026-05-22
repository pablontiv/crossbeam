---
tipo: outcome
---
# Sanitize CI reusables — eliminar Scorecard, ajustar coverage default, alinear lint

Reducir la tasa de fallas de CI en los 5 repos del ecosistema (roadmapctl, crossbeam, backscroll, rootline, picokit) desde ~40-67% actual a <15%, sin perder las capacidades de detección que sí están funcionando (smoke multi-plataforma, CodeQL, gitleaks, releases automáticos).

## Contexto

Investigación cuantitativa (ver `/home/pones/.claude/plans/tenemos-multiples-incluso-cientos-sprightly-valley.md`) reveló que la fricción de CI/CD en el ecosistema viene de 3 fuentes concretas y removibles desde crossbeam:

1. **OpenSSF Scorecard** roto en 4/5 repos consumidores (100% startup_failure en roadmapctl, 67% en backscroll, 50% en rootline; 4 fixes de emergencia en 48h en rootline). Cero alertas accionables hasta la fecha.
2. **Coverage gate 85% default** en `go-ci.yml` reusable. Choca con iteración rápida; el patrón roadmapctl O17 (coverage en smoke jobs multi-plataforma) ya validado pero no propagado.
3. **Reglas yamllint vs actionlint contradictorias** en el propio repo (yamllint=160 chars, actionlint=80) — provocan ~5 de 9 fallas internas de CI.

Cambio adicional: agrupar PRs de Dependabot (minor/patch) para reducir amplificación de CI runs por bump.

Outcome buscado: una PR única en crossbeam publicada como `v2`, que permita a los 4 consumidores bumpear + remover scorecard local en PRs mecánicas chicas (tasks `roadmapctl/T037`, `backscroll/O17/T020`, `rootline/T005`, `picokit/T001`).
