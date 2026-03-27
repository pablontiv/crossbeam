# crossbeam — Shared Infrastructure for the pablontiv Ecosystem

## Summary

Centralized repository (`pablontiv/crossbeam`) containing all reusable GitHub Actions workflows, tooling configurations, and community templates shared across the pablontiv ecosystem. Replaces per-repo duplication with a single source of truth, consumed via GitHub's `workflow_call` mechanism and praxis/conform synchronization.

## Problem

30+ workflow files across 6 repos with 70-80% duplication. Security workflows (CodeQL, Scorecard, Gitleaks) are copy-pasted nearly identically. Go CI and Rust CI follow the same patterns with minor parameter variations. Linter configs, release configs, and community files (CONTRIBUTING.md, SECURITY.md, issue templates) are maintained independently in each repo, leading to drift and maintenance overhead.

Praxis/conform already templates most of these, but generates static copies that diverge over time. There is no mechanism to propagate updates across repos without re-running conform on each one.

## Consuming Repos

| Repo | Language | Workflows Consumed | Configs Consumed |
|------|----------|-------------------|-----------------|
| rootline | Go | codeql, scorecard, gitleaks, go-ci, go-release | golangci, goreleaser, editorconfig |
| localops | Go | codeql, scorecard, gitleaks, go-ci, go-release | golangci, goreleaser, editorconfig |
| backscroll | Rust | codeql, scorecard, gitleaks, rust-ci, rust-release | rustfmt, clippy, deny, editorconfig |
| kedral | Rust | codeql, scorecard, gitleaks, rust-ci, rust-release | rustfmt, clippy, deny, editorconfig |
| homeserver | HCL/YAML | codeql, scorecard, gitleaks | editorconfig |
| dotfiles | Shell | gitleaks | editorconfig |

## Repository Structure

```
crossbeam/
├── .github/
│   └── workflows/
│       ├── codeql.yml           # Reusable: language input
│       ├── scorecard.yml        # Reusable: no inputs
│       ├── gitleaks.yml         # Reusable: no inputs
│       ├── go-ci.yml            # Reusable: build + test + tidy + lint + vuln
│       ├── go-release.yml       # Reusable: auto-tag + goreleaser
│       ├── rust-ci.yml          # Reusable: check + test + audit
│       └── rust-release.yml     # Reusable: auto-tag + cargo-zigbuild
│
├── configs/
│   ├── go/
│   │   ├── golangci.yml         # Standard linter config
│   │   └── goreleaser.yml       # Base goreleaser (no GPG)
│   ├── rust/
│   │   ├── rustfmt.toml         # Edition 2024, full standard
│   │   ├── clippy.toml          # Standardized thresholds
│   │   └── deny.toml            # License allowlist + advisory baseline
│   └── shared/
│       └── editorconfig         # Multi-language .editorconfig
│
├── templates/
│   ├── CONTRIBUTING.md          # Placeholders: {{LANGUAGE}}, {{SETUP_STEPS}}
│   ├── SECURITY.md
│   ├── CODE_OF_CONDUCT.md
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── dependabot/
│       ├── go.yml
│       ├── rust.yml
│       └── actions-only.yml
│
├── CLAUDE.md
└── README.md                    # Catalog + consumption guide
```

## Reusable Workflow Specifications

### codeql.yml

**Inputs:**
- `language` (required, string): `go`, `rust`, `actions`

**Triggers (caller-side):**
- push + pull_request on default branch
- schedule: `0 6 * * 1` (Mondays 6AM UTC)

**Permissions:** `security-events: write`, `contents: read`

**Actions (SHA-pinned):**
- `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd`
- `github/codeql-action/init@b1bff81932f5cdfc8695c7752dcee935dcd061c8`
- `github/codeql-action/analyze@b1bff81932f5cdfc8695c7752dcee935dcd061c8`

### scorecard.yml

**Inputs:** none

**Triggers (caller-side):**
- branch_protection_rule
- push on default branch
- schedule: `0 6 * * 1`

**Permissions:** `read-all` (top), `security-events: write` + `id-token: write` (job)

**Actions (SHA-pinned):**
- `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd`
- `ossf/scorecard-action@4eaacf0543bb3f2c246792bd56e8cdeffafb205a`
- `actions/upload-artifact` (SARIF upload)
- `github/codeql-action/upload-sarif@b1bff81932f5cdfc8695c7752dcee935dcd061c8`

