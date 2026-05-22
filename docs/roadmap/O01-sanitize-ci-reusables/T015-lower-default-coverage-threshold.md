---
estado: Specified
tipo: task
---
# T015: Bajar default `coverage-threshold` a 0 en `go-ci.yml`

**Outcome**: [O01 Sanitize CI reusables](README.md)
**Contribuye a**: reducir fallas CI por coverage gate en consumidores que iteran rápido; cobertura real se valida en smoke jobs multi-plataforma del consumidor.

## Preserva

- INV1: consumidores que pasan `coverage-threshold: <N>` explícito mantienen su comportamiento.
  - Verificar: `grep -n "coverage-threshold" .github/workflows/go-ci.yml` muestra el input declarado, no removido.
- INV2: el input sigue siendo opcional aceptando cualquier número ≥ 0.

## Contexto

Hoy el reusable `pablontiv/crossbeam/.github/workflows/go-ci.yml` define `coverage-threshold` con default `85`. Los consumidores (roadmapctl, backscroll, rootline, picokit) heredan ese default si no lo overridean. En fase de desarrollo activo con alta velocidad de push, este gate provoca fallas en cascada y cancelaciones.

El patrón ya validado en roadmapctl (outcome O17 T004 — "Remove crossbeam coverage threshold") bajó este threshold a `0` en la llamada del consumidor y delegó la validación de cobertura a un smoke job multi-plataforma. Esta task propaga ese cambio al default del reusable mismo.

## Alcance

**In**:
1. Editar `.github/workflows/go-ci.yml` para cambiar el default de `coverage-threshold` de `85` a `0`.
2. Actualizar documentación inline (comentario en el input o README/CLAUDE.md) explicando que la cobertura debe gatear en smoke jobs del consumidor.

**Out**:
- No modificar la lógica del check de cobertura cuando `coverage-threshold > 0` (debe seguir funcionando para overrides).
- No tocar `.coverage-floors.toml` ni configs pkcov en consumidores.

## Estado inicial esperado

- `go-ci.yml` tiene `coverage-threshold` con default 85.
- CI de crossbeam pasa antes de empezar.

## Criterios de Aceptación

- El input `coverage-threshold` en `go-ci.yml` declara default 0.
- Una invocación de go-ci.yml sin `coverage-threshold` no falla por threshold (verificable vía dry-run del yaml o test job sin override).
- CI de crossbeam (actionlint + yamllint + tests) pasa post-push: `gh run list --repo pablontiv/crossbeam --limit 3` retorna `conclusion=success`.

## Fuente de verdad

- `/home/shared/crossbeam/.github/workflows/go-ci.yml`
- `/home/shared/crossbeam/CLAUDE.md` (sección Workflows, columna Key Inputs)
