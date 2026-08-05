#!/usr/bin/env bash
# Executes the release workflow's inline shell against disposable Git repositories.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
WORKFLOW="$ROOT/.github/workflows/go-release.yml"
TEST_ROOT=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

extract_release_script() {
  python3 - "$WORKFLOW" "$TEST_ROOT/compute-tag.sh" <<'PY'
from pathlib import Path
import sys

workflow = Path(sys.argv[1]).read_text().splitlines()
output = Path(sys.argv[2])

step = next(i for i, line in enumerate(workflow) if line == "      - name: Compute and push tag")
run = next(i for i in range(step + 1, len(workflow)) if workflow[i] == "        run: |")

body = []
for line in workflow[run + 1:]:
    if line and not line.startswith("          "):
        break
    body.append(line[10:] if line else "")

output.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + "\n".join(body) + "\n")
PY
  chmod +x "$TEST_ROOT/compute-tag.sh"
}

record() {
  local name=$1 expected=$2 actual=$3
  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS: %s -> %s\n' "$name" "$actual"
    PASS=$((PASS + 1))
  else
    printf '  FAIL: %s -> expected %s, got %s\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

make_commit() {
  local repo=$1 subject=$2 body=${3:-}
  printf '%s\n' "$subject" >> "$repo/history.txt"
  git -C "$repo" add history.txt
  if [[ -n "$body" ]]; then
    git -C "$repo" commit -m "$subject" -m "$body" >/dev/null
  else
    git -C "$repo" commit -m "$subject" >/dev/null
  fi
}

run_case() {
  local name=$1 latest=$2 graduation_threshold=$3 force_bump=$4
  local expected_tag=$5 expected_created=$6 expected_type=$7
  shift 7

  local slug=${name//[^a-zA-Z0-9]/-}
  local repo="$TEST_ROOT/$slug"
  local remote="$TEST_ROOT/$slug.git"
  local output="$repo/github-output"
  local log="$repo/run.log"

  git init --bare "$remote" >/dev/null
  git init -b main "$repo" >/dev/null
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.com
  git -C "$repo" remote add origin "$remote"
  make_commit "$repo" "chore: initialize fixture"
  if [[ "$latest" == "none" ]]; then
    git -C "$repo" push origin main >/dev/null
  else
    git -C "$repo" tag "$latest"
    git -C "$repo" push origin main "$latest" >/dev/null
  fi

  while (( $# > 0 )); do
    local subject=$1 body=${2:-}
    shift 2
    make_commit "$repo" "$subject" "$body"
  done

  (
    cd "$repo"
    GRADUATION_THRESHOLD="$graduation_threshold" FORCE_BUMP="$force_bump" GITHUB_OUTPUT="$output" \
      "$TEST_ROOT/compute-tag.sh"
  ) >"$log" 2>&1

  local actual_tag actual_created actual_type
  actual_tag=$(sed -n 's/^new_tag=//p' "$output" | tail -1)
  actual_created=$(sed -n 's/^created=//p' "$output" | tail -1)
  actual_type=$(sed -n 's/.*type=\([^,]*\).*/\1/p' "$log" | tail -1)

  record "$name tag" "$expected_tag" "$actual_tag"
  record "$name created" "$expected_created" "$actual_created"
  if [[ -n "$expected_type" ]]; then
    record "$name classifier" "$expected_type" "$actual_type"
  fi

  if [[ "$expected_created" == "true" ]]; then
    if git --git-dir="$remote" show-ref --verify --quiet "refs/tags/$expected_tag"; then
      record "$name remote tag" "$expected_tag" "$expected_tag"
    else
      record "$name remote tag" "$expected_tag" "missing"
    fi
  else
    local remote_tags
    remote_tags=$(git --git-dir="$remote" tag -l | sort | tr '\n' ',' | sed 's/,$//')
    local expected_remote_tags=$latest
    [[ "$latest" == "none" ]] && expected_remote_tags=""
    record "$name leaves remote tags unchanged" "$expected_remote_tags" "$remote_tags"
  fi
}

assert_invalid_force_bump_fails() {
  local repo="$TEST_ROOT/invalid-force"
  local remote="$TEST_ROOT/invalid-force.git"
  git init --bare "$remote" >/dev/null
  git init -b main "$repo" >/dev/null
  git -C "$repo" config user.name Test
  git -C "$repo" config user.email test@example.com
  git -C "$repo" remote add origin "$remote"
  make_commit "$repo" "chore: initialize fixture"
  git -C "$repo" tag v1.2.3
  git -C "$repo" push origin main v1.2.3 >/dev/null
  make_commit "$repo" "fix: repair bug"

  local status=0
  (
    cd "$repo"
    GRADUATION_THRESHOLD=5 FORCE_BUMP=banana GITHUB_OUTPUT="$repo/github-output" \
      "$TEST_ROOT/compute-tag.sh"
  ) >"$repo/run.log" 2>&1 || status=$?

  if (( status != 0 )) && grep -q "Invalid force-bump" "$repo/run.log"; then
    record "invalid force-bump fails loudly" "rejected" "rejected"
  else
    record "invalid force-bump fails loudly" "rejected" "accepted"
  fi
}

assert_release_job_skips_without_created_tag() {
  local condition
  condition=$(python3 - "$WORKFLOW" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
release = next(i for i, line in enumerate(lines) if line == "  release:")
condition = next(line.strip() for line in lines[release + 1:] if line.strip().startswith("if:"))
print(condition)
PY
)
  record "release job is gated by created=true" \
    "if: needs.auto-tag.outputs.created == 'true'" "$condition"
}

extract_release_script

echo "=== Post-1.0 policy ==="
run_case "breaking defaults to minor" v2.3.4 5 "" v2.4.0 true feat \
  "feat!: change command contract" ""
run_case "docs-only creates no release" v2.3.4 5 "" "" false other \
  "docs: clarify usage" ""
run_case "fix creates patch" v2.3.4 5 "" v2.3.5 true fix \
  "fix: repair command" ""
run_case "perf creates patch" v2.3.4 5 "" v2.3.5 true perf \
  "perf: reduce allocations" ""
run_case "breaking trailer defaults to minor" v2.3.4 5 "" v2.4.0 true other \
  "refactor: change command contract" "BREAKING CHANGE: command output changed"
run_case "force major overrides breaking minor" v2.3.4 5 major v3.0.0 true feat \
  "feat!: change command contract" ""
run_case "force minor overrides patch" v2.3.4 5 minor v2.4.0 true fix \
  "fix: repair command" ""
run_case "force patch overrides breaking minor" v2.3.4 5 patch v2.3.5 true feat \
  "feat!: change command contract" ""
run_case "feat outranks fix across range" v2.3.4 5 "" v2.4.0 true feat \
  "fix: repair command" "" \
  "feat: add command" ""
run_case "breaking outranks feat across range" v2.3.4 5 "" v2.4.0 true feat \
  "feat: add command" "" \
  "refactor!: change command contract" "" \
  "fix: repair command" ""

echo ""
echo "=== Pre-1.0 graduation policy ==="
run_case "fix stays patch before 1.0" v0.2.14 5 "" v0.2.15 true fix \
  "fix: repair command" ""
run_case "feat stays minor before threshold" v0.2.14 5 "" v0.3.0 true feat \
  "feat: add command" ""
run_case "maintenance creates no release before 1.0" v0.2.14 5 "" "" false other \
  "test: expand coverage" ""
run_case "breaking still graduates at threshold" v0.5.4 5 "" v1.0.0 true feat \
  "feat!: change command contract" ""
run_case "custom threshold still graduates" v0.3.1 3 "" v1.0.0 true feat \
  "feat: add command" ""
run_case "disabled graduation stays in 0.x" v0.10.0 0 "" v0.11.0 true feat \
  "feat: add command" ""

echo ""
echo "=== Initial repository policy ==="
run_case "first feat creates v0.1.0" none 5 "" v0.1.0 true feat \
  "feat: add command" ""
run_case "first fix creates v0.0.1" none 5 "" v0.0.1 true fix \
  "fix: repair command" ""
run_case "first maintenance commit creates no tag" none 5 "" "" false other \
  "docs: explain command" ""

echo ""
echo "=== Validation and downstream gating ==="
assert_invalid_force_bump_fails
assert_release_job_skips_without_created_tag

echo ""
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
