---
source: pablontiv/crossbeam
name: crossbeam
description: |
  Auditar y estandarizar la infraestructura de un repositorio contra los
  estándares de crossbeam: workflows reusables, seguridad, git hooks, CI/CD,
  versionado, y configuración. Verifica que los repos usen crossbeam@v1
  caller stubs en lugar de workflows inline. Usar este skill siempre que
  el usuario diga "estandarizar", "conform", "crossbeam audit", "preparar
  repo", "harden", "security audit", "add git hooks", "setup CI",
  "standardize", "conventional commits", "auto-tag", "hacer público",
  "preparar para open source", "revisar seguridad del repo", "endurecer",
  "public release checklist", "verificar estándares", "check standards",
  "migrate to crossbeam" — incluso si no dice "crossbeam" e incluso si
  solo pregunta "está listo?" o "what do I need before open-sourcing?" o
  "estandarizar este repo".
  (No para: pentesting, vulnerability research, code review de lógica.)
user-invocable: true
argument-hint: "[--audit-only] [--apply] [--component hooks|ci|security|config]"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /crossbeam — Repository Standards Audit & Remediation

Audits repos against the pablontiv crossbeam infrastructure standards. Verifies that shared workflows, security scanning, configs, and hooks are correctly configured. Replaces inline CI/CD with crossbeam reusable workflow caller stubs.

## Routing

Parse `$ARGUMENTS`:

| Input | Mode | Behavior |
|-------|------|----------|
| (empty) | **audit + apply** | Audit, show report, apply fixes with confirmation |
| `--audit-only` | **audit** | Only show the report, don't touch anything |
| `--apply` | **apply** | Audit and apply without individual confirmations (still confirms gh api) |
| `--component X` | **filtered** | Only audit/apply checks for component X (hooks, ci, security, config) |

## Dependencies

### Required: gh CLI

**Needed for**: branch protection, repo settings, secret scanning verification.
**NOT needed for**: file-based checks (CI, hooks, governance, dependabot).

Gate check:
```bash
command -v gh && gh auth status
```
If unavailable, skip GitHub API checks and note them as "unable to verify".

### Optional: gitleaks

```bash
command -v gitleaks
```
If unavailable, note and continue.

### Optional: rootline

```bash
command -v rootline
```
If unavailable, skip docs-related checks.

## Crossbeam Reference

This skill uses two sources of truth:

