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

extract_smoke_script() {
  python3 - "$WORKFLOW" "$TEST_ROOT/smoke-test.sh" <<'PY'
from pathlib import Path
import sys

workflow = Path(sys.argv[1]).read_text().splitlines()
output = Path(sys.argv[2])

step = next(i for i, line in enumerate(workflow) if line == "      - name: Smoke test binary")
run = next(i for i in range(step + 1, len(workflow)) if workflow[i] == "        run: |")

body = []
for line in workflow[run + 1:]:
    if line and not line.startswith("          "):
        break
    body.append(line[10:] if line else "")

output.write_text("\n".join(body) + "\n")
PY
}

extract_checksum_script() {
  python3 - "$WORKFLOW" "$TEST_ROOT/verify-checksums.sh" <<'PY'
from pathlib import Path
import sys

workflow = Path(sys.argv[1]).read_text().splitlines()
output = Path(sys.argv[2])

step = next(i for i, line in enumerate(workflow) if line == "      - name: Verify release checksums")
run = next(i for i in range(step + 1, len(workflow)) if workflow[i] == "        run: |")

body = []
for line in workflow[run + 1:]:
    if line and not line.startswith("          "):
        break
    body.append(line[10:] if line else "")

output.write_text("\n".join(body) + "\n")
PY
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

make_test_binary() {
  local repo=$1 path=$2 mode=$3
  mkdir -p "$(dirname "$repo/$path")"
  cat > "$repo/$path" <<'SH'
#!/usr/bin/env bash
set -u
mode=$(cat "$0.mode")
printf '%s %s\n' "$0" "${1-}" >> "$INVOCATION_LOG"
case "$mode:${1-}" in
  version-flag:--version|fallback:version) exit 0 ;;
  *) exit 1 ;;
esac
SH
  printf '%s\n' "$mode" > "$repo/$path.mode"
}

run_smoke_case() {
  local name=$1 repo=$2 binary_name=$3 expected=$4
  local status=0
  local invocation_log="$repo/invocations.log"
  local run_log="$repo/smoke.log"
  : > "$invocation_log"

  (
    cd "$repo"
    BINARY_NAME="$binary_name" INVOCATION_LOG="$invocation_log" \
      bash "$TEST_ROOT/smoke-test.sh"
  ) >"$run_log" 2>&1 || status=$?

  local actual=success
  (( status == 0 )) || actual=failure
  record "$name" "$expected" "$actual"
}

assert_smoke_darwin_first_linux_selected() {
  local repo="$TEST_ROOT/smoke-platform-selection"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_darwin_arm64/tool" both-fail
  make_test_binary "$repo" "dist/tool_linux_amd64/tool" version-flag
  cat > "$repo/dist/artifacts.json" <<'JSON'
[
  {"type":"Binary","name":"tool","goos":"darwin","goarch":"arm64","path":"dist/tool_darwin_arm64/tool"},
  {"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64/tool"}
]
JSON

  run_smoke_case "smoke selects Linux when Darwin is first" "$repo" tool success
  local selected
  selected=$(sed 's/.*dist\///' "$repo/invocations.log")
  record "smoke executes selected Linux artifact" "tool_linux_amd64/tool --version" "$selected"
}

assert_smoke_version_flag_succeeds() {
  local repo="$TEST_ROOT/smoke-version-flag"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_linux_amd64/tool" version-flag
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64/tool"}]
JSON

  run_smoke_case "smoke accepts --version" "$repo" tool success
  local arguments
  arguments=$(sed 's/.* //' "$repo/invocations.log" | paste -sd, -)
  record "successful --version does not use fallback" "--version" "$arguments"
}

assert_smoke_version_fallback_succeeds() {
  local repo="$TEST_ROOT/smoke-version-fallback"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_linux_amd64/tool" fallback
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64/tool"}]
JSON

  run_smoke_case "smoke accepts version fallback" "$repo" tool success
  local arguments
  arguments=$(sed 's/.* //' "$repo/invocations.log" | paste -sd, -)
  record "fallback runs after failed --version" "--version,version" "$arguments"
}

assert_smoke_both_version_commands_fail() {
  local repo="$TEST_ROOT/smoke-both-fail"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_linux_amd64/tool" both-fail
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64/tool"}]
JSON

  run_smoke_case "smoke fails when both version commands fail" "$repo" tool failure
}

assert_smoke_zero_matches_fails() {
  local repo="$TEST_ROOT/smoke-zero-match"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_darwin_arm64/tool" version-flag
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"darwin","goarch":"arm64","path":"dist/tool_darwin_arm64/tool"}]
JSON

  run_smoke_case "smoke fails with zero matching artifacts" "$repo" tool failure
}

