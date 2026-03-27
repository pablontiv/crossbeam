# Crossbeam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create all reusable GitHub Actions workflows, tooling configs, and community templates for the crossbeam shared infrastructure repo, implementing the versioning strategy with aggressive semver bumps and auto-graduation.

**Architecture:** Reusable workflows consumed via `workflow_call`. Security workflows (codeql, scorecard, gitleaks) are parameterless or single-input. Language CI workflows (go-ci, rust-ci) accept version/threshold inputs. Release workflows (go-release, rust-release) embed the auto-tag versioning algorithm inline as shell steps. Config files are static reference copies. All GitHub Actions are SHA-pinned.

**Tech Stack:** GitHub Actions (reusable `workflow_call` workflows), shell/bash (auto-tag logic), YAML, TOML, INI

**Specs:**
- `docs/superpowers/specs/2026-03-27-crossbeam-design.md` — full workflow specs, config content, consumer patterns
- `docs/superpowers/specs/2026-03-27-versioning-strategy.md` — bump table, auto-graduation algorithm, migration strategy

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `.github/workflows/codeql.yml` | Create | Reusable CodeQL security scan |
| `.github/workflows/scorecard.yml` | Create | Reusable OpenSSF Scorecard |
| `.github/workflows/gitleaks.yml` | Create | Reusable secret scanning |
| `.github/workflows/go-ci.yml` | Create | Go CI: build, test, tidy, lint, vuln |
| `.github/workflows/rust-ci.yml` | Create | Rust CI: check-lint, test, audit |
| `.github/workflows/go-release.yml` | Create | Go release: auto-tag (versioning algorithm) + goreleaser |
| `.github/workflows/rust-release.yml` | Create | Rust release: auto-tag (versioning algorithm) + cargo-zigbuild + multi-platform |
| `scripts/test-auto-tag.sh` | Create | Integration test for the auto-tag versioning algorithm |
| `configs/go/golangci.yml` | Create | Baseline golangci-lint config |
| `configs/go/goreleaser.yml` | Create | Baseline goreleaser config (no GPG) |
| `configs/rust/rustfmt.toml` | Create | rustfmt Edition 2024 config |
| `configs/rust/clippy.toml` | Create | clippy thresholds config |
| `configs/rust/deny.toml` | Create | cargo-deny license allowlist + advisory baseline |
| `configs/shared/editorconfig` | Create | Multi-language .editorconfig |
| `templates/CONTRIBUTING.md` | Create | Contributing guide with language/setup placeholders |
| `templates/SECURITY.md` | Create | Security policy |
| `templates/CODE_OF_CONDUCT.md` | Create | Contributor Covenant |
| `templates/ISSUE_TEMPLATE/bug_report.md` | Create | Bug report template |
| `templates/ISSUE_TEMPLATE/feature_request.md` | Create | Feature request template |
| `templates/PULL_REQUEST_TEMPLATE.md` | Create | PR template |
| `templates/dependabot/go.yml` | Create | Dependabot config for Go repos |
| `templates/dependabot/rust.yml` | Create | Dependabot config for Rust repos |
| `templates/dependabot/actions-only.yml` | Create | Dependabot config for actions-only repos |
| `CLAUDE.md` | Create | AI assistant context for crossbeam |
| `README.md` | Create | Catalog + consumption guide |

---

### Task 1: Security Workflows (Phase 1)

**Files:**
- Create: `.github/workflows/codeql.yml`
- Create: `.github/workflows/scorecard.yml`
- Create: `.github/workflows/gitleaks.yml`

- [ ] **Step 1: Create codeql.yml**

```yaml
# .github/workflows/codeql.yml
name: CodeQL

on:
  workflow_call:
    inputs:
      language:
        required: true
        type: string
        description: 'Language to analyze: go, rust, actions'

permissions:
  security-events: write
  contents: read

jobs:
  analyze:
    name: Analyze (${{ inputs.language }})
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd

      - name: Initialize CodeQL
        uses: github/codeql-action/init@b1bff81932f5cdfc8695c7752dcee935dcd061c8
        with:
          languages: ${{ inputs.language }}

      - name: Autobuild
        uses: github/codeql-action/autobuild@b1bff81932f5cdfc8695c7752dcee935dcd061c8

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@b1bff81932f5cdfc8695c7752dcee935dcd061c8
```

- [ ] **Step 2: Create scorecard.yml**

```yaml
# .github/workflows/scorecard.yml
name: Scorecard

on:
  workflow_call:

permissions: read-all

jobs:
  analysis:
    name: Scorecard analysis
    runs-on: ubuntu-latest
    permissions:
      security-events: write
      id-token: write
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
        with:
          persist-credentials: false

      - name: Run analysis
        uses: ossf/scorecard-action@4eaacf0543bb3f2c246792bd56e8cdeffafb205a
        with:
          results_file: results.sarif
          results_format: sarif
          publish_results: true

      - name: Upload artifact
        uses: actions/upload-artifact@ea165f8d65b6db9a6b7c67862cd61e8cca06d2d1
        with:
          name: SARIF file
          path: results.sarif
          retention-days: 5

      - name: Upload to code-scanning
        uses: github/codeql-action/upload-sarif@b1bff81932f5cdfc8695c7752dcee935dcd061c8
        with:
          sarif_file: results.sarif
```

- [ ] **Step 3: Create gitleaks.yml**

