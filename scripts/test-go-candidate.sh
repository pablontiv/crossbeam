#!/usr/bin/env bash
# Executes the reusable candidate workflow's shell logic against disposable fixtures.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
WORKFLOW="$ROOT/.github/workflows/go-candidate.yml"
TEST_ROOT=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

record() {
  local name=$1 expected=$2 actual=$3
  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS: %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL: %s -> expected %s, got %s\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

extract_step() {
  local name=$1 output=$2
  python3 - "$WORKFLOW" "$name" "$output" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
name = sys.argv[2]
output = Path(sys.argv[3])
step = next(i for i, line in enumerate(lines) if line == f"      - name: {name}")
run = next(i for i in range(step + 1, len(lines)) if lines[i] == "        run: |")
body = []
for line in lines[run + 1:]:
    if line and not line.startswith("          "):
        break
    body.append(line[10:] if line else "")
output.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + "\n".join(body) + "\n")
PY
  chmod +x "$output"
}

expect_status() {
  local name=$1 expected=$2 log=$3
  shift 3
  local status=0
  "$@" >"$log" 2>&1 || status=$?
  if [[ "$expected" == success && $status -eq 0 ]]; then
    record "$name" success success
  elif [[ "$expected" == failure && $status -ne 0 ]]; then
    record "$name" failure failure
  else
    record "$name" "$expected" "status-$status"
  fi
}

extract_step "Validate inputs" "$TEST_ROOT/validate-inputs.sh"
extract_step "Validate PR provenance" "$TEST_ROOT/validate-provenance.sh"
extract_step "Trust only stable caller tags" "$TEST_ROOT/trust-tags.sh"
extract_step "Validate source paths" "$TEST_ROOT/validate-paths.sh"
extract_step "Validate candidate and stage upload" "$TEST_ROOT/validate-candidate.sh"
extract_step "Smoke test linux amd64 candidate" "$TEST_ROOT/smoke.sh"

run_input_case() {
  local name=$1 expected=$2 repository=$3 source=$4 base=$5 pr=$6 binary=$7
  local go_file=${8:-go.mod} config=${9:-.goreleaser.yml}
  expect_status "$name" "$expected" "$TEST_ROOT/input-${name// /-}.log" \
    env SOURCE_REPOSITORY="$repository" SOURCE_SHA="$source" BASE_SHA="$base" \
    PR_NUMBER="$pr" BINARY_NAME="$binary" GO_VERSION_FILE="$go_file" \
    GORELEASER_CONFIG="$config" "$TEST_ROOT/validate-inputs.sh"
}

echo "=== Input validation ==="
run_input_case "numeric hexadecimal SHA remains a string" success owner/repo \
  1234567890123456789012345678901234567890 0987654321098765432109876543210987654321 17 tool
run_input_case "short source SHA rejected" failure owner/repo deadbeef \
  0987654321098765432109876543210987654321 17 tool
run_input_case "nonhex base SHA rejected" failure owner/repo \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz 17 tool
run_input_case "zero PR rejected" failure owner/repo \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 0 tool
run_input_case "empty binary rejected" failure owner/repo \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 1 ""
run_input_case "invalid repository rejected" failure ../repo \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 1 tool
run_input_case "traversing Go path rejected" failure owner/repo \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 1 tool ../go.mod
run_input_case "option-like config path rejected" failure owner/repo \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 1 tool go.mod --config
run_input_case "spaced config path rejected" failure owner/repo \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 1 tool go.mod "release config.yml"

