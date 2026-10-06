# crossbeam

[![CI](https://github.com/pablontiv/crossbeam/actions/workflows/ci.yml/badge.svg)](https://github.com/pablontiv/crossbeam/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Shared CI/CD infrastructure for the [pablontiv](https://github.com/pablontiv) ecosystem.

| Consumer need | crossbeam provides |
|---------------|--------------------|
| Security scanning | `codeql.yml`, `gitleaks.yml`, `scorecard.yml` |
| Go CI (build, test, lint, vuln) | `go-ci.yml` |
| Rust CI (check, test, audit) | `rust-ci.yml` |
| PR pre-release artifacts | `go-candidate.yml` |
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
| `go-candidate.yml` | Opt-in, read-only Go PR candidate artifacts | — |
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

### Go PR candidate artifacts

`go-candidate.yml` is an opt-in `workflow_call` for building a pre-release from an exact PR commit. The caller owns the event trigger, job-level `if`, and `needs`; Crossbeam does not decide which PRs produce artifacts.

Required inputs are `source-repository`, `source-sha` (40 hexadecimal characters), `base-sha` (40 hexadecimal characters), positive `pr-number`, and non-empty `binary-name`. Optional `go-version-file` and `goreleaser-config` default to `go.mod` and `.goreleaser.yml`; both must be safe relative regular-file paths. The Go version file must select an exact patch release such as `1.24.1` (including an exact `go 1.24.1` directive).

The caller grants only `contents: read` and `pull-requests: read`. The workflow uses the token solely to read the numbered PR from the caller repository and requires exact API agreement for the head repository, head SHA, and base SHA. If the PR base changes, regenerate the candidate with the new `base-sha`; stale inputs fail closed.

The consuming repository must use this exact GoReleaser snapshot template:

```yaml
snapshot:
  version_template: "{{ incpatch .Version }}-pr.{{ .Env.PR_NUMBER }}.g{{ .ShortCommit }}"
```

Always build after the caller's required checks. A mandatory candidate on every PR can be wired as follows:

```yaml
on:
  pull_request:

jobs:
  test:
    uses: pablontiv/crossbeam/.github/workflows/go-ci.yml@v1

  candidate:
    needs: [test]
    uses: pablontiv/crossbeam/.github/workflows/go-candidate.yml@v1
    permissions:
      contents: read
      pull-requests: read
    with:
      source-repository: ${{ github.event.pull_request.head.repo.full_name }}
      source-sha: ${{ github.event.pull_request.head.sha }}
      base-sha: ${{ github.event.pull_request.base.sha }}
      pr-number: ${{ github.event.pull_request.number }}
      binary-name: my-tool
```

For a manual candidate, expose typed `workflow_dispatch` inputs and pass them through explicitly:

```yaml
on:
  workflow_dispatch:
    inputs:
      source-repository: { required: true, type: string }
      source-sha: { required: true, type: string }
      base-sha: { required: true, type: string }
      pr-number: { required: true, type: number }

jobs:
  candidate:
    uses: pablontiv/crossbeam/.github/workflows/go-candidate.yml@v1
    permissions:
      contents: read
      pull-requests: read
    with:
      source-repository: ${{ inputs.source-repository }}
      source-sha: ${{ inputs.source-sha }}
      base-sha: ${{ inputs.base-sha }}
      pr-number: ${{ inputs.pr-number }}
      binary-name: my-tool
```

To make creation label-controlled, keep the policy in the caller job:

```yaml
on:
  pull_request:
    types: [labeled, synchronize, reopened]

jobs:
  test:
    uses: pablontiv/crossbeam/.github/workflows/go-ci.yml@v1

  candidate:
    if: contains(github.event.pull_request.labels.*.name, 'candidate')
    needs: [test]
    uses: pablontiv/crossbeam/.github/workflows/go-candidate.yml@v1
    permissions:
      contents: read
      pull-requests: read
    with:
      source-repository: ${{ github.event.pull_request.head.repo.full_name }}
      source-sha: ${{ github.event.pull_request.head.sha }}
      base-sha: ${{ github.event.pull_request.base.sha }}
      pr-number: ${{ github.event.pull_request.number }}
      binary-name: my-tool
```

The workflow checks out and deepens the exact public fork SHA without credentials, discards fork tags, and imports only exact stable `vN.N.N` tags from the caller repository. Its token is confined to PR API validation under `contents: read` and `pull-requests: read`; checkout, build, and GoReleaser receive no token or secrets. It performs no push, tag, release, write, or OIDC operation. GoReleaser runs a clean snapshot; confined artifact paths, metadata, one-to-one checksums, manifest, embedded revision, and binary version are validated before only archives, checksums, and `candidate.json` are uploaded for seven days.

This workflow intentionally executes code supplied by the fork. The runner is ephemeral and has no persisted checkout credentials or build secrets, which limits repository compromise, but untrusted build code can still use runner CPU/network and observe public workflow context. Callers should keep the job secret-free, apply their own approval or label policy, and never add privileged credentials to it.

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

| Commit range | Go release result |
|--------------|-------------------|
| Contains a breaking change | minor |
| Contains `feat` | minor |
| Contains `fix` or `perf` | patch |
| Only `docs`, `test`, `refactor`, `ci`, `chore`, or `style` | no release |

Breaking changes and features in `0.x` keep the existing graduation behavior: when the minor version reaches the configurable threshold (default 5), the next qualifying commit creates `v1.0.0`. Set `graduation-threshold: 0` to disable graduation.

### Force a release bump

`go-release.yml` accepts `force-bump` with an empty default. Set it to `major`, `minor`, or `patch` to override the computed bump. Any other value fails the tagging job.

Expose the input through a caller's `workflow_dispatch` when maintainers need to cut a deliberate major release:

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      force-bump:
        description: 'Override with major, minor, or patch; leave empty for automatic'
        required: false
        type: string
        default: ''

jobs:
  release:
    uses: pablontiv/crossbeam/.github/workflows/go-release.yml@v1
    with:
      quality-gate-jobs: '["test", "lint"]'
      force-bump: ${{ inputs.force-bump || '' }}
```

---

## Documentation

| Topic | Description |
|-------|-------------|
| [go-ci.yml](.github/workflows/go-ci.yml) | Go CI: profile (light/full), coverage threshold, lint gate |
| [rust-ci.yml](.github/workflows/rust-ci.yml) | Rust CI: profile (light/full), toolchain, deny checks |
| [go-release.yml](.github/workflows/go-release.yml) | Auto-tag + goreleaser: quality gates, graduation threshold |
| [go-candidate.yml](.github/workflows/go-candidate.yml) | Opt-in Go PR candidate snapshots and interface |
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

[Apache License 2.0](LICENSE) — free for commercial and non-commercial use.
