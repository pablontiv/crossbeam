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

  local RANGE SUBJECTS BODIES TYPE BREAKING
  # Classify every commit since the last tag (a push may contain several
  # commits); the highest-impact type wins: breaking > feat > other.
  if [[ "$LATEST" == "v0.0.0" ]]; then
    RANGE="HEAD"
  else
    RANGE="${LATEST}..HEAD"
  fi
  SUBJECTS=$(git log --pretty=%s "$RANGE")
  BODIES=$(git log --pretty=%b "$RANGE")
  BREAKING=false
  TYPE=other

  # Check for breaking indicator: ! in subject OR BREAKING CHANGE trailer in body
  if echo "$SUBJECTS" | grep -qE '^[a-z]+(\(.+\))?!:' || echo "$BODIES" | grep -qE 'BREAKING CHANGE'; then
    BREAKING=true
  fi

  # Determine type from conventional commit prefix
  if echo "$SUBJECTS" | grep -qE '^feat(\(.+\))?[!]?:'; then
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
make_commit "chore: init"
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
make_commit "chore: init"
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
make_commit "chore: init"
git tag v0.9.121

make_commit "feat: next feature"
TAG=$(compute_tag)
assert_tag "feat from v0.9.121 with minor=9 >= 5 → v1.0.0" "v1.0.0" "$TAG"

git tag v1.0.0
make_commit "feat: post-graduation feature"
TAG=$(compute_tag)
assert_tag "feat from v1.0.0 → v1.1.0 (post-1.0 rules)" "v1.1.0" "$TAG"

echo ""
echo "=== Multi-commit push (type from full range, not HEAD only) ==="

cleanup
setup_repo
unset GRADUATION_THRESHOLD
make_commit "chore: init"
git tag v0.3.18

make_commit "feat: feature one"
make_commit "feat: feature two"
make_commit "fix(test): lint fix at HEAD"
TAG=$(compute_tag)
assert_tag "feat mid-push, fix at HEAD → minor" "v0.4.0" "$TAG"

git tag v0.4.0
make_commit "docs: only docs"
make_commit "chore: only chores"
TAG=$(compute_tag)
assert_tag "no feat in range → patch" "v0.4.1" "$TAG"

cleanup
setup_repo
make_commit "chore: init"
git tag v1.0.0

make_commit "feat: a feature"
make_commit "refactor!: breaking mid-push"
make_commit "fix: fix at HEAD"
TAG=$(compute_tag)
assert_tag "breaking mid-push, fix at HEAD → major" "v2.0.0" "$TAG"

git tag v2.0.0
make_commit "feat: counted"
git tag v2.1.0
make_commit "docs: after tag"
TAG=$(compute_tag)
assert_tag "commits before last tag not counted → patch" "v2.1.1" "$TAG"

echo ""
echo "════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
echo "════════════════════════"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