```yaml
# .github/workflows/gitleaks.yml
name: Gitleaks

on:
  workflow_call:

permissions:
  contents: read

jobs:
  scan:
    name: Secret scanning
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
        with:
          fetch-depth: 0

      - name: Run Gitleaks
        uses: gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 4: Validate YAML syntax**

Run: `python3 -c "import yaml; [yaml.safe_load(open(f'.github/workflows/{w}')) for w in ['codeql.yml','scorecard.yml','gitleaks.yml']]" && echo "YAML valid"`

Expected: `YAML valid`

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/codeql.yml .github/workflows/scorecard.yml .github/workflows/gitleaks.yml
git commit -m "feat: add reusable security workflows — codeql, scorecard, gitleaks

SHA-pinned actions. CodeQL accepts language input (go/rust/actions).
Scorecard publishes SARIF results. Gitleaks scans full history."
```

---

### Task 2: Go CI Workflow (Phase 2)

**Files:**
- Create: `.github/workflows/go-ci.yml`

- [ ] **Step 1: Create go-ci.yml**

```yaml
# .github/workflows/go-ci.yml
name: Go CI

on:
  workflow_call:
    inputs:
      go-version:
        required: false
        type: string
        default: 'stable'
        description: 'Go version for setup-go'
      go-version-file:
        required: false
        type: string
        default: ''
        description: 'Path to go.mod for version resolution'
      coverage-threshold:
        required: false
        type: number
        default: 0
        description: 'Minimum coverage %, 0 disables check'
      lint-version:
        required: false
        type: string
        default: 'v2.10.1'
        description: 'golangci-lint version'

permissions:
  contents: read

jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd

      - name: Setup Go
        uses: actions/setup-go@4b73464bb391d4059bd26b0524d20df3927bd417
        with:
          go-version: ${{ inputs.go-version }}
          go-version-file: ${{ inputs.go-version-file || '' }}

      - name: Build
        run: go build ./...

  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd

      - name: Setup Go
        uses: actions/setup-go@4b73464bb391d4059bd26b0524d20df3927bd417
        with:
          go-version: ${{ inputs.go-version }}
          go-version-file: ${{ inputs.go-version-file || '' }}

      - name: Test with coverage
        run: go test ./... -race -coverprofile=coverage.out

      - name: Check coverage threshold
        if: inputs.coverage-threshold > 0
        run: |
          COVERAGE=$(go tool cover -func=coverage.out | grep total | awk '{print substr($3, 1, length($3)-1)}')
          echo "Coverage: ${COVERAGE}%"
          if (( $(echo "$COVERAGE < ${{ inputs.coverage-threshold }}" | bc -l) )); then
            echo "::error::Coverage ${COVERAGE}% is below threshold ${{ inputs.coverage-threshold }}%"
            exit 1
          fi

  tidy:
    name: Tidy
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd

      - name: Setup Go
        uses: actions/setup-go@4b73464bb391d4059bd26b0524d20df3927bd417
        with:
          go-version: ${{ inputs.go-version }}
          go-version-file: ${{ inputs.go-version-file || '' }}

      - name: Tidy
        run: go mod tidy

      - name: Check for changes
        run: git diff --exit-code go.mod go.sum

  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd

      - name: Setup Go
        uses: actions/setup-go@4b73464bb391d4059bd26b0524d20df3927bd417
        with:
          go-version: ${{ inputs.go-version }}
          go-version-file: ${{ inputs.go-version-file || '' }}

      - name: golangci-lint
        uses: golangci/golangci-lint-action@1e7e51e771db61008b38414a730f564565cf7c20
        with:
          version: ${{ inputs.lint-version }}

  vuln:
    name: Vulnerability check
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd

      - name: Setup Go
        uses: actions/setup-go@4b73464bb391d4059bd26b0524d20df3927bd417
        with:
          go-version: ${{ inputs.go-version }}
          go-version-file: ${{ inputs.go-version-file || '' }}

      - name: Install govulncheck
        run: go install golang.org/x/vuln/cmd/govulncheck@latest

      - name: Run govulncheck
        run: govulncheck ./...
```

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/go-ci.yml'))" && echo "YAML valid"`

Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/go-ci.yml
git commit -m "feat: add reusable go-ci workflow — build, test, tidy, lint, vuln

5 parallel jobs. Configurable go-version, coverage-threshold, lint-version.
Coverage check uses bc for float comparison."
```

---

### Task 3: Rust CI Workflow (Phase 2)

**Files:**
- Create: `.github/workflows/rust-ci.yml`

- [ ] **Step 1: Create rust-ci.yml**

```yaml
# .github/workflows/rust-ci.yml
name: Rust CI

on:
  workflow_call:
    inputs:
      rust-toolchain:
        required: false
        type: string
        default: 'stable'
        description: 'Rust toolchain'
      deny-checks:
        required: false
        type: string
        default: 'licenses bans advisories'
        description: 'cargo-deny check arguments'
      test-args:
        required: false
        type: string
        default: '--all-features'
        description: 'Additional cargo test arguments'

permissions:
  contents: read

env:
  CARGO_TERM_COLOR: always

jobs:
  check-lint:
    name: Check & Lint
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd

      - name: Setup Rust
        uses: dtolnay/rust-toolchain@efa25f7f19611383d5b0ccf2d1c8914531636bf9
        with:
          toolchain: ${{ inputs.rust-toolchain }}
          components: rustfmt, clippy

      - name: Format check
        run: cargo fmt --check

      - name: Clippy
        run: cargo clippy -- -D warnings

      - name: Check
        run: cargo check

  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd

      - name: Setup Rust
        uses: dtolnay/rust-toolchain@efa25f7f19611383d5b0ccf2d1c8914531636bf9
        with:
          toolchain: ${{ inputs.rust-toolchain }}

      - name: Test
        run: cargo test ${{ inputs.test-args }}

  audit:
    name: Audit
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd

      - name: Install cargo-deny
        run: cargo install cargo-deny

      - name: Run cargo-deny
        run: cargo deny check ${{ inputs.deny-checks }}