echo ""
echo "=== Pull request provenance ==="
mkdir -p "$TEST_ROOT/mock-bin"
cat > "$TEST_ROOT/mock-bin/curl" <<'CURL'
#!/usr/bin/env bash
cat "$MOCK_PR_PAYLOAD"
CURL
chmod +x "$TEST_ROOT/mock-bin/curl"
make_pr_payload() {
  local path=$1 head_repo=$2 head_sha=$3 base_sha=$4
  python3 - "$path" "$head_repo" "$head_sha" "$base_sha" <<'PY'
import json
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(json.dumps({
    "head": {"repo": {"full_name": sys.argv[2]}, "sha": sys.argv[3]},
    "base": {"sha": sys.argv[4]},
}))
PY
}
run_provenance_case() {
  local name=$1 head_repo=$2 head_sha=$3 base_sha=$4 expected=$5
  local payload="$TEST_ROOT/pr-${name// /-}.json"
  make_pr_payload "$payload" "$head_repo" "$head_sha" "$base_sha"
  expect_status "$name" "$expected" "$TEST_ROOT/pr-${name// /-}.log" \
    env PATH="$TEST_ROOT/mock-bin:$PATH" MOCK_PR_PAYLOAD="$payload" GH_TOKEN=test-token \
    GITHUB_API_URL=https://api.github.test CALLER_REPOSITORY=base/repo \
    SOURCE_REPOSITORY=fork/repo SOURCE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    BASE_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb PR_NUMBER=42 \
    "$TEST_ROOT/validate-provenance.sh"
}
run_provenance_case "matching PR payload accepted" fork/repo \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb success
run_provenance_case "head repository mismatch rejected" other/repo \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb failure
run_provenance_case "head SHA mismatch rejected" fork/repo \
  cccccccccccccccccccccccccccccccccccccccc bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb failure
run_provenance_case "base SHA mismatch rejected" fork/repo \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa cccccccccccccccccccccccccccccccccccccccc failure
expect_status "missing API token rejected" failure "$TEST_ROOT/pr-no-token.log" \
  env PATH="$TEST_ROOT/mock-bin:$PATH" MOCK_PR_PAYLOAD="$TEST_ROOT/pr-matching-PR-payload-accepted.json" \
  GH_TOKEN= GITHUB_API_URL=https://api.github.test CALLER_REPOSITORY=base/repo \
  SOURCE_REPOSITORY=fork/repo SOURCE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  BASE_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb PR_NUMBER=42 \
  "$TEST_ROOT/validate-provenance.sh"

configure_git() {
  git -C "$1" config user.name Test
  git -C "$1" config user.email test@example.com
}

echo ""
echo "=== Trusted tag preparation ==="
base_work="$TEST_ROOT/base-work"
base_remote="$TEST_ROOT/base.git"
fork_work="$TEST_ROOT/fork-work"
fork_remote="$TEST_ROOT/fork.git"
source_work="$TEST_ROOT/source"
mkdir -p "$TEST_ROOT/home"
git init --bare "$base_remote" >/dev/null
git init -b main "$base_work" >/dev/null
configure_git "$base_work"
printf 'base\n' > "$base_work/history"
git -C "$base_work" add history
git -C "$base_work" commit -m "chore: base" >/dev/null
git -C "$base_work" tag v1.2.3
git -C "$base_work" tag v1.2.3-rc.1
git -C "$base_work" remote add origin "$base_remote"
git -C "$base_work" push origin main --tags >/dev/null
base_sha=$(git -C "$base_work" rev-parse HEAD)
git init --bare "$fork_remote" >/dev/null
git clone -b main "$base_remote" "$fork_work" >/dev/null 2>&1
configure_git "$fork_work"
printf 'source\n' >> "$fork_work/history"
git -C "$fork_work" add history
git -C "$fork_work" commit -m "feat: candidate" >/dev/null
git -C "$fork_work" tag v9.9.9
git -C "$fork_work" remote set-url origin "$fork_remote"
git -C "$fork_work" push origin main --tags >/dev/null
source_sha=$(git -C "$fork_work" rev-parse HEAD)
git clone --depth=1 --no-tags -b main "file://$fork_remote" "$source_work" >/dev/null 2>&1
git -C "$source_work" tag v8.8.8
record "fixture starts as a real shallow clone" true "$(git -C "$source_work" rev-parse --is-shallow-repository)"
HOME="$TEST_ROOT/home" git config --global url."file://$base_remote".insteadOf https://github.com/base/repo.git
prepare_output="$TEST_ROOT/prepare-output"
expect_status "shallow tag preparation succeeds" success "$TEST_ROOT/prepare.log" \
  env HOME="$TEST_ROOT/home" SOURCE_SHA="$source_sha" BASE_SHA="$base_sha" \
  BASE_REPOSITORY=base/repo PR_NUMBER=42 GITHUB_OUTPUT="$prepare_output" \
  bash -c "cd '$source_work' && '$TEST_ROOT/trust-tags.sh'"
