---
estado: Specified
tipo: task
---
# T002: Activar Dependabot para GitHub Actions

**Contribuye a**: SHAs de Actions se actualizan automáticamente cada semana

[[blocked_by:./T001-write-design-spec.md]]

## Preserva

- INV1: Todos los commits deben usar conventional commits
  - Verificar: el prefix configurado en dependabot.yml es `chore(deps):`

## Contexto

crossbeam tiene SHAs de GitHub Actions pinned en sus workflows. El problema de SHA stale de `ghaction-import-gpg` (fix en commit 4df269d) demostró que los SHAs se quedan obsoletos silenciosamente. Dependabot detecta nuevas versiones y abre PRs automáticos.

Ya existe un template en `templates/dependabot/actions-only.yml` que es exactamente lo que se necesita.

## Alcance

**In**:
1. Crear `.github/dependabot.yml` copiando el contenido de `templates/dependabot/actions-only.yml`
2. Commitear el archivo

**Out**:
- No modificar el template original en `templates/dependabot/`
- No configurar Dependabot para otros ecosistemas (go, cargo)

## Estado inicial esperado

- `templates/dependabot/actions-only.yml` existe con el contenido correcto
- `.github/dependabot.yml` no existe

## Criterios de Aceptación

- `.github/dependabot.yml` existe con `package-ecosystem: github-actions`, `interval: weekly`, prefix `chore(deps):`
- `cat templates/dependabot/actions-only.yml` y `cat .github/dependabot.yml` tienen el mismo contenido

## Fuente de verdad

- `templates/dependabot/actions-only.yml` (fuente a copiar)
- `.github/dependabot.yml` (archivo a crear)
