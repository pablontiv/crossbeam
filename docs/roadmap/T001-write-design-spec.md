---
estado: Specified
tipo: task
---
# T001: Escribir spec de diseño

**Contribuye a**: Documentar el diseño acordado antes de implementar

## Preserva

- INV1: El directorio `docs/superpowers/specs/` es la ubicación canónica de specs de diseño
  - Verificar: `ls docs/superpowers/specs/2026-05-13-crossbeam-self-ci-design.md`

## Contexto

Durante una sesión de brainstorming se diseñó un plan para que crossbeam tenga su propio CI (lint + test), actualizaciones automáticas de SHAs via Dependabot, y protección de rama. El diseño fue aprobado pero el spec nunca se escribió al archivo canónico porque el usuario pasó directamente a `/roadmap plan`.

El plan de referencia está en `/home/pones/.claude/plans/tuvimos-problemas-recientes-con-memoized-dewdrop.md`.

## Alcance

**In**:
1. Crear `docs/superpowers/specs/2026-05-13-crossbeam-self-ci-design.md` con el contenido del plan de referencia adaptado a formato spec
2. Commitear el archivo

**Out**:
- No implementar ningún archivo de workflow ni config

## Estado inicial esperado

- El plan de referencia existe en `/home/pones/.claude/plans/tuvimos-problemas-recientes-con-memoized-dewdrop.md`

## Criterios de Aceptación

- `docs/superpowers/specs/2026-05-13-crossbeam-self-ci-design.md` existe y está commiteado
- El spec cubre los 4 entregables: dependabot.yml, ci.yml (lint+test), CODEOWNERS, branch protection

## Fuente de verdad

- `/home/pones/.claude/plans/tuvimos-problemas-recientes-con-memoized-dewdrop.md`
- `docs/superpowers/specs/` (directorio destino)