assert_smoke_multiple_matches_fail() {
  local repo="$TEST_ROOT/smoke-multiple-matches"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" "dist/tool_linux_amd64_a/tool" version-flag
  make_test_binary "$repo" "dist/tool_linux_amd64_b/tool" version-flag
  cat > "$repo/dist/artifacts.json" <<'JSON'
[
  {"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64_a/tool"},
  {"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/tool_linux_amd64_b/tool"}
]
JSON

  run_smoke_case "smoke fails with multiple matching artifacts" "$repo" tool failure
}

assert_smoke_missing_path_fails() {
  local repo="$TEST_ROOT/smoke-missing-path"
  mkdir -p "$repo/dist"
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64"}]
JSON

  run_smoke_case "smoke fails when artifact path is absent" "$repo" tool failure
}

assert_smoke_missing_file_fails() {
  local repo="$TEST_ROOT/smoke-missing-file"
  mkdir -p "$repo/dist"
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"dist/not-created/tool"}]
JSON

  run_smoke_case "smoke fails when artifact file is absent" "$repo" tool failure
}

assert_smoke_outside_dist_fails() {
  local repo="$TEST_ROOT/smoke-outside-dist"
  mkdir -p "$repo/dist"
  make_test_binary "$repo" tool version-flag
  cat > "$repo/dist/artifacts.json" <<'JSON'
[{"type":"Binary","name":"tool","goos":"linux","goarch":"amd64","path":"tool"}]
JSON

  run_smoke_case "smoke rejects artifact outside dist" "$repo" tool failure
}

assert_smoke_missing_manifest_fails() {
  local repo="$TEST_ROOT/smoke-missing-manifest"
  mkdir -p "$repo/dist"
  run_smoke_case "smoke fails when manifest is absent" "$repo" tool failure
}

assert_smoke_invalid_manifest_fails() {
  local repo="$TEST_ROOT/smoke-invalid-manifest"
  mkdir -p "$repo/dist"
  printf '%s\n' 'not json' > "$repo/dist/artifacts.json"
  run_smoke_case "smoke fails when manifest is invalid" "$repo" tool failure
}

assert_empty_binary_name_preserves_static_skip() {
  local metadata condition env_value
  metadata=$(python3 - "$WORKFLOW" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
step = next(i for i, line in enumerate(lines) if line == "      - name: Smoke test binary")
end = next(
    (i for i in range(step + 1, len(lines)) if lines[i].startswith("      - name:")),
    len(lines),
)
block = lines[step:end]
print(next(line.strip() for line in block if line.strip().startswith("if:")))
print(next(line.strip() for line in block if line.strip().startswith("BINARY_NAME:")))
PY
)
  condition=$(printf '%s\n' "$metadata" | sed -n '1p')
  env_value=$(printf '%s\n' "$metadata" | sed -n '2p')
  record "empty binary-name preserves static skip" "if: inputs.binary-name != ''" "$condition"
  record "binary-name is passed through env" 'BINARY_NAME: ${{ inputs.binary-name }}' "$env_value"
}

run_checksum_case() {
  local name=$1 fixture=$2 expected=$3
  local repo="$TEST_ROOT/checksum-${name//[^a-zA-Z0-9]/-}"
  local status=0 actual=success first_line
  mkdir -p "$repo/dist/intermediate"

  printf '%s\n' 'first asset' > "$repo/dist/first.tar.gz"
  printf '%s\n' 'second asset' > "$repo/dist/second.zip"
  printf '%s\n' 'intermediate binary' > "$repo/dist/intermediate/tool"
  cat > "$repo/dist/artifacts.json" <<'JSON'
[
  {"type":"Archive","name":"first","path":"dist/first.tar.gz"},
  {"type":"Archive","name":"second","path":"dist/second.zip"},
  {"type":"Binary","name":"tool","path":"dist/intermediate/tool"},
  {"type":"Metadata","name":"metadata","path":"dist/metadata.json"},
  {"type":"Checksum","name":"checksums","path":"dist/checksums.txt"}
]
JSON
  (cd "$repo/dist" && sha256sum first.tar.gz second.zip > checksums.txt)

  case "$fixture" in
    valid) ;;
    missing-file)
      rm "$repo/dist/checksums.txt"
      ;;
    missing-entry)
      first_line=$(head -n 1 "$repo/dist/checksums.txt")
      printf '%s\n' "$first_line" > "$repo/dist/checksums.txt"
      ;;
    tampered)
      printf '%s\n' 'tampered' >> "$repo/dist/first.tar.gz"
      ;;
    extra-existing)
      printf '%s\n' 'not published' > "$repo/dist/extra.tar.gz"
      (cd "$repo/dist" && sha256sum extra.tar.gz >> checksums.txt)
      ;;
    duplicate)
      first_line=$(head -n 1 "$repo/dist/checksums.txt")
      printf '%s\n' "$first_line" >> "$repo/dist/checksums.txt"
      ;;
    traversal)
      printf '%064d  ../outside.tar.gz\n' 0 >> "$repo/dist/checksums.txt"
      ;;
    absolute)
      printf '%064d  /tmp/absolute.tar.gz\n' 0 >> "$repo/dist/checksums.txt"
      ;;
    artifacts-shape)
      printf '%s\n' '{"artifacts": []}' > "$repo/dist/artifacts.json"
      ;;
    checksum-shape)
      python3 - "$repo/dist/artifacts.json" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