**Config:** `publish_results: true`

### gitleaks.yml

**Inputs:** none

**Triggers (caller-side):** push + pull_request on default branch

**Permissions:** `contents: read`

**Actions (SHA-pinned):**
- `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd` with `fetch-depth: 0`
- `gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7`

**Secrets:** `GITHUB_TOKEN` passed via env

### go-ci.yml

**Inputs:**
- `go-version` (optional, string, default: `stable`): Go version for setup-go
- `go-version-file` (optional, string, default: `""`): Path to go.mod for version resolution
- `coverage-threshold` (optional, number, default: `0`): Minimum coverage %, 0 disables check
- `lint-version` (optional, string, default: `v2.10.1`): golangci-lint version
**Jobs:**
1. **build** — `go build ./...`
2. **test** — `go test ./... -race -coverprofile=coverage.out`, coverage threshold check if > 0
3. **tidy** — `go mod tidy` + `git diff --exit-code go.mod go.sum`
4. **lint** — golangci-lint-action with specified version
5. **vuln** — `go install golang.org/x/vuln/cmd/govulncheck@latest && govulncheck ./...`

**Permissions:** `contents: read`

**Actions (SHA-pinned):**
- `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd`
- `actions/setup-go@4b73464bb391d4059bd26b0524d20df3927bd417`
- `golangci/golangci-lint-action@1e7e51e771db61008b38414a730f564565cf7c20`

### go-release.yml

**Inputs:**
- `quality-gate-jobs` (required, string): JSON array of job names to wait for before tagging (e.g. `'["build","test","tidy","lint","vuln"]'`)
- `binary-name` (optional, string, default: `""`): Binary name for smoke test, empty skips smoke test
- `goreleaser-args` (optional, string, default: `release --clean`): Goreleaser arguments
- `signing` (optional, boolean, default: `false`): Enable GPG signing

**Secrets:**
- `GPG_PRIVATE_KEY` (optional): Required if signing enabled
- `GPG_FINGERPRINT` (optional): Required if signing enabled

**Jobs:**
1. **auto-tag** — Conventional commit analysis, semver bump (pre-1.0: feat=patch, breaking=minor; post-1.0: feat=minor, breaking=major), tag push with concurrent guard
2. **release** — goreleaser-action if tag was created, multi-platform builds, SLSA attestation

**Permissions:** `contents: write`, `id-token: write`, `attestations: write`

**Version strategy:**
- Prefixes: `feat*` → minor/patch, `fix*`/`perf*` → patch, `*!` → breaking
- Initial tag: `v0.0.0` if no tags exist
- Concurrent guard: `git ls-remote --tags origin` check before push

### rust-ci.yml

**Inputs:**
- `rust-toolchain` (optional, string, default: `stable`): Rust toolchain
- `deny-checks` (optional, string, default: `licenses bans advisories`): cargo-deny check arguments
- `test-args` (optional, string, default: `--all-features`): Additional cargo test arguments

**Jobs:**
1. **check-lint** — `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo check`
2. **test** — `cargo test` with specified args
3. **audit** — `cargo install cargo-deny && cargo deny check`

**Permissions:** `contents: read`

**Env:** `CARGO_TERM_COLOR: always`

**Actions (SHA-pinned):**
- `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd`
- `dtolnay/rust-toolchain@efa25f7f19611383d5b0ccf2d1c8914531636bf9`

### rust-release.yml

**Inputs:**
- `quality-gate-jobs` (required, string): JSON array of job names to wait for
- `binary-name` (required, string): Binary name for builds and smoke tests
- `platforms` (optional, string, default: `linux`): Comma-separated: `linux`, `macos`, `windows`
- `changelog-tool` (optional, string, default: `generate-notes`): `git-cliff` or `generate-notes`
- `static-target` (optional, string, default: `x86_64-unknown-linux-musl`): Static build target

**Jobs:**
1. **auto-tag** — Same conventional commit strategy as go-release
2. **release** — Build native + static musl, smoke test, create GitHub release
3. **release-macos** (conditional on platforms input) — aarch64 build, upload to release
4. **release-windows** (conditional on platforms input) — x86_64 build, upload to release

**Permissions:** `contents: write`, `id-token: write`, `attestations: write`

