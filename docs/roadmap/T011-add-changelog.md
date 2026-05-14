---
estado: Completed
tipo: task
---
# T011: Add CHANGELOG.md

**Contribuye a**: provide a human-readable change history for crossbeam consumers who need to understand what changed between versions.

## Alcance

**In**:
- Create `/CHANGELOG.md` following the format used in backscroll (sections: [Unreleased], then versioned entries with Fixed/Features/Documentation/CI/CD headings)
- Seed with v1.0.0 entry and key workflow additions from git log

**Out**:
- CHANGELOG is not auto-generated; it is maintained manually on release

## Criterios de Aceptación

- `test -f /home/shared/crossbeam/CHANGELOG.md` passes
- Contains an `[Unreleased]` section and at least one versioned entry
- Format consistent with backscroll CHANGELOG.md
- `git -C /home/shared/crossbeam log --oneline -1` shows a conventional commit

## Fuente de verdad

- /home/shared/crossbeam/CHANGELOG.md (new)
- /home/shared/backscroll/CHANGELOG.md (format reference)