artifacts = json.loads(path.read_text())
artifacts[-1]["path"] = "dist/sums.txt"
path.write_text(json.dumps(artifacts))
PY
      ;;
    manifest-traversal)
      python3 - "$repo/dist/artifacts.json" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
artifacts = json.loads(path.read_text())
artifacts[0]["path"] = "dist/../first.tar.gz"
path.write_text(json.dumps(artifacts))
PY
      ;;
    symlink)
      cp "$repo/dist/first.tar.gz" "$repo/outside.tar.gz"
      rm "$repo/dist/first.tar.gz"
      ln -s ../outside.tar.gz "$repo/dist/first.tar.gz"
      ;;
    *)
      printf 'unknown checksum fixture: %s\n' "$fixture" >&2
      exit 1
      ;;
  esac

  (cd "$repo" && bash "$TEST_ROOT/verify-checksums.sh") >"$repo/checksum.log" 2>&1 || status=$?
  (( status == 0 )) || actual=failure
  record "$name" "$expected" "$actual"
}

assert_attestation_is_fail_closed_and_ordered() {
  local metadata order continue_on_error subject
  metadata=$(python3 - "$WORKFLOW" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
gate = next(i for i, line in enumerate(lines) if line == "      - name: Verify release checksums")
attest = next(i for i, line in enumerate(lines) if line == "      - name: Generate SLSA attestation")
end = next(
    (i for i in range(attest + 1, len(lines)) if lines[i].startswith("      - name:")),
    len(lines),
)
block = lines[attest:end]
print("gate-before-attestation" if gate < attest else "invalid-order")
print("present" if any(line.strip().startswith("continue-on-error:") for line in block) else "absent")
print(next((line.strip() for line in block if line.strip().startswith("subject-path:")), "missing"))
PY
)
  order=$(printf '%s\n' "$metadata" | sed -n '1p')
  continue_on_error=$(printf '%s\n' "$metadata" | sed -n '2p')
  subject=$(printf '%s\n' "$metadata" | sed -n '3p')
  record "checksum gate runs before attestation" "gate-before-attestation" "$order"
  record "attestation has no continue-on-error" "absent" "$continue_on_error"
  record "attestation subject remains checksums.txt" "subject-path: 'dist/checksums.txt'" "$subject"
}

extract_release_script
extract_smoke_script
extract_checksum_script

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
echo "=== Go release binary smoke test ==="
assert_smoke_darwin_first_linux_selected
assert_smoke_version_flag_succeeds
assert_smoke_version_fallback_succeeds
assert_smoke_both_version_commands_fail
assert_smoke_zero_matches_fails
assert_smoke_multiple_matches_fail
assert_smoke_missing_path_fails
assert_smoke_missing_file_fails
assert_smoke_outside_dist_fails
assert_smoke_missing_manifest_fails
assert_smoke_invalid_manifest_fails
assert_empty_binary_name_preserves_static_skip

echo ""
echo "=== Go release checksum and attestation gate ==="
run_checksum_case "valid archive checksums pass" valid success
run_checksum_case "missing checksum file fails" missing-file failure
run_checksum_case "missing archive checksum fails" missing-entry failure
run_checksum_case "tampered archive fails" tampered failure
run_checksum_case "extra existing checksum fails" extra-existing failure
run_checksum_case "duplicate checksum fails" duplicate failure
run_checksum_case "traversing checksum fails" traversal failure
run_checksum_case "absolute checksum fails" absolute failure
run_checksum_case "artifacts root shape mismatch fails" artifacts-shape failure
run_checksum_case "checksum artifact shape mismatch fails" checksum-shape failure
run_checksum_case "manifest traversal fails" manifest-traversal failure
run_checksum_case "symlink archive fails" symlink failure
assert_attestation_is_fail_closed_and_ordered

echo ""
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
