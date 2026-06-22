---
estado: Completed
tipo: task
---
# T018: Agrupar PRs de Dependabot para acciones menores

**Outcome**: [O01 Sanitize CI reusables](README.md)
**Contribuye a**: reducir amplificación de CI runs por bumps de dependencia (cada dep individual hoy dispara su propio pipeline completo).

## Contexto

`crossbeam/.github/dependabot.yml` configura Dependabot sin `groups:`, generando un PR por dependencia bumpada. Cada PR dispara CI completo (yamllint + actionlint + tests). Sobre 48 runs en 8 días, ~20+ son disparados por Dependabot.

Dependabot soporta `groups:` desde 2023: agrupa varias deps en una sola PR (semanal o mensual) con un solo CI run. Majors quedan separadas (cambio breaking potencial).

## Alcance

**In**:
1. Editar `.github/dependabot.yml` añadiendo `groups:` por ecosystem configurado (github-actions y gomod si aplica), patrón:
   ```yaml
   groups:
     actions-minor-patch:
       update-types: ["minor", "patch"]
   ```
2. Mantener majors fuera del group.

**Out**:
- No cambiar schedule, target-branch, ni reviewers de Dependabot.
- No tocar ecosystems no configurados.

## Estado inicial esperado

- `.github/dependabot.yml` existe sin clave `groups:` en los ecosystems configurados.

## Criterios de Aceptación

- `.github/dependabot.yml` contiene la clave `groups:` con al menos un grupo `minor`+`patch` por ecosystem activo.
- Configuración valida con yaml parser sin errors; actionlint del propio workflow ci no detecta issues.
- Próxima ventana Dependabot abre 1 PR agrupada (validable post-merge observando que la siguiente tanda Dependabot abre 1 PR agrupada en vez de N).

## Fuente de verdad

- `/home/shared/crossbeam/.github/dependabot.yml`