record "source history is fully deepened" false "$(git -C "$source_work" rev-parse --is-shallow-repository)"
actual_tags=$(git -C "$source_work" tag -l | sort | tr '\n' ',')
record "fork tags removed and only stable base tags fetched" "v1.2.3," "$actual_tags"
record "core.abbrev is seven" 7 "$(git -C "$source_work" config core.abbrev)"
record "candidate version uses patch PR and seven-char SHA" \
  "1.2.4-pr.42.g${source_sha:0:7}" "$(sed -n 's/^candidate_version=//p' "$prepare_output")"

echo ""
echo "=== Source path validation ==="
path_fixture="$TEST_ROOT/source-paths"
mkdir -p "$path_fixture/config"
printf 'module example.test/tool\n\ngo 1.24.1\n' > "$path_fixture/go.mod"
printf 'version: 2\n' > "$path_fixture/config/release.yml"
path_output="$path_fixture/output"
expect_status "exact Go patch and regular config accepted" success "$path_fixture/valid.log" \
  env GO_VERSION_FILE=go.mod GORELEASER_CONFIG=config/release.yml GITHUB_OUTPUT="$path_output" \
  bash -c "cd '$path_fixture' && '$TEST_ROOT/validate-paths.sh'"
record "exact Go patch emitted" 1.24.1 "$(sed -n 's/^go_version=//p' "$path_output")"
printf 'module example.test/tool\n\ngo 1.24\n' > "$path_fixture/go-minor.mod"
expect_status "minor-only Go version rejected" failure "$path_fixture/minor.log" \
  env GO_VERSION_FILE=go-minor.mod GORELEASER_CONFIG=config/release.yml \
  GITHUB_OUTPUT="$path_fixture/minor-output" bash -c "cd '$path_fixture' && '$TEST_ROOT/validate-paths.sh'"
ln -s release.yml "$path_fixture/config/link.yml"
expect_status "symlinked config rejected" failure "$path_fixture/symlink.log" \
  env GO_VERSION_FILE=go.mod GORELEASER_CONFIG=config/link.yml \
  GITHUB_OUTPUT="$path_fixture/symlink-output" bash -c "cd '$path_fixture' && '$TEST_ROOT/validate-paths.sh'"

