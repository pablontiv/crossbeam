---
estado: Completed
tipo: task
---
# T016: Eliminar workflow Scorecard del set de reusables

**Outcome**: [O01 Sanitize CI reusables](README.md)
**Contribuye a**: eliminar la fuente #1 de ruido CI (100% startup_failure en roadmapctl, 67% backscroll, 50% rootline; 4 fixes de emergencia en 48h en rootline por API churn).

## Preserva

- INV1: CodeQL sigue disponible como workflow reusable independiente.
- INV2: rootline mantiene scorecard inlined localmente por restricciones de permissions; esta task no toca esa copia (es responsabilidad de `rootline/T005`).

## Contexto

`scorecard.yml` en crossbeam es un wrapper que llama a `ossf/scorecard-action`. En los repos consumidores, la tasa de `startup_failure` va de 50% a 100% por SHAs inestables, permisos (`read-all` vs `security-events: write`), y network/proxy flaky.

Cero alertas accionables se han generado por este workflow. Decisión: eliminarlo del set reusable.

## Alcance

**In**:
1. Eliminar `.github/workflows/scorecard.yml` del repo crossbeam.
2. Actualizar `crossbeam/CLAUDE.md` tabla "Workflows" para remover la fila scorecard.yml.
3. Documentar el cambio en commit message con data: failure rate y emergency-fix count.

**Out**:
- No tocar la copia inline en rootline.
- No modificar CodeQL ni gitleaks.

## Estado inicial esperado

- `.github/workflows/scorecard.yml` existe en crossbeam.
- `CLAUDE.md` lista scorecard.yml en la tabla de workflows.

## Criterios de Aceptación

- `ls .github/workflows/scorecard.yml` retorna "No such file or directory".
- `grep -E '^\| *scorecard\.yml' CLAUDE.md` retorna 0 matches (sin fila activa en la tabla; sí permitido en histórico/decisiones).
- `actionlint` y `yamllint` siguen pasando sobre los workflows restantes.

## Fuente de verdad

- `/home/shared/crossbeam/.github/workflows/scorecard.yml`
- `/home/shared/crossbeam/CLAUDE.md`
- `/home/shared/crossbeam/README.md` (si lista workflows)