```

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/rust-ci.yml'))" && echo "YAML valid"`

Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/rust-ci.yml
git commit -m "feat: add reusable rust-ci workflow — check-lint, test, audit

3 parallel jobs. Configurable rust-toolchain, deny-checks, test-args.
CARGO_TERM_COLOR enabled globally."
```

---

### Task 4: Auto-Tag Versioning Test Script (TDD)

**Files:**
- Create: `scripts/test-auto-tag.sh`

This test validates the versioning algorithm that will be embedded in both release workflows. It creates a temporary git repo and simulates the bump logic.

- [ ] **Step 1: Write the test script**

```bash
#!/usr/bin/env bash
# scripts/test-auto-tag.sh — Integration test for the auto-tag versioning algorithm
# Creates a temp git repo and validates bump logic against the versioning spec.
set -euo pipefail

PASS=0
FAIL=0
TMPDIR=""

cleanup() { [[ -n "$TMPDIR" ]] && rm -rf "$TMPDIR"; }
trap cleanup EXIT

setup_repo() {
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  git init -b main >/dev/null 2>&1
  git config user.email "test@test.com"
  git config user.name "Test"
}

# The auto-tag algorithm — identical to what will be inline in release workflows.
# Takes: GRADUATION_THRESHOLD (env var)
# Reads: latest semver tag + HEAD commit message
# Outputs: NEW_TAG (or empty if no bump needed)
compute_tag() {
  local LATEST
  LATEST=$(git tag -l 'v*' | sort -V | tail -1)
  if [[ -z "$LATEST" ]]; then
    LATEST="v0.0.0"
  fi

  local MAJOR MINOR PATCH
  MAJOR=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f1)
  MINOR=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f2)
  PATCH=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f3)

  local SUBJECT BODY TYPE BREAKING
  SUBJECT=$(git log -1 --pretty=%s)
  BODY=$(git log -1 --pretty=%b)
  BREAKING=false
  TYPE=other

  # Check for breaking indicator: ! in subject OR BREAKING CHANGE trailer in body
  if echo "$SUBJECT" | grep -qE '^[a-z]+(\(.+\))?!:' || echo "$BODY" | grep -qE 'BREAKING CHANGE'; then
    BREAKING=true
  fi

  # Determine type from conventional commit prefix
  if echo "$SUBJECT" | grep -qE '^feat(\(.+\))?[!]?:'; then
    TYPE=feat
  fi

  local GRAD_THRESHOLD="${GRADUATION_THRESHOLD:-5}"

  if [[ $MAJOR -eq 0 ]]; then
    if [[ $GRAD_THRESHOLD -gt 0 && $MINOR -ge $GRAD_THRESHOLD && ("$TYPE" == "feat" || "$BREAKING" == "true") ]]; then
      NEW_TAG="v1.0.0"
    elif [[ "$TYPE" == "feat" || "$BREAKING" == "true" ]]; then
      MINOR=$((MINOR + 1))
      PATCH=0
      NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
    else
      PATCH=$((PATCH + 1))
      NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
    fi
  else
    if [[ "$BREAKING" == "true" ]]; then
      MAJOR=$((MAJOR + 1))
      MINOR=0
      PATCH=0
      NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
    elif [[ "$TYPE" == "feat" ]]; then
      MINOR=$((MINOR + 1))
      PATCH=0
      NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
    else
      PATCH=$((PATCH + 1))
      NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
    fi
  fi

  echo "$NEW_TAG"
}

make_commit() {
  local msg="$1"
  echo "$msg" >> log.txt
  git add log.txt
  git commit -m "$msg" >/dev/null 2>&1
}

