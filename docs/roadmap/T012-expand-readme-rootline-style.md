---
estado: Completed
tipo: task
---
# T012: Expand README to rootline narrative style

**Contribuye a**: align crossbeam documentation with the ecosystem baseline — rootline's README structure is the canonical reference.

## Alcance

**In**:
- Add CI + PolyForm NC badges
- Add Status callout
- Add Core Idea section (shared workflow library concept, SHA propagation, inheritance model)
- Add AI-Native section (crossbeam as security/release layer for AI-native tools)
- Fix `## License` section: "MIT" → PolyForm Noncommercial 1.0.0
- Remove stale consumers from `rust-ci.yml` and `rust-release.yml` (backscroll migrated to Go)
- Preserve existing Usage and Versioning sections

**Out**:
- No changes to workflows, configs, or templates

## Criterios de Aceptación

- `grep "## Core Idea" /home/shared/crossbeam/README.md` exits 0
- `grep "## AI-Native" /home/shared/crossbeam/README.md` exits 0
- `grep "PolyForm" /home/shared/crossbeam/README.md` exits 0 (license section coherent)
- `grep "backscroll" /home/shared/crossbeam/README.md | grep rust-ci` returns empty
- `git -C /home/shared/crossbeam log --oneline -1` shows a conventional commit

## Fuente de verdad

- /home/shared/crossbeam/README.md
- /home/shared/rootline/README.md (style reference)