**Build tools installed:** cargo-auditable, cargo-zigbuild, zig (via pip), git-cliff (if changelog-tool = git-cliff)

## Standard Configurations

### configs/go/golangci.yml

```yaml
version: "2"
run:
  timeout: 3m
linters:
  default: none
  enable:
    - govet
    - errcheck
    - staticcheck
    - unused
    - ineffassign
    - gocritic
    - gosec
linters-settings:
  gosec:
    excludes:
      - G301    # directory permissions
      - G304    # file inclusion via variable
      - G306    # file write permissions
issues:
  max-issues-per-linter: 50
  max-same-issues: 5
```

**Per-repo overrides:** Each repo maintains its own `.golangci.yml`. Crossbeam's version is the canonical baseline that praxis/conform diffs against. Repos needing additional gosec excludes (e.g. G204 for subprocess execution in localops) copy the crossbeam baseline and add their exclusions. There is no inheritance mechanism — the local file is the full config.

### configs/go/goreleaser.yml

```yaml
version: 2

before:
  hooks:
    - go mod tidy

builds:
  - env: [CGO_ENABLED=0]
    ldflags: [-s, -w, "-X main.version={{.Version}}"]
    goos: [linux, darwin, windows]
    goarch: [amd64, arm64]

archives:
  - format: tar.gz
    format_overrides:
      - goos: windows
        format: zip
    name_template: "{{ .ProjectName }}_{{ .Version }}_{{ .Os }}_{{ .Arch }}"

checksum:
  name_template: checksums.txt

changelog:
  sort: asc
  filters:
    exclude: ["^docs:", "^test:", "^ci:", "^chore:", "^style:", "^refactor:"]
```

**Per-repo overrides:** localops adds GPG signing block and terraform-registry-manifest.json. rootline adds `main: ./cmd/rootline/`. These are local goreleaser configs that override crossbeam's base.

### configs/rust/rustfmt.toml

```toml
edition = "2024"
newline_style = "Unix"
use_field_init_shorthand = true
use_try_shorthand = true
```

### configs/rust/clippy.toml

```toml
disallowed-types = []
enum-variant-name-threshold = 3
struct-field-name-threshold = 3
```

### configs/rust/deny.toml

```toml
[graph]
all-features = false
no-default-features = false

[advisories]
ignore = []

[licenses]
allow = [
  "MIT",
  "Apache-2.0",
  "Unicode-3.0",
  "BSD-3-Clause",
  "ISC",
  "OpenSSL",
  "Zlib",
  "CC0-1.0",
  "MPL-2.0",
  "BSL-1.0",
]
confidence-threshold = 0.8

[bans]
multiple-versions = "warn"
wildcards = "allow"

[sources]
unknown-registry = "warn"
unknown-git = "warn"
allow-registry = ["https://github.com/rust-lang/crates.io-index"]
```

**Per-repo overrides:** Repos with transitive dependency advisories add `ignore` entries in a local `deny.toml` (e.g. kedral's RUSTSEC-2024-0384 for notify/instant).

### configs/shared/editorconfig

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.go]
indent_style = tab

[*.rs]
indent_size = 4

[*.tf]
indent_size = 2

[Makefile]
indent_style = tab

[*.{yml,yaml}]
indent_size = 2

[*.md]
trim_trailing_whitespace = false
```

## Consumer-Side Pattern

### Workflow caller (example: rootline)

```yaml
# rootline/.github/workflows/codeql.yml
name: CodeQL
on:
  push: { branches: [master, main] }
  pull_request: { branches: [master, main] }
  schedule: [{ cron: '0 6 * * 1' }]
jobs:
  codeql:
    uses: pablontiv/crossbeam/.github/workflows/codeql.yml@v1
    with:
      language: go
    permissions:
      security-events: write
      contents: read
```

```yaml
# rootline/.github/workflows/ci.yml
name: CI
on:
  push: { branches: [master, main] }
  pull_request: { branches: [master, main] }

jobs:
  ci:
    uses: pablontiv/crossbeam/.github/workflows/go-ci.yml@v1
    with:
      coverage-threshold: 85

  gitleaks:
    uses: pablontiv/crossbeam/.github/workflows/gitleaks.yml@v1

  docs-validate:
    # Repo-specific job stays local
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
      - run: rootline validate --all docs/epics/

  release:
    uses: pablontiv/crossbeam/.github/workflows/go-release.yml@v1
    needs: [ci, gitleaks, docs-validate]
    with:
      quality-gate-jobs: '["ci","gitleaks","docs-validate"]'
      binary-name: rootline
    permissions:
      contents: write
      id-token: write
      attestations: write
