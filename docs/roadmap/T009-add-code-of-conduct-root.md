---
estado: Pending
tipo: task
---
# T009: Add CODE_OF_CONDUCT.md to repo root

**Contribuye a**: expose the ecosystem code of conduct at the crossbeam root (currently only in templates/ for consumers).

## Alcance

**In**:
- Copy `templates/CODE_OF_CONDUCT.md` to `/CODE_OF_CONDUCT.md` (it adopts Contributor Covenant v2.1, no placeholders)

**Out**:
- No changes to templates/CODE_OF_CONDUCT.md

## Criterios de Aceptación

- `test -f /home/shared/crossbeam/CODE_OF_CONDUCT.md` passes
- File adopts Contributor Covenant v2.1
- `git -C /home/shared/crossbeam log --oneline -1` shows a conventional commit

## Fuente de verdad

- /home/shared/crossbeam/CODE_OF_CONDUCT.md (new)
- /home/shared/crossbeam/templates/CODE_OF_CONDUCT.md (source)