make_dist() {
  local dir=$1 mode=${2:-valid}
  mkdir -p "$dir/dist/payload"
  cat > "$dir/dist/payload/tool" <<'BIN'
#!/usr/bin/env bash
printf '%s\n' "candidate"
BIN
  chmod +x "$dir/dist/payload/tool"
  tar -C "$dir/dist/payload" -czf "$dir/dist/tool_linux_amd64.tar.gz" tool
  if [[ "$mode" == ambiguous ]]; then
    cp "$dir/dist/tool_linux_amd64.tar.gz" "$dir/dist/tool_linux_amd64_second.tar.gz"
  fi
  (
    cd "$dir/dist"
    sha256sum tool_linux_amd64.tar.gz > checksums.txt
    if [[ "$mode" == ambiguous ]]; then
      sha256sum tool_linux_amd64_second.tar.gz >> checksums.txt
    fi
  )
  python3 - "$dir" "$mode" <<'PY'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
mode = sys.argv[2]
sha = "a" * 40
version = "1.2.4-pr.42.gaaaaaaa"
commit = sha
if mode == "bad-revision":
    commit = "b" * 40
elif mode == "bad-version":
    version = "1.2.5-pr.42.gaaaaaaa"
elif mode == "dev-version":
    version = "1.2.4-dev-pr.42.gaaaaaaa"
metadata = {"version": version, "commit": commit}
(root / "dist/metadata.json").write_text(json.dumps(metadata))
archive_path = "dist/tool_linux_amd64.tar.gz"
if mode == "absolute-path":
    archive_path = str((root / archive_path).resolve())
elif mode == "traversal-path":
    (root / "outside.tar.gz").write_bytes((root / archive_path).read_bytes())
    archive_path = "dist/../outside.tar.gz"
elif mode == "symlink-path":
    (root / "dist/link.tar.gz").symlink_to("tool_linux_amd64.tar.gz")
    archive_path = "dist/link.tar.gz"
archives = [] if mode == "absent" else [{
    "type": "Archive", "name": "tool", "path": archive_path,
    "goos": "linux", "goarch": "amd64"
}]
if mode == "ambiguous":
    archives.append({
        "type": "Archive", "name": "tool-second", "path": "dist/tool_linux_amd64_second.tar.gz",
        "goos": "linux", "goarch": "amd64"
    })
checksum_path = "dist/checksums.txt"
if mode == "checksum-traversal":
    (root / "outside-checksums.txt").write_text((root / checksum_path).read_text())
    checksum_path = "dist/../outside-checksums.txt"
artifacts = archives + [{"type": "Checksum", "name": "checksums", "path": checksum_path}]
(root / "dist/artifacts.json").write_text(json.dumps({"artifacts": artifacts}))
PY
  case "$mode" in
    bad-checksum)
      sed -i.bak 's/^[0-9a-f]*/0000000000000000000000000000000000000000000000000000000000000000/' "$dir/dist/checksums.txt"
      rm -f "$dir/dist/checksums.txt.bak"
      ;;
    extra-checksum)
      printf '%064d  extra.tar.gz\n' 0 >> "$dir/dist/checksums.txt"
      ;;
    duplicate-checksum)
      cat "$dir/dist/checksums.txt" >> "$dir/dist/checksums.copy"
      cat "$dir/dist/checksums.copy" >> "$dir/dist/checksums.txt"
      rm "$dir/dist/checksums.copy"
      ;;
    missing-checksum)
      : > "$dir/dist/checksums.txt"
      ;;
  esac
}

run_candidate_case() {
  local name=$1 mode=$2 expected=$3 expected_version=${4:-1.2.4-pr.42.gaaaaaaa}
  local dir="$TEST_ROOT/candidate-${name// /-}"
  make_dist "$dir" "$mode"
  expect_status "$name" "$expected" "$dir/run.log" \
    env SOURCE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    BASE_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb PR_NUMBER=42 \
    BASE_VERSION=v1.2.3 CANDIDATE_VERSION="$expected_version" BINARY_NAME=tool \
    GITHUB_OUTPUT="$dir/github-output" bash -c "cd '$dir' && '$TEST_ROOT/validate-candidate.sh'"
}

echo ""
echo "=== Artifact and manifest validation ==="
run_candidate_case "valid artifacts" valid success
valid_dir="$TEST_ROOT/candidate-valid-artifacts"
manifest="$valid_dir/candidate-upload/candidate.json"
manifest_result=$(python3 - "$manifest" <<'PY'
import json
import sys
m = json.load(open(sys.argv[1]))
required = {"schema", "pr", "sha", "base", "base_version", "candidate_version", "archives"}
print("valid" if required == set(m) and m["schema"] == 1 and len(m["archives"]) == 1 else "invalid")
PY
)
record "candidate manifest has exact top-level schema" valid "$manifest_result"
upload_files=$(find "$valid_dir/candidate-upload" -maxdepth 1 -type f -exec basename {} \; | sort | tr '\n' ',')
record "upload staging contains only archives checksums and manifest" \
  "candidate.json,checksums.txt,tool_linux_amd64.tar.gz," "$upload_files"