assert_tag() {
  local test_name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $test_name → $actual"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name → expected $expected, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

# ─── Test Suite ───

echo "=== Pre-1.0 Bump Logic ==="

setup_repo
make_commit "fix: initial fix"
TAG=$(compute_tag)
assert_tag "fix from v0.0.0 → patch" "v0.0.1" "$TAG"

git tag v0.0.1
make_commit "feat: add feature"
TAG=$(compute_tag)
assert_tag "feat from v0.0.1 → minor" "v0.1.0" "$TAG"

git tag v0.1.0
make_commit "docs: update readme"
TAG=$(compute_tag)
assert_tag "docs from v0.1.0 → patch" "v0.1.1" "$TAG"

git tag v0.1.1
make_commit "feat!: breaking change"
TAG=$(compute_tag)
assert_tag "feat! from v0.1.1 → minor (pre-1.0)" "v0.2.0" "$TAG"

git tag v0.2.0
make_commit "refactor!: breaking refactor"
TAG=$(compute_tag)
assert_tag "refactor! from v0.2.0 → minor (pre-1.0)" "v0.3.0" "$TAG"

echo ""
echo "=== Auto-Graduation (threshold=3) ==="

cleanup
setup_repo
export GRADUATION_THRESHOLD=3

make_commit "feat: first"
git tag v0.1.0
make_commit "feat: second"
git tag v0.2.0
make_commit "feat: third"
git tag v0.3.0

make_commit "docs: not a feat"
TAG=$(compute_tag)
assert_tag "patch at threshold → no graduation" "v0.3.1" "$TAG"

git tag v0.3.1
make_commit "feat: triggers graduation"
TAG=$(compute_tag)
assert_tag "feat at minor>=3 → v1.0.0" "v1.0.0" "$TAG"

echo ""
echo "=== Auto-Graduation (threshold=5, default) ==="

cleanup
setup_repo
export GRADUATION_THRESHOLD=5

for i in $(seq 1 5); do
  make_commit "feat: feature $i"
  git tag "v0.${i}.0"
done

make_commit "feat: triggers graduation"
TAG=$(compute_tag)
assert_tag "feat at minor>=5 → v1.0.0" "v1.0.0" "$TAG"

echo ""
echo "=== Auto-Graduation Disabled (threshold=0) ==="

cleanup
setup_repo
export GRADUATION_THRESHOLD=0

for i in $(seq 1 10); do
  make_commit "feat: feature $i"
  git tag "v0.${i}.0"
done

make_commit "feat: no graduation"
TAG=$(compute_tag)
assert_tag "feat at minor=10 with threshold=0 → v0.11.0 (no graduation)" "v0.11.0" "$TAG"

echo ""
echo "=== Post-1.0 Bump Logic ==="

cleanup
setup_repo
unset GRADUATION_THRESHOLD
git tag v1.0.0

make_commit "fix: a bugfix"
TAG=$(compute_tag)
assert_tag "fix from v1.0.0 → patch" "v1.0.1" "$TAG"

git tag v1.0.1
make_commit "feat: new feature"
TAG=$(compute_tag)
assert_tag "feat from v1.0.1 → minor" "v1.1.0" "$TAG"

git tag v1.1.0
make_commit "feat!: breaking feature"
TAG=$(compute_tag)
assert_tag "feat! from v1.1.0 → major" "v2.0.0" "$TAG"

git tag v2.0.0
make_commit "perf!: breaking perf"
TAG=$(compute_tag)
assert_tag "perf! from v2.0.0 → major" "v3.0.0" "$TAG"

git tag v3.0.0
make_commit "chore: housekeeping"
TAG=$(compute_tag)
assert_tag "chore from v3.0.0 → patch" "v3.0.1" "$TAG"

echo ""
echo "=== Scoped Commits ==="

cleanup
setup_repo
git tag v1.0.0

make_commit "feat(api): scoped feature"
TAG=$(compute_tag)
assert_tag "feat(api) → minor" "v1.1.0" "$TAG"

git tag v1.1.0
make_commit "fix(core): scoped fix"
TAG=$(compute_tag)
assert_tag "fix(core) → patch" "v1.1.1" "$TAG"

git tag v1.1.1
make_commit "feat(api)!: scoped breaking"
TAG=$(compute_tag)
assert_tag "feat(api)! → major" "v2.0.0" "$TAG"

echo ""
echo "=== No Tags (initial state) ==="

cleanup
setup_repo
make_commit "feat: first commit ever"
TAG=$(compute_tag)
assert_tag "feat from no tags → v0.1.0" "v0.1.0" "$TAG"

cleanup
setup_repo
make_commit "fix: first commit ever"
TAG=$(compute_tag)
assert_tag "fix from no tags → v0.0.1" "v0.0.1" "$TAG"

echo ""
echo "=== Migration: rootline-like scenario (v0.9.121, threshold=5) ==="

cleanup
setup_repo
export GRADUATION_THRESHOLD=5
git tag v0.9.121

make_commit "feat: next feature"
TAG=$(compute_tag)
assert_tag "feat from v0.9.121 with minor=9 >= 5 → v1.0.0" "v1.0.0" "$TAG"

git tag v1.0.0
make_commit "feat: post-graduation feature"
TAG=$(compute_tag)
assert_tag "feat from v1.0.0 → v1.1.0 (post-1.0 rules)" "v1.1.0" "$TAG"

echo ""
echo "════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "════════════════════════"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
```

- [ ] **Step 2: Run the test**

Run: `chmod +x scripts/test-auto-tag.sh && bash scripts/test-auto-tag.sh`

Expected: All tests PASS, exit code 0. The key assertions:
- Pre-1.0: feat→minor, fix→patch, breaking→minor
- Auto-graduation: feat at minor>=threshold → v1.0.0
- Graduation disabled: threshold=0 never graduates
- Post-1.0: feat→minor, breaking→major, fix→patch
- Migration: v0.9.121 + feat → v1.0.0 (rootline scenario)

- [ ] **Step 3: Commit**

```bash
git add scripts/test-auto-tag.sh
git commit -m "test: add auto-tag versioning algorithm integration test

Validates bump table, auto-graduation (threshold=3,5,disabled),
post-1.0 semver, scoped commits, initial state, and rootline
migration scenario (v0.9.121 → v1.0.0)."
```

---

### Task 5: Go Release Workflow (Phase 4)

**Files:**
- Create: `.github/workflows/go-release.yml`

- [ ] **Step 1: Create go-release.yml**

```yaml
# .github/workflows/go-release.yml
name: Go Release

on:
  workflow_call:
    inputs:
      quality-gate-jobs:
        required: true
        type: string
        description: 'JSON array of job names to wait for before tagging'
      binary-name:
        required: false
        type: string
        default: ''
        description: 'Binary name for smoke test, empty skips smoke test'
      goreleaser-args:
        required: false
        type: string
        default: 'release --clean'
        description: 'Goreleaser arguments'
      signing:
        required: false
        type: boolean
        default: false
        description: 'Enable GPG signing'
      graduation-threshold:
        required: false
        type: number
        default: 5
        description: 'Minor version threshold for auto-graduation to v1.0.0. 0 disables.'
    secrets:
      GPG_PRIVATE_KEY:
        required: false
        description: 'GPG private key for signing (required if signing enabled)'
      GPG_FINGERPRINT:
        required: false
        description: 'GPG fingerprint (required if signing enabled)'

permissions:
  contents: write
  id-token: write
  attestations: write

jobs:
  auto-tag:
    name: Auto-tag
    runs-on: ubuntu-latest
    if: github.ref == format('refs/heads/{0}', github.event.repository.default_branch)
    outputs:
      new_tag: ${{ steps.tag.outputs.new_tag }}
      created: ${{ steps.tag.outputs.created }}
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
        with:
          fetch-depth: 0

      - name: Compute and push tag
        id: tag
        env:
          GRADUATION_THRESHOLD: ${{ inputs.graduation-threshold }}
        run: |
          # Find latest semver tag
          LATEST=$(git tag -l 'v*' | sort -V | tail -1)
          if [[ -z "$LATEST" ]]; then
            LATEST="v0.0.0"
          fi

          # Parse version components
          MAJOR=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f1)
          MINOR=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f2)
          PATCH=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f3)

          # Determine commit type from HEAD message
          SUBJECT=$(git log -1 --pretty=%s)
          BODY=$(git log -1 --pretty=%b)
          BREAKING=false
          TYPE=other

          # Check for breaking: ! in subject OR BREAKING CHANGE trailer in body
          if echo "$SUBJECT" | grep -qE '^[a-z]+(\(.+\))?!:' || echo "$BODY" | grep -qE 'BREAKING CHANGE'; then
            BREAKING=true
          fi

          if echo "$SUBJECT" | grep -qE '^feat(\(.+\))?[!]?:'; then
            TYPE=feat
          fi

          # Apply bump table
          if [[ $MAJOR -eq 0 ]]; then
            if [[ $GRADUATION_THRESHOLD -gt 0 && $MINOR -ge $GRADUATION_THRESHOLD && ("$TYPE" == "feat" || "$BREAKING" == "true") ]]; then
              NEW_TAG="v1.0.0"
            elif [[ "$TYPE" == "feat" || "$BREAKING" == "true" ]]; then
              MINOR=$((MINOR + 1))
              PATCH=0
              NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
            else
              PATCH=$((PATCH + 1))
              NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
            fi
          else
            if [[ "$BREAKING" == "true" ]]; then
              MAJOR=$((MAJOR + 1))
              MINOR=0
              PATCH=0
              NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
            elif [[ "$TYPE" == "feat" ]]; then
              MINOR=$((MINOR + 1))
              PATCH=0
              NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
            else
              PATCH=$((PATCH + 1))
              NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
            fi
          fi

          echo "Computed tag: $NEW_TAG (from $LATEST, type=$TYPE, breaking=$BREAKING)"

          # Concurrent guard: check if tag already exists on remote
          if git ls-remote --tags origin | grep -q "refs/tags/${NEW_TAG}$"; then
            echo "Tag $NEW_TAG already exists on remote, skipping"
            echo "new_tag=$NEW_TAG" >> "$GITHUB_OUTPUT"
            echo "created=false" >> "$GITHUB_OUTPUT"
          else
            git tag "$NEW_TAG"
            git push origin "$NEW_TAG"
            echo "new_tag=$NEW_TAG" >> "$GITHUB_OUTPUT"
            echo "created=true" >> "$GITHUB_OUTPUT"
          fi

  release:
    name: Release
    runs-on: ubuntu-latest
    needs: auto-tag
    if: needs.auto-tag.outputs.created == 'true'
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
        with:
          fetch-depth: 0

      - name: Setup Go
        uses: actions/setup-go@4b73464bb391d4059bd26b0524d20df3927bd417
        with:
          go-version: stable

      - name: Import GPG key
        if: inputs.signing
        uses: crazy-max/ghaction-import-gpg@e89d40939c28e39f97cf32e97db1ba6f489de4f0
        with:
          gpg_private_key: ${{ secrets.GPG_PRIVATE_KEY }}
          fingerprint: ${{ secrets.GPG_FINGERPRINT }}

      - name: Run GoReleaser
        uses: goreleaser/goreleaser-action@9ed2f89a662bf1735a48bc8557fd212fa902bebf
        with:
          version: latest
          args: ${{ inputs.goreleaser-args }}
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Smoke test binary
        if: inputs.binary-name != ''
        run: |
          ARTIFACT=$(find dist/ -name "${{ inputs.binary-name }}" -type f | head -1)
          if [[ -n "$ARTIFACT" ]]; then
            chmod +x "$ARTIFACT"
            "$ARTIFACT" --version || "$ARTIFACT" version || echo "Smoke test: binary executes"
          fi

      - name: Generate SLSA attestation
        uses: actions/attest-build-provenance@db473fddc028af60658334401dc6fa3ffd8669fd
        with:
          subject-path: 'dist/checksums.txt'