```

### Config consumption

Configs live in crossbeam as reference copies. Praxis/conform synchronizes them to consuming repos:

1. Conform compares local config against `crossbeam@latest`
2. If drift detected: reports diff, optionally auto-creates PR to align
3. Repos can maintain a local override file that extends the crossbeam baseline

This is a **pull model**, not push. Repos opt-in by having praxis/conform configured to check crossbeam.

## Relationship with Praxis/Conform

| Aspect | Before (praxis/conform only) | After (crossbeam + conform) |
|--------|-----------------------------|-----------------------------|
| Source of truth | Templates embedded in praxis skill | Versioned files in crossbeam repo |
| Propagation | Re-run conform per repo, generates fresh copy | Conform diffs against crossbeam@latest |
| Workflow reuse | Static YAML generation | `workflow_call` reference (5 lines vs 35) |
| Config updates | Must re-generate and PR per repo | Single crossbeam PR, conform detects drift |
| Audit checks | 33 checks against internal templates | Same checks, but against crossbeam artifacts |

Praxis/conform evolves from "template generator" to "drift detector against crossbeam". The conform skill's template directory (`praxis/.claude/skills/conform/templates/`) is deprecated once crossbeam is the canonical source.

## What Does NOT Go in crossbeam

- Repo-specific workflows: `validate-terraform.yml`, `validate-k8s.yml`, `publish-marketplace.yml`
- Repo-specific CI jobs: PowerShell install tests (backscroll), docs-validate (rootline)
- Secrets or credentials: GPG keys passed as workflow inputs, never stored
- Praxis/conform audit logic: the "engine" stays in praxis, crossbeam is the "data"
- Application code, business logic, or project-specific tooling

## Versionado

- Semver tags: `v1.0.0`, `v1.1.0`, `v2.0.0`
- Major tag alias: `v1` points to latest `v1.x.x` (consumers reference `@v1`)
- Breaking changes (input renames, removed jobs) require major bump
- Action SHA updates, new optional inputs, bug fixes are minor/patch
- Dependabot on crossbeam itself to keep action SHAs current

## Migration Plan

### Phase 1 — Security Workflows (Low Risk)

1. Create `pablontiv/crossbeam` repo
2. Implement `codeql.yml`, `scorecard.yml`, `gitleaks.yml` as reusable workflows
3. Tag `v1.0.0`
4. Migrate all 6 repos to reference crossbeam, one repo at a time
5. Validate CI passes on each before proceeding
6. Remove old workflow content (keep caller stubs)

### Phase 2 — Language CI Workflows

1. Implement `go-ci.yml` with all 5 standard jobs
2. Implement `rust-ci.yml` with all 3 standard jobs
3. Tag `v1.1.0`
4. Migrate rootline, localops (Go) and backscroll, kedral (Rust)
5. Validate CI parity (same jobs, same results)

### Phase 3 — Configs and Templates

1. Add `configs/` directory with all standard configs
2. Add `templates/` directory with community files
3. Evolve praxis/conform to diff against crossbeam instead of internal templates
4. Tag `v1.2.0`

### Phase 4 — Release Workflows

1. Implement `go-release.yml` (auto-tag + goreleaser)
2. Implement `rust-release.yml` (auto-tag + cargo-zigbuild + optional multi-platform)
3. Tag `v1.3.0`
4. Migrate release jobs from all repos
5. End-to-end validation: push a feat commit, verify tag + release created

## Success Criteria

- All 6 repos reference crossbeam for security workflows (CodeQL, Scorecard, Gitleaks)
- Go repos (rootline, localops) use `go-ci.yml` and `go-release.yml`
- Rust repos (backscroll, kedral) use `rust-ci.yml` and `rust-release.yml`
- No workflow duplication remains (only caller stubs in consuming repos)
- Praxis/conform audits against crossbeam artifacts instead of internal templates
- CI behavior is identical before and after migration (no regressions)
- Single PR to crossbeam propagates action SHA updates to all consumers
