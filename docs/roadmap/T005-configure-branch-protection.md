---
estado: Specified
tipo: task
---
# T005: Configurar branch protection en master

**Contribuye a**: Solo el admin puede mergear cambios; nadie puede pushear directo a master

[[blocked_by:./T003-add-self-ci-workflow.md]]
[[blocked_by:./T004-add-codeowners.md]]

## Preserva

- INV1: `enforce_admins=false` para que el admin pueda hacer override de emergencia
  - Verificar: la regla no tiene `enforce_admins: true`

## Contexto

Los jobs `lint` y `test` de ci.yml (T003) y el CODEOWNERS (T004) deben estar activos antes de configurar branch protection, ya que la regla referencia los status checks por nombre (`lint`, `test`) y el review requerido por CODEOWNERS.

El comando `gh api` aplica la regla directamente via GitHub API sin necesidad de UI.

## Alcance

**In**:
1. Aplicar branch protection rule en `master` via `gh api`:
   - `required_status_checks`: strict=true, contexts=["lint","test"]
   - `required_pull_request_reviews`: 1 aprobación, require_code_owner_reviews=true, dismiss_stale_reviews=true
   - `restrictions`: null (no restricción de quién puede abrir PRs)
   - `enforce_admins`: false

**Out**:
- No modificar archivos del repo
- No cambiar otros branches

## Estado inicial esperado

- ci.yml mergeado y jobs `lint`+`test` corrieron al menos una vez (para que GitHub los reconozca como status checks)
- `.github/CODEOWNERS` existe y está mergeado

## Criterios de Aceptación

- Push directo a master bloqueado: `git push origin master` rechazado con error de branch protection
- PR sin aprobación de @pablontiv no se puede mergear
- PR sin que pasen `lint` y `test` no se puede mergear
- `gh api repos/pablontiv/crossbeam/branches/master/protection` retorna la regla configurada

## Fuente de verdad

- GitHub API: `gh api repos/pablontiv/crossbeam/branches/master/protection`

## Comando de aplicación

```bash
gh api repos/pablontiv/crossbeam/branches/master/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["lint","test"]}' \
  --field enforce_admins=false \
  --field required_pull_request_reviews='{"required_approving_review_count":1,"require_code_owner_reviews":true,"dismiss_stale_reviews":true}' \
  --field restrictions=null
```