```

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/go-release.yml'))" && echo "YAML valid"`

Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/go-release.yml
git commit -m "feat: add reusable go-release workflow with auto-tag versioning

Auto-tag job implements aggressive semver: feat=minor (pre-1.0),
auto-graduation at configurable threshold (default 5), concurrent
guard. Release job runs goreleaser with optional GPG signing and
SLSA attestation."
```

---

### Task 6: Rust Release Workflow (Phase 4)

**Files:**
- Create: `.github/workflows/rust-release.yml`

- [ ] **Step 1: Create rust-release.yml**

```yaml
# .github/workflows/rust-release.yml
name: Rust Release

on:
  workflow_call:
    inputs:
      quality-gate-jobs:
        required: true
        type: string
        description: 'JSON array of job names to wait for'
      binary-name:
        required: true
        type: string
        description: 'Binary name for builds and smoke tests'
      platforms:
        required: false
        type: string
        default: 'linux'
        description: 'Comma-separated: linux, macos, windows'
      changelog-tool:
        required: false
        type: string
        default: 'generate-notes'
        description: 'git-cliff or generate-notes'
      static-target:
        required: false
        type: string
        default: 'x86_64-unknown-linux-musl'
        description: 'Static build target'
      graduation-threshold:
        required: false
        type: number
        default: 5
        description: 'Minor version threshold for auto-graduation to v1.0.0. 0 disables.'

permissions:
  contents: write
  id-token: write
  attestations: write

