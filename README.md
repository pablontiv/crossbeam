# crossbeam

[![CI](https://github.com/pablontiv/crossbeam/actions/workflows/ci.yml/badge.svg)](https://github.com/pablontiv/crossbeam/actions/workflows/ci.yml)
[![License: PolyForm NC](https://img.shields.io/badge/License-PolyForm%20NC-blue.svg)](LICENSE)

Shared CI/CD infrastructure for the [pablontiv](https://github.com/pablontiv) ecosystem.

| Consumer need | crossbeam provides |
|---------------|--------------------|
| Security scanning | `codeql.yml`, `gitleaks.yml`, `scorecard.yml` |
| Go CI (build, test, lint, vuln) | `go-ci.yml` |
| Rust CI (check, test, audit) | `rust-ci.yml` |
| Auto-tag + release | `go-release.yml`, `rust-release.yml` |
| Baseline tool configs | `configs/` (golangci, goreleaser, rustfmt, clippy, deny, editorconfig) |
| Community file templates | `templates/` (CONTRIBUTING, SECURITY, issue templates) |

---

## Table of Contents

- [Quick Start](#quick-start)
- [Core Idea](#core-idea)
- [What's Inside](#whats-inside)
- [Usage](#usage)
- [AI-Native](#ai-native)
- [Versioning](#versioning)
- [Documentation](#documentation)
- [Development](#development)
- [License](#license)

---

## Quick Start

```yaml
# 1. Wire up Go CI — build, test, lint, coverage gate
ci:
  uses: pablontiv/crossbeam/.github/workflows/go-ci.yml@v1
  with:
    coverage-threshold: 85

# 2. Add secret scanning (runs on every push)
gitleaks:
  uses: pablontiv/crossbeam/.github/workflows/gitleaks.yml@v1

# 3. Add security analysis (nightly CodeQL)
codeql:
  uses: pablontiv/crossbeam/.github/workflows/codeql.yml@v1
  with:
    language: go

# 4. Add automated releases — auto-tag + goreleaser on push to main
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

See [Usage](#usage) for the full `.github/workflows/ci.yml` stub.

### Profile Options

Both `go-ci.yml` and `rust-ci.yml` support a `profile` input to control CI scope:

- **`light` (default)**: Fast gate — build + test + coverage check (no -race on Go tests). Suitable for dev/PR workflows.
- **`full`**: Comprehensive — adds tidy/lint/audit checks and enables -race on tests. For final quality gates before release.

To use the previous "full" behavior by default, pass `with: profile: full`:

```yaml
ci:
  uses: pablontiv/crossbeam/.github/workflows/go-ci.yml@v1
  with:
    profile: full
    coverage-threshold: 85
```

---

## Core Idea

CI/CD configuration is infrastructure. Crossbeam treats it as a **shared library** with a versioned contract, so each consuming repo inherits a battle-tested baseline instead of maintaining its own copy.

- A single SHA update in crossbeam propagates to every consumer on next workflow run
- Each workflow exposes a typed `inputs:` contract — consumers are insulated from internal changes
- All `uses:` references are SHA-pinned — supply chain attacks on upstream actions don't silently affect the ecosystem
- Consumers don't own CI logic — they own their domain code

Crossbeam does not run code. It **defines the rules** under which all other repos build, test, scan, and release.

---

## What's Inside

### Reusable Workflows

| Workflow | Description | Consumers |
|----------|-------------|-----------|
| `codeql.yml` | CodeQL security scanning | rootline, backscroll, roadmapctl |
| `scorecard.yml` | OpenSSF Scorecard | rootline, backscroll, roadmapctl |
| `gitleaks.yml` | Secret scanning | all repos |
| `go-ci.yml` | Build, test, tidy, lint, vuln | rootline, roadmapctl, backscroll |
| `rust-ci.yml` | Check, test, audit | — |
| `go-release.yml` | Auto-tag + goreleaser | rootline, roadmapctl, backscroll |
| `rust-release.yml` | Auto-tag + multi-platform builds | — |

### Configuration Files

| File | Purpose |
|------|---------|
| `configs/go/golangci.yml` | golangci-lint baseline |
| `configs/go/goreleaser.yml` | goreleaser baseline (no GPG) |
| `configs/rust/rustfmt.toml` | rustfmt Edition 2024 |
| `configs/rust/clippy.toml` | clippy thresholds |
| `configs/rust/deny.toml` | cargo-deny license allowlist |
| `configs/shared/editorconfig` | Multi-language .editorconfig |

---

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

---

## AI-Native

Crossbeam is the **security and release infrastructure** for a suite of AI-native tools. By centralizing CI/CD policy, each tool in the ecosystem (backscroll, rootline, roadmapctl) can remain focused on its domain without owning or diverging in security posture.

- All security workflows (CodeQL, Scorecard, Gitleaks) run on a consistent schedule across the ecosystem
- SHA-pinned actions mean agents can trust the supply chain of every repo they interact with
- Release workflows produce deterministic versioned binaries — agents get reproducible tool installs

---

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

---

## Documentation

| Topic | Description |
|-------|-------------|
| [go-ci.yml](.github/workflows/go-ci.yml) | Go CI: profile (light/full), coverage threshold, lint gate |
| [rust-ci.yml](.github/workflows/rust-ci.yml) | Rust CI: profile (light/full), toolchain, deny checks |
| [go-release.yml](.github/workflows/go-release.yml) | Auto-tag + goreleaser: quality gates, graduation threshold |
| [codeql.yml](.github/workflows/codeql.yml) | CodeQL: language input, nightly schedule |
| [scorecard.yml](.github/workflows/scorecard.yml) | OpenSSF Scorecard: SARIF upload |
| [gitleaks.yml](.github/workflows/gitleaks.yml) | Secret scanning |
| [configs/go/](configs/go/) | golangci-lint and goreleaser baseline configs |
| [templates/](templates/) | Community file templates for consuming repos |

---

## Development

No build tooling required — crossbeam is a workflows-and-configs repo. Validate YAML syntax locally before opening a PR.

Commits follow [Conventional Commits](https://www.conventionalcommits.org/) (`type(scope): description`). See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow.

---

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — free for non-commercial use.
