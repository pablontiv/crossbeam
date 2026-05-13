---
estado: Specified
tipo: task
---
# T003: Agregar workflow de CI propio de crossbeam

**Contribuye a**: crossbeam valida sus propios workflows en cada push/PR

[[blocked_by:./T001-write-design-spec.md]]

## Preserva

- INV1: Todas las Actions referenciadas deben estar SHA-pinned
  - Verificar: ningún `uses:` en `.github/workflows/ci.yml` usa tag `@v*` o `@main`
- INV2: El script de tests existente no debe ser modificado
  - Verificar: `git diff HEAD scripts/test-auto-tag.sh` sin cambios

## Contexto

Todos los workflows en crossbeam usan solo `workflow_call` (son reusable, llamados por otros repos). El repo no tiene CI propio. Para detectar errores de sintaxis y semántica antes de que afecten a consumidores, se agrega un workflow `ci.yml` con dos jobs:

- `lint`: valida todos los workflows con `actionlint` (semántica de GH Actions) y `yamllint` (YAML general)
- `test`: ejecuta `scripts/test-auto-tag.sh` que ya existe con 30+ casos de test del algoritmo de versioning

El job `test` solo necesita `bash` y `git`, disponibles en `ubuntu-latest` sin setup adicional.

## Alcance

**In**:
1. Crear `.github/workflows/ci.yml` con:
   - Triggers: `push` a `master`, `pull_request` targeting `master`
   - Job `lint`: checkout + actionlint + yamllint sobre `.github/workflows/`
   - Job `test`: checkout + `bash scripts/test-auto-tag.sh`
   - Todas las Actions SHA-pinned
2. Commitear el archivo

**Out**:
- No modificar workflows existentes en `.github/workflows/`
- No agregar pasos de build/compilación

## Estado inicial esperado

- `.github/workflows/ci.yml` no existe
- `scripts/test-auto-tag.sh` existe y pasa localmente: `bash scripts/test-auto-tag.sh`

## Criterios de Aceptación

- `.github/workflows/ci.yml` existe con jobs `lint` y `test`
- `actionlint .github/workflows/ci.yml` pasa sin errores (verificar localmente si actionlint está disponible)
- Los jobs `lint` y `test` pasan en GitHub Actions en el primer trigger tras merge
- Ningún `uses:` en ci.yml usa tag flotante (verificar con `grep 'uses:.*@v' .github/workflows/ci.yml`)

## Fuente de verdad

- `.github/workflows/ci.yml` (archivo a crear)
- `scripts/test-auto-tag.sh` (script a invocar, no modificar)
- `.github/workflows/go-ci.yml` (referencia de estilo y SHA-pinning existente)
