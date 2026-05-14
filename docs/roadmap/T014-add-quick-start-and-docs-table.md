---
estado: Completed
tipo: task
---
# T014: Add Quick Start and Documentation table to README

**Contribuye a**: reach narrative parity with the rest of the ecosystem — rootline, backscroll, and roadmapctl all have Quick Start and Documentation sections; crossbeam does not. Also remove the Status callout from all 4 repos.

## Alcance

**In**:
- Add `## Quick Start` section before Core Idea in crossbeam README (numbered YAML workflow stubs with inline comments)
- Add `## Documentation` table linking to actual workflow files and config directories
- Update ToC to include Quick Start and Documentation
- Remove `> **Status**: ...` callout from crossbeam, rootline, backscroll, and roadmapctl READMEs

**Out**:
- No changes to workflows, configs, or templates

## Criterios de Aceptación

- `grep "## Quick Start" /home/shared/crossbeam/README.md` exits 0
- `grep "## Documentation" /home/shared/crossbeam/README.md` exits 0
- `grep "> \*\*Status\*\*" /home/shared/crossbeam/README.md` returns empty
- `grep "> \*\*Status\*\*" /home/shared/rootline/README.md` returns empty
- `grep "> \*\*Status\*\*" /home/shared/backscroll/README.md` returns empty
- `grep "> \*\*Status\*\*" /home/shared/roadmapctl/README.md` returns empty

## Fuente de verdad

- /home/shared/crossbeam/README.md
- /home/shared/rootline/README.md (Quick Start style reference)
