---
estado: Completed
tipo: task
---
# T004: Agregar CODEOWNERS

**Contribuye a**: Todo PR requiere aprobación explícita de @pablontiv

[[blocked_by:./T001-write-design-spec.md]]

## Preserva

- INV1: Solo @pablontiv puede ser code owner (no agregar otros owners)
  - Verificar: `cat .github/CODEOWNERS` contiene solo `* @pablontiv`

## Contexto

crossbeam es infraestructura compartida de CI/CD. Ningún cambio debería poder mergearse sin revisión del admin. El archivo CODEOWNERS hace que GitHub requiera automáticamente la aprobación de @pablontiv en cualquier PR que modifique cualquier archivo del repo.

CODEOWNERS funciona en conjunto con branch protection (T005): la protección aplica la regla de review requerido, CODEOWNERS define quién debe dar esa review.

## Alcance

**In**:
1. Crear `.github/CODEOWNERS` con el contenido `* @pablontiv`
2. Commitear el archivo

**Out**:
- No configurar branch protection (eso es T005)

## Estado inicial esperado

- `.github/CODEOWNERS` no existe

## Criterios de Aceptación

- `.github/CODEOWNERS` existe con exactamente `* @pablontiv`
- En un PR de prueba, la sección "Reviewers" muestra @pablontiv como required reviewer

## Fuente de verdad

- `.github/CODEOWNERS` (archivo a crear)