1. **Crossbeam repo files** — the actual workflow YAMLs, configs, and templates at `pablontiv/crossbeam`. When auditing CI/security checks, compare against crossbeam's reusable workflows.
2. **Bundled templates** — hooks, justfiles, ecosystem metadata, and gitignore patterns that are NOT in crossbeam (they're local to each repo, not shared via workflow_call).

Crossbeam workflows live at:
- `.github/workflows/codeql.yml` — CodeQL (input: language)
- `.github/workflows/scorecard.yml` — OpenSSF Scorecard
- `.github/workflows/gitleaks.yml` — Secret scanning
- `.github/workflows/go-ci.yml` — Go CI (build, test, tidy, lint, vuln)
- `.github/workflows/rust-ci.yml` — Rust CI (check-lint, test, audit)
- `.github/workflows/go-release.yml` — Go release (auto-tag + goreleaser)
- `.github/workflows/rust-release.yml` — Rust release (auto-tag + cargo-zigbuild)
- `.github/workflows/auto-tag.yml` — Standalone auto-tag (non-language repos)
- `.github/workflows/sops-guard.yml` — SOPS plaintext detection

Crossbeam configs live at: `configs/go/`, `configs/rust/`, `configs/shared/`
Crossbeam templates live at: `templates/` (CONTRIBUTING, SECURITY, CoC, issues, PR, dependabot)

## Phase 1: Detect & Audit

### Step 1: Detect ecosystem

Check for marker files in the repo root:

| File | Ecosystem | Language |
|------|-----------|----------|
| `Cargo.toml` | cargo | Rust |
| `go.mod` | gomod | Go |
| `package.json` | npm | Node/JS |
| `pyproject.toml` or `setup.py` | pip | Python |

If multiple found, use first match in order above. Store as `$ECOSYSTEM` and `$LANGUAGE`.

Read ecosystem metadata from this skill's `templates/ecosystems/$LANGUAGE.yml` for parameterization values.

### Step 2: Detect GitHub remote

```bash
git remote get-url origin 2>/dev/null
```

Extract `$OWNER/$REPO` from the URL. If no remote, skip all gh api checks.

### Step 3: Run audit checklist

For every check, determine status: PASS, FAIL, or SKIP.

See [checks-reference.md](checks-reference.md) for detailed detection logic per check.

**Hooks checks** (skip if `--component` != hooks):

| # | Check | How to detect |
|---|-------|---------------|
| H1 | .githooks/ exists + core.hooksPath set | `.githooks/` dir exists AND `git config core.hooksPath` == `.githooks` |
| H2 | Pre-commit: format + lint + gitleaks | `.githooks/pre-commit` has gitleaks + format/lint |
| H3 | Commit-msg: conventional commits | `.githooks/commit-msg` contains conventional commit regex |
| H4 | Pre-push: docs validate + drift + build + sync | `.githooks/pre-push` contains rootline validate + drift detection + build |
| H5 | Post-merge: sync + build + rootline fix | `.githooks/post-merge` contains skill sync + build + rootline fix |
| H6 | Skill sync in hooks | pre-push and post-merge sync `.claude/skills/` |

**CI/CD checks** (skip if `--component` != ci):

| # | Check | How to detect |
|---|-------|---------------|
| C1 | Crossbeam CI workflow | `uses: pablontiv/crossbeam/.github/workflows/go-ci.yml@v1` or `rust-ci.yml@v1` in any workflow |
| C2 | Crossbeam auto-tag/release | `uses: pablontiv/crossbeam/.github/workflows/go-release.yml@v1` or `rust-release.yml@v1` or `auto-tag.yml@v1` |
| C3 | Gitleaks via crossbeam | `uses: pablontiv/crossbeam/.github/workflows/gitleaks.yml@v1` in any workflow |
| C4 | No inline CI duplication | No inline build/test/lint/vuln jobs that duplicate crossbeam CI workflow |
| C5 | Crossbeam version current | Caller stubs reference `@v1` (the major tag alias) |
| C6 | Cross-platform release | Release workflow passes `platforms` input with ≥2 targets (Rust) or goreleaser has multi-goos (Go) |
| C7 | Quality gate dependencies | Release workflow has `needs:` on CI + gitleaks jobs |
| C8 | SOPS guard (if applicable) | `uses: pablontiv/crossbeam/.github/workflows/sops-guard.yml@v1` if `.sops.yaml` exists |

**Security checks** (skip if `--component` != security):

| # | Check | How to detect |
|---|-------|---------------|
| S1 | CodeQL via crossbeam | `uses: pablontiv/crossbeam/.github/workflows/codeql.yml@v1` with correct `language` input |
| S2 | Scorecard via crossbeam | `uses: pablontiv/crossbeam/.github/workflows/scorecard.yml@v1` |
| S3 | Dependabot config | `.github/dependabot.yml` exists with ecosystem + github-actions entries |
| S4 | Branch protection | `gh api .../protection` returns PR reviews + dismiss_stale + no force push |
| S5 | Secret scanning enabled | `gh api` shows secret_scanning.status = enabled |
| S6 | SLSA attestation | Crossbeam release workflows include attestation (inherent — just verify release workflow is referenced) |

**Config checks** (skip if `--component` != config):

| # | Check | How to detect |
|---|-------|---------------|
| F1 | .editorconfig | File exists (reference: crossbeam `configs/shared/editorconfig`) |
| F2 | Justfile with standard recipes | `Justfile` has: check, test, fmt, sync-version, bump-*, release-* |
| F3 | .gitignore comprehensive | File exists with ecosystem-appropriate patterns |
| F4 | CONTRIBUTING.md | File exists (reference: crossbeam `templates/CONTRIBUTING.md`) |
| F5 | SECURITY.md | File exists (reference: crossbeam `templates/SECURITY.md`) |
| F6 | LICENSE | File exists at root |
| F7 | CODE_OF_CONDUCT.md | File exists (reference: crossbeam `templates/CODE_OF_CONDUCT.md`) |
| F8 | Linter config file | `.clippy.toml` (Rust) or `.golangci.yml` (Go) — reference: crossbeam `configs/` |
| F9 | Dependency policy config | `deny.toml` (Rust) — reference: crossbeam `configs/rust/deny.toml` |
| F10 | Release profile optimized | Cargo.toml `[profile.release]` has LTO + strip (Rust only) |

**Governance checks** (part of security component):

| # | Check | How to detect |
|---|-------|---------------|
| G1 | CODEOWNERS | `.github/CODEOWNERS` or `CODEOWNERS` exists |
| G2 | Repo settings hardened | Wiki disabled, squash-only, auto-delete branches |
| G3 | Issue/PR templates | `.github/ISSUE_TEMPLATE/` or `.github/pull_request_template.md` |

### Step 4: Output report

```
CROSSBEAM — Repository Standards Report
════════════════════════════════════════
Repo: $OWNER/$REPO
Language: $LANGUAGE ($ECOSYSTEM)
Date: $(date -I)

HOOKS
─────
[PASS] H1  .githooks/ exists + core.hooksPath configured
[PASS] H2  Pre-commit: format + lint + gitleaks
...

CI/CD (crossbeam integration)
─────────────────────────────
[PASS] C1  CI workflow uses crossbeam go-ci.yml@v1
[PASS] C2  Release uses crossbeam go-release.yml@v1
[PASS] C3  Gitleaks via crossbeam
[PASS] C4  No inline CI duplication
[PASS] C5  Crossbeam version current (@v1)
...

SECURITY
────────
[PASS] S1  CodeQL via crossbeam
[PASS] S2  Scorecard via crossbeam
...

CONFIG
──────
[PASS] F1  .editorconfig present
...

GOVERNANCE
──────────
[PASS] G1  CODEOWNERS configured
...

SCORE: 28/30 checks passing (93%)
```

If `--audit-only`, STOP HERE and present the report.

## Phase 2: Generate & Apply

For each FAIL check, apply the remediation.

### Crossbeam caller stubs (CI/Security checks)

When a repo is missing crossbeam workflow references, create caller stubs.

**For Go repos** — create/update `.github/workflows/ci.yml`:
```yaml
name: CI
on:
  push: { branches: [main, master] }
  pull_request: { branches: [main, master] }
jobs:
  ci:
    uses: pablontiv/crossbeam/.github/workflows/go-ci.yml@v1
    with:
      go-version-file: go.mod
  gitleaks:
    uses: pablontiv/crossbeam/.github/workflows/gitleaks.yml@v1
  release:
    uses: pablontiv/crossbeam/.github/workflows/go-release.yml@v1
    needs: [ci, gitleaks]
    if: github.event_name == 'push'
    with:
      quality-gate-jobs: '["ci","gitleaks"]'
      binary-name: {{BINARY_NAME}}
    permissions:
      contents: write
      id-token: write
      attestations: write
```

**For Rust repos** — same pattern with `rust-ci.yml@v1` and `rust-release.yml@v1`.

**For non-language repos** — use `auto-tag.yml@v1` instead of language-specific release.

**Security workflows** — create separate caller stubs:
```yaml
# .github/workflows/codeql.yml
name: CodeQL
on:
  push: { branches: [main, master] }
  pull_request: { branches: [main, master] }
  schedule: [{ cron: '0 6 * * 1' }]
jobs:
  codeql:
    uses: pablontiv/crossbeam/.github/workflows/codeql.yml@v1
    with:
      language: {{LANGUAGE}}
    permissions:
      security-events: write
      contents: read
```

**SOPS guard** — add to CI if `.sops.yaml` exists:
```yaml
  sops-guard:
    uses: pablontiv/crossbeam/.github/workflows/sops-guard.yml@v1
```

### Hook creation (local files, from bundled templates)

For missing hooks (H1-H6), use templates from this skill's `templates/hooks/` directory. These are local git hooks, NOT crossbeam workflows.

| Check | Template | Target |
|-------|----------|--------|
| H2 | `templates/hooks/pre-commit.sh` | `.githooks/pre-commit` |
| H3 | `templates/hooks/commit-msg.sh` | `.githooks/commit-msg` |
| H4 | `templates/hooks/pre-push.sh` | `.githooks/pre-push` |
| H5 | `templates/hooks/post-merge.sh` | `.githooks/post-merge` |

When creating hooks:
1. Create `.githooks/` directory
2. Write hook files with `chmod +x`
3. Set `git config core.hooksPath .githooks`

### Config files

For missing config files, reference crossbeam's canonical versions:
- `.editorconfig` → based on crossbeam `configs/shared/editorconfig`
- `.golangci.yml` → based on crossbeam `configs/go/golangci.yml`
- `deny.toml` → based on crossbeam `configs/rust/deny.toml`
- `CONTRIBUTING.md` → based on crossbeam `templates/CONTRIBUTING.md`
- `SECURITY.md` → based on crossbeam `templates/SECURITY.md`
- `CODE_OF_CONDUCT.md` → based on crossbeam `templates/CODE_OF_CONDUCT.md`
- `.github/dependabot.yml` → based on crossbeam `templates/dependabot/{go,rust,actions-only}.yml`

For Justfile and .gitignore, use this skill's bundled templates.

### Template parameterization

Replace `{{PLACEHOLDER}}` values:

| Placeholder | Source |
|-------------|--------|
| `{{PROJECT_NAME}}` | Repo name from remote URL or directory name |
| `{{OWNER}}` | Extracted from remote URL |
| `{{BINARY_NAME}}` | Same as project name (lowercase) |
| `{{LANGUAGE}}` | Detected language (go, rust, etc.) |
| `{{SOURCE_DIR}}` | `cmd/` for Go, `src/` for Rust |
| `{{FORMAT_CHECK}}` | From ecosystem metadata |
| `{{LINT_CHECK}}` | From ecosystem metadata |
| `{{BUILD_RELEASE_CMD}}` | From ecosystem metadata |

### GitHub API calls (always confirm)

| Check | API call |
|-------|----------|
| S4 | `gh api .../branches/$BRANCH/protection --method PUT` |
| S5 | `gh repo edit --enable-secret-scanning --enable-secret-scanning-push-protection` |
| G2 | `gh api repos/$OWNER/$REPO --method PATCH` |

Branch protection payload:
```json
{
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "enforce_admins": false,
  "restrictions": null,
  "required_status_checks": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
```

## Phase 3: Verify

After applying:

1. **YAML validation**: For each created/modified workflow, verify valid YAML
2. **Hook permissions**: Verify `.githooks/*` are executable
3. **Secrets scan**: `gitleaks detect --source . --verbose` (if available)
4. **Final report**: Re-run the audit checklist and show updated score

```
CROSSBEAM — Post-Remediation Summary
═════════════════════════════════════

Applied: 5 fixes
Score: 23/28 → 28/28 (100%)

Crossbeam stubs created:
  .github/workflows/ci.yml (go-ci + gitleaks + go-release)
  .github/workflows/codeql.yml (codeql@v1)
  .github/workflows/scorecard.yml (scorecard@v1)

Hooks created:
  .githooks/pre-commit
  .githooks/commit-msg

Next steps:
  - git add + commit the new files
  - Push to trigger CI and verify all jobs pass
```

## Important guidelines

- **Never commit automatically**. Create files, modify files — but leave the commit to the user.
- **gh api calls are destructive** — always confirm before executing, even in `--apply` mode.
- **Crossbeam stubs use @v1** — the major tag alias, not specific versions or SHAs.
- **Additive only** — never delete existing workflow jobs, hooks, or governance files.
- **Respect existing files** — if a hook/config already exists with more content than expected, preserve extra content.
- **Language detection is best-effort** — if unsure, ask the user.
- **Private repos** require GitHub Pro for branch protection. Detect 403 and note as SKIP.
