---
estado: Completed
tipo: task
---
# T013: Merge de los 4 dep bumps con CI verde

**Contribuye a**: Mantener dependencias de CI actualizadas

## Contexto

4 PRs de Dependabot con CI verde (Test + Lint):
- PR #1: dtolnay/rust-toolchain hash bump
- PR #2: goreleaser/goreleaser-action 6.1→7.2
- PR #3: actions/setup-go 6.3→6.4
- PR #4: actions/attest-build-provenance 2.3→4.1 (v4 es reescritura como wrapper, documentada en release notes)

## Alcance

**In**:
1. `gh pr merge 1 --repo pablontiv/crossbeam --merge`
2. `gh pr merge 2 --repo pablontiv/crossbeam --merge`
3. `gh pr merge 3 --repo pablontiv/crossbeam --merge`
4. `gh pr merge 4 --repo pablontiv/crossbeam --merge`
5. `git -C /home/shared/crossbeam pull --rebase origin master`

**Out**:
- No modificar workflows más allá del merge

## Estado inicial esperado

- PRs #1-4 abiertos, todos con CI verde

## Criterios de Aceptación

- `gh pr list --repo pablontiv/crossbeam --state open` retorna 0 PRs
- `git -C /home/shared/crossbeam log --oneline -4` muestra los 4 merges

## Fuente de verdad

- `gh pr list --repo pablontiv/crossbeam --state open --json number,statusCheckRollup`
