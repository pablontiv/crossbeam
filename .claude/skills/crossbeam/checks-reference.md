# Crossbeam — Checks Reference

Detailed detection and remediation logic for each check. CI and security checks verify crossbeam reusable workflow integration instead of inline workflows.

---

## Hooks Checks

### H1: .githooks/ exists + core.hooksPath configured

**Why**: Git hooks enforce conventions locally before code reaches CI. Without them, developers can push non-conforming commits.

**Detect**:
```bash
test -d .githooks && [ "$(git config core.hooksPath)" = ".githooks" ]
```
PASS if both conditions true.

**Remediate**:
1. `mkdir -p .githooks`
2. `git config core.hooksPath .githooks`

---

### H2: Pre-commit has format + lint + gitleaks

**Why**: Catches formatting errors, lint violations, and secrets before they enter git history. The earlier you catch, the cheaper the fix.

**Detect**:
```bash
test -f .githooks/pre-commit
```
Then verify content includes gitleaks secret scanning AND format/lint via one of:
- **Strategy A (all-in-hook)**: format + lint + gitleaks all in `.githooks/pre-commit`
  - **Rust**: `cargo fmt` AND `cargo clippy` AND `gitleaks`
- **Strategy B (framework + hook)**: `.pre-commit-config.yaml` handles format/lint, `.githooks/pre-commit` handles gitleaks
  - **Go**: `.pre-commit-config.yaml` with `golangci-lint` + `gofmt` AND `.githooks/pre-commit` with `gitleaks`

PASS if gitleaks present AND format/lint covered (either in-hook or via pre-commit framework). WARN if gitleaks only with no format/lint in either location.

**Remediate**: For Strategy A (recommended for Rust), generate from `templates/hooks/pre-commit.sh`. For Strategy B (Go with pre-commit framework), ensure `.pre-commit-config.yaml` covers format/lint and `.githooks/pre-commit` covers gitleaks.

---

### H3: Commit-msg enforces conventional commits

**Why**: Conventional commits enable automatic versioning, changelog generation, and meaningful git history. The commit-msg hook is the enforcement point.

**Detect**:
```bash
grep -q 'feat|fix|chore|docs|refactor|perf|test|style|ci' .githooks/commit-msg 2>/dev/null
```
PASS if conventional commit regex pattern found.

**Remediate**: Copy `templates/hooks/commit-msg.sh` (universal, no parameterization needed). Set executable.

---

### H4: Pre-push validates docs + detects drift + builds + syncs skills

**Why**: Pre-push is the last gate before code reaches remote. It should validate documentation consistency, detect code-docs drift, rebuild the project binary, and sync Claude Code skills.

**Detect**: Check `.githooks/pre-push` contains:
1. `rootline validate` (docs validation)
2. `git diff --name-only` with drift detection logic — two scopes:
   - **Source drift**: source dir changed but docs unchanged
   - **Infra drift**: CI/scripts/config changed (`.github/`, `install.sh`, `install.ps1`, `Justfile`, `Cargo.toml`/`go.mod`) but docs unchanged
3. Build command (ecosystem-specific)
4. Skill sync (`cp -r` to `~/.claude/skills/`)