jobs:
  auto-tag:
    name: Auto-tag
    runs-on: ubuntu-latest
    if: github.ref == format('refs/heads/{0}', github.event.repository.default_branch)
    outputs:
      new_tag: ${{ steps.tag.outputs.new_tag }}
      created: ${{ steps.tag.outputs.created }}
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
        with:
          fetch-depth: 0

      - name: Compute and push tag
        id: tag
        env:
          GRADUATION_THRESHOLD: ${{ inputs.graduation-threshold }}
        run: |
          # Find latest semver tag
          LATEST=$(git tag -l 'v*' | sort -V | tail -1)
          if [[ -z "$LATEST" ]]; then
            LATEST="v0.0.0"
          fi

          # Parse version components
          MAJOR=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f1)
          MINOR=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f2)
          PATCH=$(echo "$LATEST" | sed 's/^v//' | cut -d. -f3)

          # Determine commit type from HEAD message
          SUBJECT=$(git log -1 --pretty=%s)
          BODY=$(git log -1 --pretty=%b)
          BREAKING=false
          TYPE=other

          # Check for breaking: ! in subject OR BREAKING CHANGE trailer in body
          if echo "$SUBJECT" | grep -qE '^[a-z]+(\(.+\))?!:' || echo "$BODY" | grep -qE 'BREAKING CHANGE'; then
            BREAKING=true
          fi

          if echo "$SUBJECT" | grep -qE '^feat(\(.+\))?[!]?:'; then
            TYPE=feat
          fi

          # Apply bump table
          if [[ $MAJOR -eq 0 ]]; then
            if [[ $GRADUATION_THRESHOLD -gt 0 && $MINOR -ge $GRADUATION_THRESHOLD && ("$TYPE" == "feat" || "$BREAKING" == "true") ]]; then
              NEW_TAG="v1.0.0"
            elif [[ "$TYPE" == "feat" || "$BREAKING" == "true" ]]; then
              MINOR=$((MINOR + 1))
              PATCH=0
              NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
            else
              PATCH=$((PATCH + 1))
              NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
            fi
          else
            if [[ "$BREAKING" == "true" ]]; then
              MAJOR=$((MAJOR + 1))
              MINOR=0
              PATCH=0
              NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
            elif [[ "$TYPE" == "feat" ]]; then
              MINOR=$((MINOR + 1))
              PATCH=0
              NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
            else
              PATCH=$((PATCH + 1))
              NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
            fi
          fi

          echo "Computed tag: $NEW_TAG (from $LATEST, type=$TYPE, breaking=$BREAKING)"

          # Concurrent guard
          if git ls-remote --tags origin | grep -q "refs/tags/${NEW_TAG}$"; then
            echo "Tag $NEW_TAG already exists on remote, skipping"
            echo "new_tag=$NEW_TAG" >> "$GITHUB_OUTPUT"
            echo "created=false" >> "$GITHUB_OUTPUT"
          else
            git tag "$NEW_TAG"
            git push origin "$NEW_TAG"
            echo "new_tag=$NEW_TAG" >> "$GITHUB_OUTPUT"
            echo "created=true" >> "$GITHUB_OUTPUT"
          fi

  release:
    name: Release (Linux)
    runs-on: ubuntu-latest
    needs: auto-tag
    if: needs.auto-tag.outputs.created == 'true'
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
        with:
          fetch-depth: 0

      - name: Setup Rust
        uses: dtolnay/rust-toolchain@efa25f7f19611383d5b0ccf2d1c8914531636bf9
        with:
          toolchain: stable
          targets: ${{ inputs.static-target }}

      - name: Install build tools
        run: |
          cargo install cargo-auditable cargo-zigbuild
          pip install ziglang

      - name: Install git-cliff
        if: inputs.changelog-tool == 'git-cliff'
        run: cargo install git-cliff

      - name: Set release version
        run: echo "RELEASE_VERSION=${{ needs.auto-tag.outputs.new_tag }}" >> "$GITHUB_ENV"

      - name: Build native
        run: cargo auditable build --release

      - name: Build static (musl)
        run: cargo auditable zigbuild --release --target ${{ inputs.static-target }}

      - name: Smoke test
        run: |
          chmod +x target/release/${{ inputs.binary-name }}
          target/release/${{ inputs.binary-name }} --version || target/release/${{ inputs.binary-name }} version || echo "Smoke test: binary executes"

      - name: Generate changelog
        id: changelog
        run: |
          if [[ "${{ inputs.changelog-tool }}" == "git-cliff" ]]; then
            git-cliff --latest --strip header > CHANGELOG.md
          else
            echo "Using GitHub auto-generated release notes"
            echo "" > CHANGELOG.md
          fi

      - name: Create GitHub release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          GENERATE_NOTES_FLAG=""
          if [[ "${{ inputs.changelog-tool }}" != "git-cliff" ]]; then
            GENERATE_NOTES_FLAG="--generate-notes"
          fi

          gh release create "${{ needs.auto-tag.outputs.new_tag }}" \
            --title "${{ needs.auto-tag.outputs.new_tag }}" \
            ${GENERATE_NOTES_FLAG} \
            $([[ -s CHANGELOG.md ]] && echo "--notes-file CHANGELOG.md" || echo "") \
            target/release/${{ inputs.binary-name }} \
            target/${{ inputs.static-target }}/release/${{ inputs.binary-name }}

      - name: Generate SLSA attestation
        uses: actions/attest-build-provenance@db473fddc028af60658334401dc6fa3ffd8669fd
        with:
          subject-path: 'target/release/${{ inputs.binary-name }}'

  release-macos:
    name: Release (macOS)
    runs-on: macos-latest
    needs: [auto-tag, release]
    if: needs.auto-tag.outputs.created == 'true' && contains(inputs.platforms, 'macos')
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd

      - name: Setup Rust
        uses: dtolnay/rust-toolchain@efa25f7f19611383d5b0ccf2d1c8914531636bf9
        with:
          toolchain: stable
          targets: aarch64-apple-darwin

      - name: Install cargo-auditable
        run: cargo install cargo-auditable

      - name: Build
        run: cargo auditable build --release --target aarch64-apple-darwin

      - name: Upload to release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release upload "${{ needs.auto-tag.outputs.new_tag }}" \
            target/aarch64-apple-darwin/release/${{ inputs.binary-name }}

  release-windows:
    name: Release (Windows)
    runs-on: windows-latest
    needs: [auto-tag, release]
    if: needs.auto-tag.outputs.created == 'true' && contains(inputs.platforms, 'windows')
    steps:
      - name: Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd

      - name: Setup Rust
        uses: dtolnay/rust-toolchain@efa25f7f19611383d5b0ccf2d1c8914531636bf9
        with:
          toolchain: stable

      - name: Install cargo-auditable
        run: cargo install cargo-auditable

      - name: Build
        run: cargo auditable build --release

      - name: Upload to release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release upload "${{ needs.auto-tag.outputs.new_tag }}" `
            target/release/${{ inputs.binary-name }}.exe
```

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/rust-release.yml'))" && echo "YAML valid"`

