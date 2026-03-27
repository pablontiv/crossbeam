# crossbeam

Shared CI/CD infrastructure for the [pablontiv](https://github.com/pablontiv) ecosystem.

## What's Inside

### Reusable Workflows

| Workflow | Description | Consumers |
|----------|-------------|-----------|
| `codeql.yml` | CodeQL security scanning | rootline, localops, backscroll, kedral, homeserver |
| `scorecard.yml` | OpenSSF Scorecard | rootline, localops, backscroll, kedral, homeserver |
| `gitleaks.yml` | Secret scanning | all repos |
| `go-ci.yml` | Build, test, tidy, lint, vuln | rootline, localops |
| `rust-ci.yml` | Check, test, audit | backscroll, kedral |
| `go-release.yml` | Auto-tag + goreleaser | rootline, localops |
| `rust-release.yml` | Auto-tag + multi-platform builds | backscroll, kedral |

### Configuration Files

| File | Purpose |
|------|---------|
| `configs/go/golangci.yml` | golangci-lint baseline |
| `configs/go/goreleaser.yml` | goreleaser baseline (no GPG) |
| `configs/rust/rustfmt.toml` | rustfmt Edition 2024 |
| `configs/rust/clippy.toml` | clippy thresholds |
| `configs/rust/deny.toml` | cargo-deny license allowlist |
| `configs/shared/editorconfig` | Multi-language .editorconfig |

## Usage

### Calling a Workflow

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push: { branches: [main] }
  pull_request: { branches: [main] }

jobs:
  ci:
    uses: pablontiv/crossbeam/.github/workflows/go-ci.yml@v1
    with:
      coverage-threshold: 85

  gitleaks:
    uses: pablontiv/crossbeam/.github/workflows/gitleaks.yml@v1

  release:
    uses: pablontiv/crossbeam/.github/workflows/go-release.yml@v1
    needs: [ci, gitleaks]
    with:
      quality-gate-jobs: '["ci","gitleaks"]'
      binary-name: my-tool
    permissions:
      contents: write
      id-token: write
      attestations: write
```

## Versioning

This repository follows semver. Consumers reference `@v1` (major tag alias) to automatically receive patches and new features without changing their caller stubs.

| Change | Bump |
|--------|------|
| Bug fix, action SHA update | patch |
| New workflow, new optional input | minor |
| Input rename/removal, breaking change | major |

### Auto-Tag for Consuming Repos

Release workflows (`go-release.yml`, `rust-release.yml`) implement automatic version tagging based on [Conventional Commits](https://www.conventionalcommits.org/):

**Pre-1.0:** `feat` → minor, `fix` → patch, breaking → minor
**Post-1.0:** `feat` → minor, `fix` → patch, breaking → major
**Auto-graduation:** When minor version reaches the configurable threshold (default 5), the next feature commit creates `v1.0.0`.

## License

MIT