PASS if all four present (both drift scopes count as #2). WARN if partial.

**Remediate**: Generate from `templates/hooks/pre-push.sh` with ecosystem params. Key placeholders:
- `{{SOURCE_DIR}}`: `cmd/` (Go) or `src/` (Rust)
- `{{BUILD_RELEASE_CMD}}`: ecosystem build command
- `{{PROJECT_NAME}}`: repo name
- `{{INFRA_PATHS}}`: `.github/ install.sh install.ps1 Justfile` + ecosystem config (`Cargo.toml` for Rust, `go.mod .goreleaser.yml` for Go)

---

### H5: Post-merge syncs + builds + propagates aggregates

**Why**: After pulling merged code, the local binary and skills must stay in sync. Rootline aggregates may need re-propagation after doc merges.

**Detect**: Check `.githooks/post-merge` contains:
1. Skill sync to `~/.claude/skills/`
2. Build command (ecosystem-specific)
3. `rootline fix --all` (aggregate propagation)

PASS if all three present. WARN if partial.

**Remediate**: Generate from `templates/hooks/post-merge.sh` with ecosystem params.

---

### H6: Skill sync in hooks

**Why**: Claude Code skills in `.claude/skills/` must stay in sync with `~/.claude/skills/` so the user always has the latest version. Hooks automate this on push and merge.

**Detect**: Check `.githooks/pre-push` AND `.githooks/post-merge` both contain:
```bash
grep -q '.claude/skills' .githooks/pre-push .githooks/post-merge 2>/dev/null
```
PASS if both hooks sync skills. WARN if only one does.

**Remediate**: Already included in `templates/hooks/pre-push.sh` and `templates/hooks/post-merge.sh`. Ensure the skill sync block is present.

---

## CI/CD Checks (Crossbeam Integration)

### C1: CI workflow uses crossbeam

**Why**: Crossbeam centralizes CI logic. Repos should use `workflow_call` caller stubs instead of inline jobs, eliminating duplication and ensuring consistent quality gates.

**Detect**: At least one workflow contains:
```bash
grep -l 'pablontiv/crossbeam/.github/workflows/go-ci.yml\|pablontiv/crossbeam/.github/workflows/rust-ci.yml' .github/workflows/*.yml
```
PASS if crossbeam CI workflow reference found. FAIL if CI is inline.

**Remediate**: Replace inline CI jobs with crossbeam caller stub. Go repos use `go-ci.yml@v1`, Rust repos use `rust-ci.yml@v1`.

---

### C2: Release via crossbeam

**Why**: Crossbeam release workflows implement the aggressive semver strategy (feat=minor pre-1.0, auto-graduation) with tested auto-tag logic. Inline release jobs use the old logic.

**Detect**:
```bash
grep -l 'pablontiv/crossbeam/.github/workflows/go-release.yml\|pablontiv/crossbeam/.github/workflows/rust-release.yml\|pablontiv/crossbeam/.github/workflows/auto-tag.yml' .github/workflows/*.yml
```
PASS if crossbeam release/auto-tag reference found.

**Remediate**: Replace inline auto-tag+release with crossbeam caller stub. Language repos use `go-release.yml@v1` or `rust-release.yml@v1`. Non-language repos use `auto-tag.yml@v1`.

---

### C3: Gitleaks via crossbeam

**Why**: Centralized gitleaks workflow ensures consistent secret scanning configuration.

**Detect**:
```bash
grep -l 'pablontiv/crossbeam/.github/workflows/gitleaks.yml' .github/workflows/*.yml
```
PASS if crossbeam gitleaks reference found. FAIL if inline gitleaks or missing.

**Remediate**: Add `gitleaks.yml@v1` caller stub to CI workflow.

---

### C4: No inline CI duplication

**Why**: If a repo references crossbeam CI but also has inline build/test/lint jobs, the duplication wastes runner time and can cause confusion.

**Detect**: If crossbeam CI reference exists (C1 passes), check that no inline jobs duplicate those functions (build, test, tidy/fmt, lint, vuln/audit).

PASS if no duplication found. WARN if crossbeam reference exists alongside inline equivalents.

**Remediate**: Remove inline jobs that crossbeam CI already covers. Keep only repo-specific jobs (e.g., docs-validate).

---

### C5: Crossbeam version current

**Why**: Caller stubs should reference `@v1` (the major tag alias) to automatically receive patches and features.

**Detect**: All `uses: pablontiv/crossbeam/` references use `@v1` (not pinned to specific minor/patch like `@v1.0.0`).

PASS if all references use `@v1`.

**Remediate**: Update caller stubs to use `@v1`.

---

### C6: Cross-platform release

**Why**: Users on different platforms need pre-built binaries.

**Detect**: Rust release caller passes `platforms` input with ≥2 targets. Go uses goreleaser with multi-goos (inherent in crossbeam's goreleaser config).

PASS if ≥2 platforms covered.

**Remediate**: Add `platforms: 'linux,macos,windows'` to rust-release caller stub.

---

### C7: Quality gate dependencies

**Why**: Release should only run after CI and security checks pass.

**Detect**: Release workflow job has `needs:` that includes the CI and gitleaks jobs.

**Detect**: Release workflow runs `--version` and `--help` (or subcommand help) on built binaries BEFORE upload/publish.
```bash
grep -E '\-\-version|\-\-help' .github/workflows/*.yml
```
PASS if smoke test steps exist in release job(s) between build and upload steps.

**Remediate**: Add smoke test step after build:
```yaml
- name: Smoke Test Binary
  run: |
    ./binary --version
    ./binary --help
```

---

### C8: Changelog generation

**Why**: Users need to know what changed between releases. Automated changelog from conventional commits ensures consistency.

**Detect**:
- **Rust**: `cliff.toml` exists AND `git-cliff` in release workflow
- **Go**: `.goreleaser.yml` has `changelog:` section (goreleaser generates changelogs natively)

PASS if changelog automation present. WARN if manual only.

**Remediate**:
- **Rust**: Install `git-cliff`, create `cliff.toml` from template, add step to release job: `git-cliff --latest --strip header --output RELEASE_NOTES.md`
- **Go**: Ensure `.goreleaser.yml` has `changelog:` with `use: git` or `use: github`

---

## Security Checks

### S1: CodeQL via crossbeam

**Why**: Free static analysis via crossbeam's reusable workflow. Supports Go, Rust, Actions, JS/TS, Python.

**Detect**:
```bash
grep -l 'pablontiv/crossbeam/.github/workflows/codeql.yml' .github/workflows/*.yml
```
PASS if crossbeam codeql reference found with correct `language` input.

**Remediate**: Create codeql.yml caller stub referencing `crossbeam/.github/workflows/codeql.yml@v1` with `language: $LANGUAGE`.

---

### S2: Scorecard via crossbeam

**Why**: OpenSSF Scorecard via crossbeam's reusable workflow. 18 automated security health checks.

**Detect**:
```bash
grep -l 'pablontiv/crossbeam/.github/workflows/scorecard.yml' .github/workflows/*.yml
```
PASS if crossbeam scorecard reference found.

**Remediate**: Create scorecard.yml caller stub referencing `crossbeam/.github/workflows/scorecard.yml@v1`.

---

### S3: Dependabot configured

**Why**: Automated dependency updates catch vulnerabilities without manual monitoring.

**Detect**: `test -f .github/dependabot.yml` AND file contains both ecosystem package manager AND `github-actions` entries.

**Remediate**: Create `.github/dependabot.yml` based on crossbeam's `templates/dependabot/{go,rust,actions-only}.yml`.

---

### S4: Branch protection

**Why**: Prevents accidental or malicious direct pushes to main branch.

**Detect**:
```bash
gh api repos/$OWNER/$REPO/branches/$BRANCH/protection 2>/dev/null
```
- PASS if response includes `required_pull_request_reviews` with `required_approving_review_count >= 1` AND `dismiss_stale_reviews: true` AND `allow_force_pushes.enabled: false`
- WARN if `required_pull_request_reviews` present but `dismiss_stale_reviews: false` (stale approvals survive new pushes)
- FAIL if no branch protection or no PR review requirement

**Policy**: `enforce_admins: false` is the standard for solo-maintainer repos (owner needs bypass for emergencies). `dismiss_stale_reviews: true` ensures new commits invalidate prior approvals (critical when bots push to PRs).

**Remediate**: Apply via `gh api --method PUT` (see SKILL.md Phase 2 for payload). Requires GitHub Pro for private repos. The payload uses `enforce_admins: false` + `dismiss_stale_reviews: true` + `required_approving_review_count: 1`.

---

### S5: Secret scanning enabled

**Why**: GitHub scans for known token patterns and blocks pushes containing them.

**Detect**:
```bash
gh api repos/$OWNER/$REPO --jq '.security_and_analysis.secret_scanning.status'
```
PASS if `enabled`.

**Remediate**:
```bash
gh repo edit $OWNER/$REPO --enable-secret-scanning --enable-secret-scanning-push-protection
```

---

### S6: SLSA attestation (inherent)

**Why**: Crossbeam release workflows include SLSA attestation automatically. This check verifies the release workflow is referenced (covered by C2).

**Detect**: If C2 passes (crossbeam release workflow referenced), SLSA attestation is inherent.

PASS if C2 passes. SKIP if no release workflow.

---

## Config Checks

### F1: .editorconfig

**Detect**: `test -f .editorconfig`

**Remediate**: Copy `templates/config/editorconfig-$LANGUAGE`.

---

### F2: Justfile with standard recipes

**Why**: Justfile provides a consistent interface across ecosystems. Standard recipes (check, test, fmt, release-*) let contributors onboard without reading build docs.

**Detect**: `test -f Justfile` AND file contains all required recipes:
- `check:` (format + lint + build/check)
- `test:` (test runner)
- `fmt:` (auto-format)
- `sync-version:` (version sync from git tag)
- `bump-patch:` / `bump-minor:` (version increment)
- `release-patch:` / `release-minor:` (full release)

PASS if all present. WARN if Justfile exists but missing some recipes.

**Remediate**: Copy `templates/justfile/justfile-$LANGUAGE`. Replace `{{PROJECT_NAME}}` and `{{VERSION_FILE}}`.

---

### F3: .gitignore comprehensive

**Detect**: `test -f .gitignore` AND file contains ecosystem-specific patterns (build artifacts, IDE, OS files).

**Remediate**: If missing, copy `templates/config/gitignore-$LANGUAGE`. If exists but incomplete, suggest additions without overwriting.

---

### F4: CONTRIBUTING.md

**Detect**: `test -f CONTRIBUTING.md` AND file contains setup instructions + workflow + quality gates.

**Remediate**: Copy `templates/config/contributing-$LANGUAGE.md`. Replace `{{PROJECT_NAME}}`, `{{OWNER}}`, `{{MIN_VERSION}}`.

---

### F5–F7: Governance files

| Check | File | Detect | Remediate |
|-------|------|--------|-----------|
| F5 | SECURITY.md | `test -f SECURITY.md` | Generate with standard disclosure template using repo name |
| F6 | LICENSE | `test -f LICENSE` | Generate MIT with current year and `$OWNER` |
| F7 | CODE_OF_CONDUCT.md | `test -f CODE_OF_CONDUCT.md` | Contributor Covenant v2.1 summary |

---

### F8: Install scripts

**Why**: Pre-built binaries need a frictionless install path. `curl | bash` is the standard for Unix, PowerShell for Windows.

**Detect**: `test -f install.sh`. If CI produces Windows binaries (C6 detected Windows target), also check `test -f install.ps1`.

PASS if install.sh exists. WARN if Windows binaries exist but no install.ps1.

**Remediate**: Generate from `templates/config/install-$LANGUAGE.sh`. Key features: platform detection, latest release from GitHub API, install to `~/.local/bin/` or `/usr/local/bin/`.

---

### F9: Linter config file

**Why**: Explicit linter configuration ensures consistent code quality across contributors and CI. Without it, lint rules depend on tool defaults which may change between versions.

**Detect**:
- **Rust**: `test -f .clippy.toml`
- **Go**: `test -f .golangci.yml` OR `test -f .golangci.yaml`

PASS if ecosystem-appropriate linter config exists.

**Remediate**: Generate with strict defaults:
- **Rust**: `.clippy.toml` with nursery + pedantic group
- **Go**: `.golangci.yml` with govet, errcheck, staticcheck, unused, ineffassign, gocritic, gosec

---

### F10: Dependency policy config (Rust only)

**Why**: `cargo deny` enforces license compliance, bans specific crates, and checks advisories. The config file makes the policy explicit and reproducible.

**Detect**: `test -f deny.toml` AND file contains `[advisories]`, `[licenses]`, `[bans]` sections.

PASS if deny.toml exists with all three sections. SKIP for non-Rust ecosystems.

**Remediate**: Generate `deny.toml` from template with safe defaults (MIT/Apache-2.0/BSD allow list, advisory checking enabled, wildcard dependencies warned).

---

### F11: Release profile optimized (Rust only)

**Why**: Default release builds leave performance and size on the table. LTO, single codegen unit, and symbol stripping produce smaller, faster binaries.

**Detect**: `Cargo.toml` contains `[profile.release]` with `lto = true` AND `strip = true`.

PASS if both present. WARN if `[profile.release]` exists but missing optimizations. SKIP for non-Rust ecosystems.

**Remediate**: Add to `Cargo.toml`:
```toml
[profile.release]
opt-level = 3
lto = true
codegen-units = 1
panic = "abort"
strip = true
```

---

## Governance Checks

### G1: CODEOWNERS

**Detect**: `test -f .github/CODEOWNERS` OR `test -f CODEOWNERS`

**Remediate**: Create `.github/CODEOWNERS` with `* @$OWNER`

---

### G2: Repo settings hardened

**Why**: Reduce attack surface and enforce clean git history.

**Detect**:
```bash
gh api repos/$OWNER/$REPO --jq '{wiki: .has_wiki, squash: .allow_squash_merge, merge: .allow_merge_commit, delete_branch: .delete_branch_on_merge}'
```
PASS if wiki=false, squash=true, merge=false, delete_branch=true.

**Remediate**: `gh api repos/$OWNER/$REPO --method PATCH` with settings payload.

---

### G3: Issue/PR templates

**Detect**: `.github/ISSUE_TEMPLATE/` directory exists OR `.github/pull_request_template.md` exists.

**Remediate**: Low priority. Note as suggestion — templates are project-specific.

---

## Ecosystem-Specific Checks (optional)

These are checked when detected but not required:

| Check | Ecosystem | Detect | Remediate |
|-------|-----------|--------|-----------|
| N1 | Rust | `forbid(unsafe_code)` in main.rs | Add `#![forbid(unsafe_code)]` |
| N2 | Rust | `cargo-auditable` in release | Replace `cargo build` with `cargo auditable build` |
| N3 | Any | SBOM generation in workflow | Note as suggestion |
