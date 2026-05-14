---
estado: Completed
tipo: task
---
# T008: Add SECURITY.md to repo root

**Contribuye a**: expose a security policy specific to crossbeam at the repo root (currently only exists in templates/ for other repos to use).

## Alcance

**In**:
- Create `/SECURITY.md` with crossbeam-specific scope (reusable workflows, config files, secret scanning via gitleaks, SHA-pinned actions)
- Reporting: private GitHub advisory + email, 48h ACK / 7d response SLA

**Out**:
- No changes to templates/SECURITY.md (it remains a template for consumers)

## Criterios de Aceptación

- `test -f /home/shared/crossbeam/SECURITY.md` passes
- SECURITY.md describes crossbeam scope (workflows, SHA pinning, sops-guard)
- SECURITY.md instructs reporters to NOT open public issues
- `git -C /home/shared/crossbeam log --oneline -1` shows a conventional commit

## Fuente de verdad

- /home/shared/crossbeam/SECURITY.md (new)
- /home/shared/crossbeam/templates/SECURITY.md (reference for structure, not for crossbeam itself)