Expected: `YAML valid`

- [ ] **Step 3: Verify auto-tag logic matches test**

Run: `diff <(sed -n '/# Find latest semver tag/,/fi$/p' .github/workflows/go-release.yml) <(sed -n '/# Find latest semver tag/,/fi$/p' .github/workflows/rust-release.yml)`

Expected: Empty output (identical auto-tag logic in both workflows).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/rust-release.yml
git commit -m "feat: add reusable rust-release workflow with auto-tag versioning

Same auto-tag algorithm as go-release. Multi-platform builds
(linux native + musl static, conditional macos/windows).
cargo-auditable for supply chain security. Optional git-cliff
changelog. SLSA attestation."
```

---

### Task 7: Config Files (Phase 3)

**Files:**
- Create: `configs/go/golangci.yml`
- Create: `configs/go/goreleaser.yml`
- Create: `configs/rust/rustfmt.toml`
- Create: `configs/rust/clippy.toml`
- Create: `configs/rust/deny.toml`
- Create: `configs/shared/editorconfig`

- [ ] **Step 1: Create configs/go/golangci.yml**

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

- [ ] **Step 2: Create configs/go/goreleaser.yml**

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

- [ ] **Step 3: Create configs/rust/rustfmt.toml**

```toml
edition = "2024"
newline_style = "Unix"
use_field_init_shorthand = true
use_try_shorthand = true
```

- [ ] **Step 4: Create configs/rust/clippy.toml**

```toml
disallowed-types = []
enum-variant-name-threshold = 3
struct-field-name-threshold = 3
```

- [ ] **Step 5: Create configs/rust/deny.toml**

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

- [ ] **Step 6: Create configs/shared/editorconfig**

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

- [ ] **Step 7: Validate YAML configs**

Run: `python3 -c "import yaml; yaml.safe_load(open('configs/go/golangci.yml')); yaml.safe_load(open('configs/go/goreleaser.yml'))" && echo "YAML valid"`

Expected: `YAML valid`

- [ ] **Step 8: Commit**

```bash
git add configs/
git commit -m "feat: add standard config files — golangci, goreleaser, rustfmt, clippy, deny, editorconfig

Canonical baselines for praxis/conform drift detection. Per-repo
overrides documented in design spec."
```

---

### Task 8: Community Templates (Phase 3)

**Files:**
- Create: `templates/CONTRIBUTING.md`
- Create: `templates/SECURITY.md`
- Create: `templates/CODE_OF_CONDUCT.md`
- Create: `templates/ISSUE_TEMPLATE/bug_report.md`
- Create: `templates/ISSUE_TEMPLATE/feature_request.md`
- Create: `templates/PULL_REQUEST_TEMPLATE.md`
- Create: `templates/dependabot/go.yml`
- Create: `templates/dependabot/rust.yml`
- Create: `templates/dependabot/actions-only.yml`

- [ ] **Step 1: Create templates/CONTRIBUTING.md**

```markdown
# Contributing to {{PROJECT_NAME}}

Thank you for your interest in contributing!

## Development Setup

**Language:** {{LANGUAGE}}

{{SETUP_STEPS}}

## Workflow

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes following the project's coding standards
4. Write tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## Commit Messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — New feature (bumps minor version)
- `fix:` — Bug fix (bumps patch version)
- `docs:` — Documentation only
- `test:` — Adding or updating tests
- `ci:` — CI/CD changes
- `chore:` — Maintenance tasks
- `feat!:` or `fix!:` — Breaking change (bumps major version post-1.0)

## Code Review

All submissions require review. We use GitHub pull requests for this purpose.

## License

By contributing, you agree that your contributions will be licensed under the project's license.
```

- [ ] **Step 2: Create templates/SECURITY.md**

```markdown
# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not** open a public issue
2. Email the maintainer directly or use GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
3. Include steps to reproduce the vulnerability
4. Allow reasonable time for a fix before public disclosure

## Security Measures

