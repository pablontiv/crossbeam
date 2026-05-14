---
estado: Pending
tipo: task
---
# T010: Add CONTRIBUTING.md specific to crossbeam

**Contribuye a**: provide contributor guidance for crossbeam itself (the existing templates/CONTRIBUTING.md has {{placeholders}} for other repos — crossbeam needs its own guide).

## Alcance

**In**:
- Create `/CONTRIBUTING.md` describing how to contribute to crossbeam:
  - Dev setup (clone, yamllint, actionlint)
  - How to add/modify a reusable workflow
  - How to add/modify a config file
  - Conventional commits convention (feat/fix/docs/chore)
  - Testing: `bash scripts/test-auto-tag.sh`, yamllint, actionlint
  - Versioning: semver, major tag alias `v1`
  - PR process

**Out**:
- No changes to templates/CONTRIBUTING.md

## Criterios de Aceptación

- `test -f /home/shared/crossbeam/CONTRIBUTING.md` passes
- No `{{placeholder}}` strings in the file
- Style consistent with rootline/backscroll CONTRIBUTING (formal, technical, English, tables)
- `git -C /home/shared/crossbeam log --oneline -1` shows a conventional commit

## Fuente de verdad

- /home/shared/crossbeam/CONTRIBUTING.md (new)
- /home/shared/rootline/CONTRIBUTING.md (style reference)