run_candidate_case "archive absent fails closed" absent failure
run_candidate_case "linux archive ambiguity fails closed" ambiguous failure
run_candidate_case "incorrect checksum rejected" bad-checksum failure
run_candidate_case "extra checksum rejected" extra-checksum failure
run_candidate_case "duplicate checksum rejected" duplicate-checksum failure
run_candidate_case "missing checksum rejected" missing-checksum failure
run_candidate_case "absolute artifact path rejected" absolute-path failure
run_candidate_case "traversing artifact path rejected" traversal-path failure
run_candidate_case "symlinked artifact rejected" symlink-path failure
run_candidate_case "traversing checksum path rejected" checksum-traversal failure
run_candidate_case "incorrect metadata revision rejected" bad-revision failure
run_candidate_case "incorrect candidate version rejected" bad-version failure
run_candidate_case "dev candidate version rejected" dev-version failure "1.2.4-dev-pr.42.gaaaaaaa"

echo ""
echo "=== Smoke validation ==="
smoke_binary="$TEST_ROOT/fake-candidate"
cat > "$smoke_binary" <<'BIN'
#!/usr/bin/env bash
printf '%s\n' "tool ${FAKE_VERSION}"
BIN
chmod +x "$smoke_binary"
mkdir -p "$TEST_ROOT/fake-bin"
cat > "$TEST_ROOT/fake-bin/go" <<'GO'
#!/usr/bin/env bash
if [[ "$1" == version && "$2" == -m ]]; then
  printf '%s\n' "$2" $'\tbuild\tvcs.revision='"$FAKE_REVISION"
else
  exit 2
fi
GO
chmod +x "$TEST_ROOT/fake-bin/go"
run_smoke_case() {
  local name=$1 revision=$2 version=$3 expected=$4
  expect_status "$name" "$expected" "$TEST_ROOT/smoke-${name// /-}.log" \
    env PATH="$TEST_ROOT/fake-bin:$PATH" SMOKE_BINARY="$smoke_binary" \
    SOURCE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    CANDIDATE_VERSION=1.2.4-pr.42.gaaaaaaa FAKE_REVISION="$revision" \
    FAKE_VERSION="$version" "$TEST_ROOT/smoke.sh"
}
run_smoke_case "exact revision and version accepted" \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1.2.4-pr.42.gaaaaaaa success
run_smoke_case "binary revision mismatch rejected" \
  bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 1.2.4-pr.42.gaaaaaaa failure
run_smoke_case "binary version mismatch rejected" \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1.2.5-pr.42.gaaaaaaa failure
run_smoke_case "binary dev version rejected" \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1.2.4-pr.42.gaaaaaaa-dev failure

echo ""
echo "=== Static workflow security contract ==="
static_result=$(python3 - "$WORKFLOW" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
checks = {
    "workflow_call only": re.search(r"(?m)^  workflow_call:$", text) is not None and not re.search(r"(?m)^  (push|pull_request|workflow_dispatch|schedule):", text),
    "read-only permissions": re.search(r"(?ms)^permissions:\n  contents: read\n  pull-requests: read\n", text) is not None and "contents: write" not in text and "id-token:" not in text,
    "fixed runner": "runs-on: ubuntu-24.04" in text and "ubuntu-latest" not in text,
    "no secret context": "secrets." not in text and "GITHUB_TOKEN" not in text,
    "token confined to provenance": text.count("GH_TOKEN: ${{ github.token }}") == 1 and text.count("github.token") == 1,
    "credential-free exact checkout": "actions/checkout@" not in text and 'git fetch --no-tags --depth=1 origin "$SOURCE_SHA"' in text,
    "no pull request target": "pull_request_target" not in text,
    "fixed goreleaser": "version: 'v2.18.2'" in text and "release --snapshot --clean" in text and "--config=${{ steps.paths.outputs.goreleaser_config }}" in text,
    "safe upload": "retention-days: 7" in text and "if-no-files-found: error" in text and "path: candidate-upload/" in text,
}
uses = re.findall(r"(?m)^\s*uses:\s*([^\s#]+)", text)
checks["all actions pinned"] = bool(uses) and all(re.fullmatch(r"[^@]+@[0-9a-f]{40}", use) for use in uses)
failed = [name for name, ok in checks.items() if not ok]
print("valid" if not failed else "invalid:" + ",".join(failed))
PY
)
record "security and SHA pinning assertions" valid "$static_result"

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