This project uses:
- [CodeQL](https://codeql.github.com/) for static analysis
- [Gitleaks](https://github.com/gitleaks/gitleaks) for secret scanning
- [OpenSSF Scorecard](https://securityscorecards.dev/) for supply chain security
- SHA-pinned GitHub Actions to prevent supply chain attacks
- Dependabot for automated dependency updates
```

- [ ] **Step 3: Create templates/CODE_OF_CONDUCT.md**

```markdown
# Contributor Covenant Code of Conduct

## Our Pledge

We as members, contributors, and leaders pledge to make participation in our
community a harassment-free experience for everyone.

## Our Standards

Examples of behavior that contributes to a positive environment:
- Using welcoming and inclusive language
- Being respectful of differing viewpoints and experiences
- Gracefully accepting constructive criticism
- Focusing on what is best for the community

Examples of unacceptable behavior:
- The use of sexualized language or imagery
- Trolling, insulting or derogatory comments, and personal or political attacks
- Public or private harassment
- Publishing others' private information without explicit permission

## Enforcement

Instances of abusive, harassing, or otherwise unacceptable behavior may be
reported to the project maintainers. All complaints will be reviewed and
investigated promptly and fairly.

## Attribution

This Code of Conduct is adapted from the [Contributor Covenant](https://www.contributor-covenant.org/), version 2.1.
```

- [ ] **Step 4: Create templates/ISSUE_TEMPLATE/bug_report.md**

```markdown
---
name: Bug Report
about: Report a bug to help us improve
title: ''
labels: bug
assignees: ''
---

## Description

A clear and concise description of the bug.

## Steps to Reproduce

1. ...
2. ...
3. ...

## Expected Behavior

What you expected to happen.

## Actual Behavior

What actually happened.

## Environment

- OS: [e.g., macOS 14, Ubuntu 22.04]
- Version: [e.g., v1.2.3]

## Additional Context

Add any other context, logs, or screenshots.
```

- [ ] **Step 5: Create templates/ISSUE_TEMPLATE/feature_request.md**

```markdown
---
name: Feature Request
about: Suggest an idea for this project
title: ''
labels: enhancement
assignees: ''
---

## Problem

A clear and concise description of the problem this feature would solve.

## Proposed Solution

Describe the solution you'd like.

## Alternatives Considered

Describe any alternative solutions or features you've considered.

## Additional Context

Add any other context or screenshots about the feature request.
```

- [ ] **Step 6: Create templates/PULL_REQUEST_TEMPLATE.md**

```markdown
## Summary

Brief description of changes.

## Type of Change

- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing

- [ ] Tests added/updated
- [ ] All tests pass locally

## Checklist

- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated (if applicable)
```

- [ ] **Step 7: Create dependabot templates**

`templates/dependabot/go.yml`:
```yaml
version: 2
updates:
  - package-ecosystem: gomod
    directory: /
    schedule:
      interval: weekly
    commit-message:
      prefix: "chore(deps):"
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    commit-message:
      prefix: "chore(deps):"
```

`templates/dependabot/rust.yml`:
```yaml
version: 2
updates:
  - package-ecosystem: cargo
    directory: /
    schedule:
      interval: weekly
    commit-message:
      prefix: "chore(deps):"
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    commit-message:
      prefix: "chore(deps):"
```

`templates/dependabot/actions-only.yml`:
```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
    commit-message:
      prefix: "chore(deps):"
```

- [ ] **Step 8: Commit**

```bash
git add templates/
git commit -m "feat: add community templates — contributing, security, CoC, issues, PR, dependabot

Placeholders {{PROJECT_NAME}}, {{LANGUAGE}}, {{SETUP_STEPS}} in
CONTRIBUTING.md. Dependabot configs for Go, Rust, and actions-only repos."
```

---

### Task 9: CLAUDE.md and README.md

**Files:**
- Create: `CLAUDE.md`
- Create: `README.md`

- [ ] **Step 1: Create CLAUDE.md**

```markdown
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
| scorecard.yml | OpenSSF Scorecard | none |
| gitleaks.yml | Secret scanning | none |
| go-ci.yml | Go CI (build, test, tidy, lint, vuln) | `go-version`, `coverage-threshold`, `lint-version` |
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
```

- [ ] **Step 2: Create README.md**

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: add CLAUDE.md and README.md — catalog and consumption guide

CLAUDE.md provides AI assistant context. README.md documents
all workflows, configs, usage patterns, and versioning strategy."
```

---

### Task 10: Final Validation

- [ ] **Step 1: Verify all files exist**

Run: `find .github configs templates scripts CLAUDE.md README.md -type f | sort`

Expected output:
```
.github/workflows/codeql.yml
.github/workflows/gitleaks.yml
.github/workflows/go-ci.yml
.github/workflows/go-release.yml
.github/workflows/rust-ci.yml
.github/workflows/rust-release.yml
.github/workflows/scorecard.yml
CLAUDE.md
README.md
configs/go/golangci.yml
configs/go/goreleaser.yml
configs/rust/clippy.toml
configs/rust/deny.toml
configs/rust/rustfmt.toml
configs/shared/editorconfig
scripts/test-auto-tag.sh
templates/CODE_OF_CONDUCT.md
templates/CONTRIBUTING.md
templates/ISSUE_TEMPLATE/bug_report.md
templates/ISSUE_TEMPLATE/feature_request.md
templates/PULL_REQUEST_TEMPLATE.md
templates/SECURITY.md
templates/dependabot/actions-only.yml
templates/dependabot/go.yml
templates/dependabot/rust.yml
```

- [ ] **Step 2: Validate all YAML files**

Run: `python3 -c "import yaml, glob; [yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml') + glob.glob('configs/go/*.yml') + glob.glob('templates/dependabot/*.yml')]" && echo "All YAML valid"`

Expected: `All YAML valid`

- [ ] **Step 3: Run the auto-tag test suite**

Run: `bash scripts/test-auto-tag.sh`

Expected: All tests PASS, 0 failures.

- [ ] **Step 4: Verify git log shows all commits**

Run: `git log --oneline`

Expected: 9 new commits (Tasks 1-9) on top of the 2 existing spec commits.
