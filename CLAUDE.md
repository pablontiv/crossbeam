# crossbeam

Shared CI/CD infrastructure for the pablontiv ecosystem. Contains reusable GitHub Actions workflows, tooling configurations, and community templates.

## Repository Structure

- `.github/workflows/` — Reusable workflows consumed via `workflow_call`
- `configs/` — Canonical tooling configs (golangci, goreleaser, rustfmt, clippy, deny, editorconfig)
- `templates/` — Community file templates (CONTRIBUTING, SECURITY, issues, dependabot)
- `scripts/` — Test scripts for workflow logic
- `docs/superpowers/specs/` — Design specifications

## Workflows

| Workflow | Purpose | Key Inputs |
|----------|---------|------------|
| codeql.yml | CodeQL security scanning | `language` (go/rust/actions) |
| gitleaks.yml | Secret scanning | none |
| go-ci.yml | Go CI (build, test, tidy, lint, vuln) | `go-version`, `coverage-threshold` (default: 0), `lint-version` |
| rust-ci.yml | Rust CI (check-lint, test, audit) | `rust-toolchain`, `deny-checks`, `test-args` |
| go-release.yml | Go release (auto-tag + goreleaser) | `quality-gate-jobs`, `binary-name`, `graduation-threshold` |
| rust-release.yml | Rust release (auto-tag + cargo-zigbuild) | `quality-gate-jobs`, `binary-name`, `platforms`, `graduation-threshold` |

## Versioning

- Crossbeam uses semver starting at v1.0.0
- New workflow/optional input = minor, bugfix/SHA update = patch, breaking = major
- Major tag alias: `v1` → latest `v1.x.x`
- Release workflows implement aggressive semver for consuming repos: `feat` = minor bump even in pre-1.0
- Auto-graduation to v1.0.0 when minor >= threshold (default 5)

## Consuming Repos

Repos reference workflows via `uses: pablontiv/crossbeam/.github/workflows/<workflow>@v1`

## Key Conventions

- All GitHub Actions are SHA-pinned (not tag-pinned)
- Conventional commits required for auto-tagging
- Configs are reference baselines — repos maintain local overrides where needed
