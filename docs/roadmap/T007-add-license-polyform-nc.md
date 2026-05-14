---
estado: Pending
tipo: task
---
# T007: Add LICENSE file (PolyForm Noncommercial 1.0.0)

**Contribuye a**: establish the ecosystem-wide PolyForm Noncommercial 1.0.0 license on crossbeam (currently only mentioned as "MIT" in README with no LICENSE file).

## Alcance

**In**:
- Create `/LICENSE` with PolyForm Noncommercial 1.0.0 full text, copyright "2026 Pablo Ontiveros"
- Update README.md License section to reference the LICENSE file and use the PolyForm NC badge

**Out**:
- No changes to workflow YAML or configs

## Criterios de Aceptación

- `test -f /home/shared/crossbeam/LICENSE` passes
- LICENSE contains "PolyForm Noncommercial License 1.0.0"
- README License section links to LICENSE and says "PolyForm Noncommercial 1.0.0"
- `git -C /home/shared/crossbeam log --oneline -1` shows a conventional commit

## Fuente de verdad

- /home/shared/crossbeam/LICENSE (new)
- /home/shared/crossbeam/README.md
