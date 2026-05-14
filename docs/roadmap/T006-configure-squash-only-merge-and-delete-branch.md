---
estado: Pending
tipo: task
---
# T006: Configure squash-only merge and delete branch on merge

**Contribuye a**: align crossbeam GitHub repo settings with the ecosystem standard (squash-only, auto-delete merged branches).

## Alcance

**In**:
- Set `squashMergeAllowed: true`, `mergeCommitAllowed: false`, `rebaseMergeAllowed: false` via GitHub API
- Set `deleteBranchOnMerge: true` via GitHub API

**Out**:
- No file changes in the repo

## Criterios de Aceptación

- `gh repo view pablontiv/crossbeam --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed,deleteBranchOnMerge` returns `{"squashMergeAllowed":true,"mergeCommitAllowed":false,"rebaseMergeAllowed":false,"deleteBranchOnMerge":true}`

## Fuente de verdad

- GitHub API: PATCH repos/pablontiv/crossbeam
