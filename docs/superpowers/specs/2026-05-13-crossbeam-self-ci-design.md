# crossbeam — Self-CI, Dependabot y Branch Protection

**Fecha:** 2026-05-13
**Estado:** Aprobado

## Contexto

crossbeam sufrió dos fallas recientes:
1. El repo era privado → GitHub bloqueaba que repos públicos consumidores llamaran sus reusable workflows.
2. SHA de `crazy-max/ghaction-import-gpg` obsoleto → fallas en release jobs aunque signing estuviera desactivado.

Ambas se detectaron tarde porque crossbeam no tenía CI propio ni actualizaciones automatizadas. Adicionalmente, el repo necesita protección explícita para que solo el admin pueda mergear cambios.

**Objetivo:** crossbeam valida sus propios workflows en cada push/PR, Dependabot mantiene los SHAs frescos, y las branch protection rules aseguran que ningún cambio entra sin aprobación del admin.

---

## Alcance — 4 entregables

### 1. `.github/dependabot.yml`

Copia directa del template existente en `templates/dependabot/actions-only.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    commit-message:
      prefix: "chore(deps):"
```

Dependabot abre PRs automáticos semanales con SHAs actualizados. Cada PR pasa por ci.yml antes de que el admin lo mergee.

### 2. `.github/workflows/ci.yml`

Triggers: `push` a `master`, `pull_request` targeting `master`.

Dos jobs paralelos:

**`lint`:**
- `actions/checkout` (SHA-pinned)
- Instalar y correr `actionlint` — valida semántica de GH Actions (tipos, contextos, expresiones)
- Instalar y correr `yamllint` sobre `.github/workflows/`

**`test`:**
- `actions/checkout` (SHA-pinned)
- `bash scripts/test-auto-tag.sh` — script ya existente, 30+ casos del algoritmo de versioning, solo necesita bash + git (disponibles en ubuntu-latest)

Todas las Actions usadas en ci.yml deben estar SHA-pinned (Dependabot las mantendrá).

### 3. `.github/CODEOWNERS`

```
* @pablontiv
```

Cualquier PR requiere aprobación explícita de `@pablontiv` antes de poder mergearse.

### 4. Branch protection rule en `master`

Aplicar vía `gh api` (una vez tras el merge del PR):

```bash
gh api repos/pablontiv/crossbeam/branches/master/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["lint","test"]}' \
  --field enforce_admins=false \
  --field required_pull_request_reviews='{"required_approving_review_count":1,"require_code_owner_reviews":true,"dismiss_stale_reviews":true}' \
  --field restrictions=null
```

Efecto combinado:
- No push directo a master — todo via PR
- `lint` y `test` de ci.yml deben pasar antes de merge
- 1 aprobación de code owner (`@pablontiv`) requerida
- `enforce_admins=false` → admin puede hacer bypass de emergencia si es necesario

---

## Flujo resultante

```
push/PR → ci.yml → lint (actionlint + yamllint)
                 → test (auto-tag script)
                 → ambos deben pasar
                 → @pablontiv aprueba
                 → merge habilitado

semana → Dependabot abre PR con SHAs actualizados
       → ci.yml valida automáticamente
       → @pablontiv revisa y mergea
```

---

## Archivos a crear/modificar

| Archivo | Acción |
|---------|--------|
| `.github/dependabot.yml` | Crear (copiar de `templates/dependabot/actions-only.yml`) |
| `.github/workflows/ci.yml` | Crear |
| `.github/CODEOWNERS` | Crear |
| Branch protection `master` | Configurar vía `gh api` post-merge |

Archivos de referencia:
- `templates/dependabot/actions-only.yml` — template a copiar para dependabot.yml
- `scripts/test-auto-tag.sh` — script existente a invocar en job `test`
- `.github/workflows/go-ci.yml` — referencia de estilo y SHA-pinning existente

---

## Verificación

1. Abrir un PR de prueba con un cambio mínimo → ci.yml debe correr y pasar ambos jobs
2. Verificar que el PR no se puede mergear sin aprobación de `@pablontiv`
3. Verificar que push directo a master está bloqueado
4. Esperar el primer ciclo semanal de Dependabot (o triggerearlo manualmente) → debe abrir PR con SHA updates
5. Verificar que el PR de Dependabot pasa ci.yml antes de estar disponible para merge
