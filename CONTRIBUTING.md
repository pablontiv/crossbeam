# Contributing to Crossbeam

Thank you for your interest in contributing!

Crossbeam is the shared CI/CD infrastructure for the pablontiv ecosystem. It provides reusable GitHub Actions workflows, tooling configurations, and community file templates consumed by other repos in the ecosystem.

## What Lives Here

- `.github/workflows/` — Reusable workflows (`workflow_call`) for CI, security, and release
- `configs/` — Canonical tooling configs (golangci, goreleaser, editorconfig, etc.)
- `templates/` — Community file templates (CONTRIBUTING, SECURITY, issue templates) for consuming repos
- `scripts/` — Test and validation scripts for workflow logic

## Development Setup

No build tooling required — crossbeam is a workflows-and-configs repo. You need:

- [GitHub CLI](https://cli.github.com/) (`gh`) for API interactions
- A text editor

```bash
git clone https://github.com/pablontiv/crossbeam.git
cd crossbeam
git config core.hooksPath .githooks
```

## Workflow

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Validate YAML syntax locally if editing workflows
5. Commit using [Conventional Commits](https://www.conventionalcommits.org/)
6. Open a Pull Request

## Commit Convention

```
type(scope): description
```

| Type | Semver Impact | When to use |
|------|--------------|-------------|
| `feat` | minor | New workflow or template |
| `fix` | patch | Bug fix in workflow logic |
| `docs` | none | Documentation only |
| `ci` | none | CI/CD changes |
| `chore` | none | Maintenance, SHA updates |

Breaking changes use `!` suffix: `feat!: remove deprecated input`

## Versioning

Crossbeam uses semver starting at v1.0.0. The `v1` tag alias always points to the latest `v1.x.x`. Consuming repos reference workflows via `@v1`.

- New workflow or optional input = minor bump
- Bug fix or SHA update = patch bump
- Breaking change to workflow inputs/outputs = major bump

## SHA Pinning

All `uses:` references in workflows **must** be SHA-pinned. Never use tag-pinned references. Update SHAs intentionally when upgrading upstream actions.

## Reporting Issues

- **Bugs**: Use the bug report template
- **Features**: Use the feature request template
- **Security**: See [SECURITY.md](SECURITY.md) for responsible disclosure
